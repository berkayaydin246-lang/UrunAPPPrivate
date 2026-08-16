import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/ocr/services/ocr_request_headers.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart'
    show LegacyStagingScoringEvidence;
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

/// Retained-label-image basis OCR dry run.
///
/// STRICTLY DRY-RUN: zero Supabase writes, zero scoring/audit writes. Reads
/// `tmp/basis_enrichment_inventory.tsv` (the read-only inventory produced by
/// tool/final_basis_enrichment_inventory.dart), selects ONLY the 212
/// `retainedLabelImageAvailable` candidates, re-resolves each one's staging
/// evidence under the SAME strict linkage rules, and — only for candidates
/// with a genuinely usable retained nutrition-label image — calls the
/// EXISTING production OCR path (Supabase Edge Function `ocr/product-label`,
/// the same one lib/features/ocr/services/production_ocr_service.dart calls)
/// to determine whether an exact basis can be proven AND is consistent with
/// the persisted nutrition evidence for that product's scoring branch.
///
/// Never touches scoring math, category resolution rules, readiness
/// semantics, the public audit gate, or the trusted-basis contract — it only
/// CALLS the existing, frozen `ScoringReadinessEvaluator`/
/// `ProductScoringInputAdapter`/`ScoringCategoryResolver` public APIs to
/// determine which nutrition fields the candidate's own branch depends on,
/// exactly as historical_basis_revalidation_service.dart already does.
Future<void> main(List<String> arguments) async {
  late final _CliOptions options;
  try {
    options = _CliOptions.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('error=${error.message}');
    _printUsage();
    exitCode = 64;
    return;
  }
  if (options.help) {
    _printUsage();
    return;
  }

  final environment = Platform.environment;
  final supabaseUrl = environment['SUPABASE_URL']?.trim() ?? '';
  final serviceRoleKey =
      environment['SUPABASE_SERVICE_ROLE_KEY']?.trim() ??
      environment['SUPABASE_SERVICE_KEY']?.trim() ??
      '';
  final supabaseAnonKey = environment['SUPABASE_ANON_KEY']?.trim() ?? '';
  final baseUri = Uri.tryParse(supabaseUrl);
  if (baseUri == null ||
      baseUri.scheme != 'https' ||
      baseUri.host != '${options.projectRef}.supabase.co' ||
      serviceRoleKey.isEmpty) {
    stderr.writeln('error=invalid_or_missing_supabase_environment');
    exitCode = 78;
    return;
  }
  if (supabaseAnonKey.isEmpty) {
    stderr.writeln(
      'error=missing_supabase_anon_key '
      'the OCR Edge Function requires SUPABASE_ANON_KEY, never the service '
      'role key',
    );
    exitCode = 78;
    return;
  }

  final inputFile = File(options.inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('error=input_inventory_not_found path=${options.inputPath}');
    exitCode = 66;
    return;
  }
  final allInventoryRows = parseBasisEnrichmentInventoryTsv(
    inputFile.readAsStringSync(),
  );
  final selected = selectLabelImageCandidates(allInventoryRows);

  stdout.writeln('[selected]');
  stdout.writeln('manifest_candidates=${allInventoryRows.length}');
  stdout.writeln('selected_label_candidates=${selected.length}');
  if (selected.length != _expectedLabelImageCandidateCount) {
    stderr.writeln(
      'error=unexpected_selected_candidate_count '
      'expected=$_expectedLabelImageCandidateCount actual=${selected.length}',
    );
    exitCode = 65;
    return;
  }

  final bounded = options.limit == null
      ? selected
      : selected.take(options.limit!).toList(growable: false);

  final dataSource = _RestOcrCandidateDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  final ocrEdgeFunctionUri = baseUri.replace(
    path: '/functions/v1/ocr/product-label',
  );
  final ocrClient = _RestOcrProductLabelClient(
    edgeFunctionUri: ocrEdgeFunctionUri,
    supabaseAnonKey: supabaseAnonKey,
  );

  try {
    final productsById = await dataSource.fetchProductsByIds(
      bounded.map((row) => row.productId).toSet(),
    );
    final sourceUrls = productsById.values
        .map((product) => product.sourceUrl?.trim())
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet();
    final stagingByUrl = await dataSource.fetchStagingRowsBySourceUrl(
      sourceUrls,
    );

    final results = await _runBounded<OcrDryRunRow>(
      bounded.map((candidate) {
        return () async {
          final product = productsById[candidate.productId];
          final sourceUrl = product?.sourceUrl?.trim();
          final stagingMatches =
              (product != null && sourceUrl != null && sourceUrl.isNotEmpty)
              ? (stagingByUrl[sourceUrl] ?? const <OcrCandidateStagingRow>[])
              : const <OcrCandidateStagingRow>[];
          return classifyOcrDryRunCandidate(
            candidate: candidate,
            product: product,
            stagingMatches: stagingMatches,
            ocrClient: ocrClient,
          );
        };
      }).toList(growable: false),
      options.concurrency,
    );

    final outputLines = <String>[_ocrDryRunTsvHeader.join('\t')];
    final outcomeCounts = {
      for (final outcome in OcrDryRunOutcome.values) outcome: 0,
    };
    var per100g = 0;
    var per100ml = 0;
    var bothPresentSelectedPer100g = 0;
    var futureRecoverable = 0;

    for (final row in results) {
      outcomeCounts[row.outcome] = (outcomeCounts[row.outcome] ?? 0) + 1;
      if (row.resolvedExactBasis == 'per_100g') per100g++;
      if (row.resolvedExactBasis == 'per_100ml') per100ml++;
      if (row.bothPresent && row.resolvedExactBasis == 'per_100g') {
        bothPresentSelectedPer100g++;
      }
      if (row.futureRecoverable) futureRecoverable++;
      if (!options.quietPerProduct) {
        stdout.writeln(
          'product_id=${row.productId} outcome=${row.outcome.name} '
          'image_kind=${row.imageKind.name} basis=${row.resolvedExactBasis} '
          'consistency=${row.nutritionConsistency.name} '
          'recoverable=${row.futureRecoverable} code=${row.diagnosticCode}',
        );
      }
      outputLines.add(row.toTsvFields().join('\t'));
    }

    File(
      options.outputPath,
    ).writeAsStringSync('${outputLines.join('\n')}\n');

    final outcomeSum = OcrDryRunOutcome.values
        .map((outcome) => outcomeCounts[outcome] ?? 0)
        .fold(0, (sum, value) => sum + value);

    stdout.writeln('processed=${results.length}');
    stdout.writeln(
      'completed=${results.length == bounded.length && bounded.length == selected.length}',
    );
    stdout.writeln('reached_limit=${options.limit != null}');

    stdout.writeln('[outcomes]');
    for (final outcome in OcrDryRunOutcome.values) {
      stdout.writeln('${outcome.name}=${outcomeCounts[outcome]}');
    }
    stdout.writeln('outcome_counts_sum=$outcomeSum');
    stdout.writeln('outcome_counts_consistent=${outcomeSum == results.length}');

    stdout.writeln('[basis]');
    stdout.writeln('per_100g=$per100g');
    stdout.writeln('per_100ml=$per100ml');
    stdout.writeln(
      'both_present_selected_per_100g=$bothPresentSelectedPer100g',
    );

    stdout.writeln('[recovery]');
    final notRecoverable = results.length - futureRecoverable;
    stdout.writeln('future_recoverable=$futureRecoverable');
    stdout.writeln('not_recoverable=$notRecoverable');
    stdout.writeln(
      'recovery_counts_consistent='
      '${futureRecoverable + notRecoverable == results.length}',
    );
    stdout.writeln('output_file=${options.outputPath}');
  } on Object catch (error) {
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
    ocrClient.close();
  }
}

const int _expectedLabelImageCandidateCount = 212;

// ─────────────────────────────────────────────────────────────────────────
// Pure, testable classification logic (no I/O in this section other than
// calling the injected [OcrProductLabelClient] abstraction).
// ─────────────────────────────────────────────────────────────────────────

enum OcrDryRunOutcome {
  exactBasisAndNutritionConsistent,
  exactBasisButNutritionInsufficientToVerify,
  exactBasisButNutritionMismatch,
  genericOrAmbiguousBasis,
  nutritionLabelUnreadable,
  noUsableNutritionImage,
  identityUnusable,
  ocrRequestFailed,
  unexpectedError,
}

enum ImageKind { nutritionUrlColumn, nutritionLabelRoleCandidate, none }

enum OcrBasisClassification { per100g, per100ml, combinedAmbiguous, generic, none }

enum NutritionConsistencyResult { consistent, insufficientToVerify, mismatch, notApplicable }

/// One retained `product_staging` row's fields relevant to this OCR pass —
/// a purpose-built, self-contained wrapper (never modifies or extends the
/// frozen scoring models it references).
class OcrCandidateStagingRow {
  const OcrCandidateStagingRow({
    required this.evidence,
    this.imageNutritionUrl,
    this.nutritionLabelRoleCandidateUrl,
  });

  final LegacyStagingScoringEvidence evidence;
  final String? imageNutritionUrl;

  /// URL of the first `raw_source_payload.image_candidates` entry whose
  /// `role` (from scripts/product_import/web_scraper/image_scoring.py's
  /// classify_image_role()) is exactly `"nutrition_label"` — an
  /// existing-project-semantics-justified fallback (Section 2), used ONLY
  /// when [imageNutritionUrl] itself is empty. Never `image_ingredients_url`.
  final String? nutritionLabelRoleCandidateUrl;
}

class BasisEnrichmentInventoryCandidate {
  const BasisEnrichmentInventoryCandidate({
    required this.productId,
    required this.productName,
    required this.originalBasisBlockerGroup,
    required this.inventoryBucket,
  });

  final String productId;
  final String productName;
  final String originalBasisBlockerGroup;
  final String inventoryBucket;
}

const _labelImageBucketName = 'retainedLabelImageAvailable';

List<BasisEnrichmentInventoryCandidate> parseBasisEnrichmentInventoryTsv(
  String tsvContent,
) {
  final lines = const LineSplitter()
      .convert(tsvContent)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return const [];
  final rows = <BasisEnrichmentInventoryCandidate>[];
  for (final line in lines.skip(1)) {
    final fields = line.split('\t');
    if (fields.length < 4) continue;
    final productId = fields[0].trim();
    if (productId.isEmpty) continue;
    rows.add(
      BasisEnrichmentInventoryCandidate(
        productId: productId,
        productName: fields[1].trim(),
        originalBasisBlockerGroup: fields[2].trim(),
        inventoryBucket: fields[3].trim(),
      ),
    );
  }
  return rows;
}

List<BasisEnrichmentInventoryCandidate> selectLabelImageCandidates(
  List<BasisEnrichmentInventoryCandidate> allRows,
) {
  return allRows
      .where((row) => row.inventoryBucket == _labelImageBucketName)
      .toList(growable: false);
}

/// OCR basis-evidence contract fix: consumes the backend's OWN structured
/// `evidence_candidates.nutrition_basis` value — never classifies OCR raw
/// text itself. The backend (backend/ocr_service/main.py's
/// `_detect_nutrition_basis_candidate`) derives this exclusively from the
/// ISOLATED NUTRITION_FACTS `basis_declaration` line, never from the
/// ingredient-side RAW_TEXT (which describes the whole label and could
/// contain an unrelated "100 g" mention with nothing to do with the
/// nutrition table — the exact bug this fix closes). The backend's
/// `"both100gAnd100ml"` value means two genuinely SEPARATE, individually
/// explicit declarations were found; THIS layer — not the backend — owns
/// the frozen project rule for that case: select per_100g. A single
/// combined declaration ("100 g / ml") is reported by the backend as
/// `"unknown"`, exactly like every other generic/ambiguous form.
({OcrBasisClassification classification, bool bothPresent}) classifyOcrEvidenceBasis(
  String? nutritionBasis,
) {
  switch (nutritionBasis) {
    case 'per100g':
      return (classification: OcrBasisClassification.per100g, bothPresent: false);
    case 'per100ml':
      return (classification: OcrBasisClassification.per100ml, bothPresent: false);
    case 'both100gAnd100ml':
      return (classification: OcrBasisClassification.per100g, bothPresent: true);
    case null:
      return (classification: OcrBasisClassification.none, bothPresent: false);
    default:
      // 'unknown', 'perServing', or any other/unrecognized backend value —
      // never exact, never guessed.
      return (classification: OcrBasisClassification.generic, bothPresent: false);
  }
}

/// Section 2 image selection: priority 1 is the dedicated
/// `product_staging.image_nutrition_url` column; priority 2 (only when
/// justified by existing project semantics) is a retained image whose OWN
/// role classification is specifically `"nutrition_label"` — never
/// `image_ingredients_url`, which this pass never assumes contains
/// nutrition data.
({String? url, ImageKind kind}) resolveNutritionLabelImage(
  OcrCandidateStagingRow? selected,
) {
  if (selected == null) return (url: null, kind: ImageKind.none);
  final columnUrl = selected.imageNutritionUrl?.trim();
  if (columnUrl != null && columnUrl.isNotEmpty) {
    return (url: columnUrl, kind: ImageKind.nutritionUrlColumn);
  }
  final roleUrl = selected.nutritionLabelRoleCandidateUrl?.trim();
  if (roleUrl != null && roleUrl.isNotEmpty) {
    return (url: roleUrl, kind: ImageKind.nutritionLabelRoleCandidate);
  }
  return (url: null, kind: ImageKind.none);
}

/// Section 5's strict staging linkage/identity re-resolution — reuses the
/// SAME signature-based ambiguity rule
/// legacy_scoring_evidence_recovery.dart's `_recover()` already trusts
/// (`LegacyStagingScoringEvidence.evidenceSignature`), and the same
/// tie-break (lowest staging id) tool/final_basis_enrichment_inventory.dart
/// already established. Returns null (unusable) when ambiguous.
OcrCandidateStagingRow? selectUnambiguousStagingRow(
  List<OcrCandidateStagingRow> stagingMatches,
) {
  if (stagingMatches.isEmpty) return null;
  final signatures = stagingMatches
      .map((row) => row.evidence.evidenceSignature)
      .toSet();
  if (signatures.length > 1) return null;
  final sorted = [...stagingMatches]
    ..sort((a, b) => a.evidence.id.compareTo(b.evidence.id));
  return sorted.first;
}

const _requirementFieldNames = {
  ScoringRequirement.energyKj: 'energy_kj',
  ScoringRequirement.totalFat: 'total_fat',
  ScoringRequirement.saturatedFat: 'saturated_fat',
  ScoringRequirement.sugars: 'sugars',
  ScoringRequirement.salt: 'salt',
  ScoringRequirement.protein: 'protein',
  ScoringRequirement.fiber: 'fiber',
};

double? _fieldValue(dynamic nutrition, ScoringRequirement requirement) {
  return switch (requirement) {
    ScoringRequirement.energyKj => nutrition.energyKj.value,
    ScoringRequirement.totalFat => nutrition.totalFat.value,
    ScoringRequirement.saturatedFat => nutrition.saturatedFat.value,
    ScoringRequirement.sugars => nutrition.sugars.value,
    ScoringRequirement.salt => nutrition.salt.value,
    ScoringRequirement.protein => nutrition.protein.value,
    ScoringRequirement.fiber => nutrition.fiber.value,
    _ => null,
  };
}

bool _closeEnough(double a, double b) => (a - b).abs() <= 1e-6;

/// Resolves the "persisted nutrition evidence used for the candidate" —
/// reuses [ProductScoringInputAdapter.fromProduct] when the product
/// already carries persisted `scoring_evidence` (the
/// `legacy_untrusted_basis` population), which is the exact same evidence
/// EtiketlyPublicScoreAuditGate/ScoringReadinessEvaluator already treat as
/// authoritative. For candidates blocked during FRESH recovery (basis_
/// unknown / generic_per100_exact_unit_unproven / assumed_per100_untrusted
/// — no persisted `scoring_evidence` yet), falls back to the matched
/// staging row's own `nutrition_json` (the actual source
/// legacy_scoring_evidence_recovery.dart's `_recover()` would use),
/// resolving category the SAME way `ProductScoringInputAdapter.fromProduct`
/// already does for that legacy path (`ScoringCategoryResolver`,
/// `allowLegacyCompatibility: true`, matching production). Reuses frozen
/// scoring services for imports/calls only — never re-implements or
/// modifies them.
EtiketlyScoringInput resolveStoredInputForConsistencyCheck(
  Product product,
  OcrCandidateStagingRow? selectedStaging,
) {
  const adapter = ProductScoringInputAdapter();
  if (product.scoringEvidence != null) {
    return adapter.fromProduct(product);
  }
  const resolver = ScoringCategoryResolver();
  final categoryEvidence = resolver.resolve(
    ScoringCategoryResolverInput(
      categoryTags: product.categoryTags ?? const [],
      canonicalCategory: product.canonicalCategory,
      canonicalSubcategory: product.canonicalSubcategory,
      taxonomyProvenance: EvidenceProvenance.databaseImport,
      taxonomyVerification: EvidenceVerification.unverified,
      allowLegacyCompatibility: true,
    ),
  );
  final stagingNutritionJson = selectedStaging?.evidence.nutritionJson;
  final nutritionSource = stagingNutritionJson != null
      ? NutritionData.fromMap(stagingNutritionJson)
      : product.nutrition;
  return EtiketlyScoringInput(
    nutrition: adapter.fromLegacyNutrition(nutritionSource),
    nutritionBasis: NutritionBasis.unknown,
    productState: NutritionProductState.unknown,
    categoryEvidence: categoryEvidence,
  );
}

/// Section 4's dependency-aware nutrition-consistency gate, mirroring
/// HistoricalBasisRevalidationService's approach exactly: determine which
/// fields the STORED product's own resolved branch depends on (via
/// [ScoringReadinessEvaluator.requiredNutritionFields], never a second
/// hardcoded table), then compare only those fields between the stored
/// evidence and the OCR-extracted nutrition from the SAME declaration/
/// image. Missing required field -> insufficientToVerify (never treated as
/// agreement). Any mismatch -> mismatch (checked first — stronger,
/// definitive signal). Everything required present and equal ->
/// consistent. An unresolved/out-of-scope category (no dependency set at
/// all) fails closed to insufficientToVerify, never a false "consistent".
NutritionConsistencyResult evaluateNutritionConsistency({
  required EtiketlyScoringInput storedInput,
  required Map<String, dynamic>? ocrNutritionMap,
}) {
  const adapter = ProductScoringInputAdapter();
  const evaluator = ScoringReadinessEvaluator();
  final category = storedInput.categoryEvidence.resolvedCategory;
  final storedNutrition = storedInput.nutrition;
  final required = evaluator.requiredNutritionFields(category, storedNutrition);
  if (required.isEmpty) return NutritionConsistencyResult.insufficientToVerify;

  final ocrNutrition = adapter.fromLegacyNutrition(
    ocrNutritionMap == null ? null : NutritionData.fromMap(ocrNutritionMap),
  );

  var hasMismatch = false;
  var hasMissing = false;
  for (final requirement in _requirementFieldNames.keys) {
    if (!required.contains(requirement)) continue;
    final storedValue = _fieldValue(storedNutrition, requirement);
    if (storedValue == null) continue;
    final ocrValue = _fieldValue(ocrNutrition, requirement);
    if (ocrValue == null) {
      hasMissing = true;
    } else if (!_closeEnough(storedValue, ocrValue)) {
      hasMismatch = true;
    }
  }
  if (hasMismatch) return NutritionConsistencyResult.mismatch;
  if (hasMissing) return NutritionConsistencyResult.insufficientToVerify;
  return NutritionConsistencyResult.consistent;
}

class OcrDryRunRow {
  const OcrDryRunRow({
    required this.productId,
    required this.productName,
    required this.originalBasisBlockerGroup,
    required this.imageKind,
    required this.outcome,
    required this.resolvedExactBasis,
    required this.bothPresent,
    required this.nutritionConsistency,
    required this.futureRecoverable,
    required this.sourceIdentityValid,
    required this.diagnosticCode,
  });

  final String productId;
  final String productName;
  final String originalBasisBlockerGroup;
  final ImageKind imageKind;
  final OcrDryRunOutcome outcome;

  /// 'per_100g' / 'per_100ml' / '' (never exact).
  final String resolvedExactBasis;
  final bool bothPresent;
  final NutritionConsistencyResult nutritionConsistency;
  final bool futureRecoverable;
  final bool sourceIdentityValid;
  final String diagnosticCode;

  List<String> toTsvFields() => [
    productId,
    productName,
    originalBasisBlockerGroup,
    imageKind.name,
    outcome.name,
    resolvedExactBasis,
    bothPresent.toString(),
    nutritionConsistency.name,
    futureRecoverable.toString(),
    sourceIdentityValid.toString(),
    diagnosticCode,
  ];
}

const _ocrDryRunTsvHeader = [
  'product_id',
  'product_name',
  'original_basis_blocker_group',
  'image_kind',
  'ocr_outcome',
  'resolved_exact_basis',
  'both_100g_and_100ml_present',
  'nutrition_consistency',
  'future_recoverable',
  'source_identity_valid',
  'diagnostic_code',
];

/// Read-only client abstraction for the EXISTING production OCR path
/// (Supabase Edge Function `ocr/product-label`, forwarding to the Claude
/// Vision backend `/ocr/product-label` — see
/// lib/features/ocr/services/production_ocr_service.dart and
/// supabase/functions/ocr/index.ts). Injectable so
/// [classifyOcrDryRunCandidate] is fully testable without real network
/// access — see the fake implementation in the test file.
abstract class OcrProductLabelClient {
  Future<OcrProductLabelCallResult> extractProductLabel(String imageUrl);
}

class OcrProductLabelCallResult {
  const OcrProductLabelCallResult({
    required this.success,
    this.extractionStatus,
    this.evidenceNutritionBasis,
    this.evidenceNutritionBasisText,
    this.nutrition,
    this.errorType,
  });

  /// True only when a well-formed OCR response was received (regardless of
  /// [extractionStatus] — a successful HTTP round-trip that says
  /// `extraction_status: "failed"` is still `success: true` here; only
  /// transport/parsing failures are `success: false`).
  final bool success;
  final String? extractionStatus;

  /// The backend's own `evidence_candidates.nutrition_basis` value
  /// (`'per100g'` / `'per100ml'` / `'both100gAnd100ml'` / `'perServing'` /
  /// `'unknown'` / absent) — derived server-side from the ISOLATED
  /// NUTRITION_FACTS declaration text, never from ingredient RAW_TEXT. This
  /// tool never reads or classifies raw OCR text itself — see
  /// [classifyOcrEvidenceBasis].
  final String? evidenceNutritionBasis;

  /// The backend's matched evidence excerpt (diagnostics only — never
  /// re-classified here).
  final String? evidenceNutritionBasisText;
  final Map<String, dynamic>? nutrition;
  final String? errorType;
}

/// Section 3/4/5 orchestrator: resolves identity + image, calls OCR ONLY
/// when a usable image was found, classifies the result. Pure aside from
/// the single [OcrProductLabelClient] call — fully testable via a fake
/// client, no real I/O, no database write path exists anywhere in this
/// function or anything it calls.
Future<OcrDryRunRow> classifyOcrDryRunCandidate({
  required BasisEnrichmentInventoryCandidate candidate,
  required Product? product,
  required List<OcrCandidateStagingRow> stagingMatches,
  required OcrProductLabelClient ocrClient,
}) async {
  OcrDryRunRow blocked(
    OcrDryRunOutcome outcome, {
    required String code,
    ImageKind imageKind = ImageKind.none,
    bool sourceIdentityValid = false,
  }) {
    return OcrDryRunRow(
      productId: candidate.productId,
      productName: candidate.productName,
      originalBasisBlockerGroup: candidate.originalBasisBlockerGroup,
      imageKind: imageKind,
      outcome: outcome,
      resolvedExactBasis: '',
      bothPresent: false,
      nutritionConsistency: NutritionConsistencyResult.notApplicable,
      futureRecoverable: false,
      sourceIdentityValid: sourceIdentityValid,
      diagnosticCode: code,
    );
  }

  try {
    if (product == null) {
      return blocked(OcrDryRunOutcome.unexpectedError, code: 'product_not_found');
    }

    final selectedStaging = selectUnambiguousStagingRow(stagingMatches);
    if (selectedStaging == null) {
      return blocked(
        OcrDryRunOutcome.identityUnusable,
        code: stagingMatches.isEmpty
            ? 'no_staging_match'
            : 'ambiguous_staging_match',
      );
    }
    final hasStrictIdentifier =
        _nonEmpty(product.barcode) ||
        (product.sourceUrl != null &&
            _extractMigrosCanonicalIdentifier(product.sourceUrl!) != null);
    if (!hasStrictIdentifier) {
      return blocked(
        OcrDryRunOutcome.identityUnusable,
        code: 'no_strict_source_identifier',
      );
    }

    final image = resolveNutritionLabelImage(selectedStaging);
    if (image.url == null) {
      return blocked(
        OcrDryRunOutcome.noUsableNutritionImage,
        code: 'no_nutrition_label_image',
        sourceIdentityValid: true,
      );
    }

    final ocrResult = await ocrClient.extractProductLabel(image.url!);
    if (!ocrResult.success) {
      return blocked(
        OcrDryRunOutcome.ocrRequestFailed,
        code: ocrResult.errorType ?? 'ocr_request_failed',
        imageKind: image.kind,
        sourceIdentityValid: true,
      );
    }
    if (ocrResult.extractionStatus == 'failed' ||
        ocrResult.extractionStatus == null) {
      return blocked(
        OcrDryRunOutcome.nutritionLabelUnreadable,
        code: 'extraction_unreadable',
        imageKind: image.kind,
        sourceIdentityValid: true,
      );
    }

    final basis = classifyOcrEvidenceBasis(ocrResult.evidenceNutritionBasis);
    if (basis.classification != OcrBasisClassification.per100g &&
        basis.classification != OcrBasisClassification.per100ml) {
      return OcrDryRunRow(
        productId: candidate.productId,
        productName: candidate.productName,
        originalBasisBlockerGroup: candidate.originalBasisBlockerGroup,
        imageKind: image.kind,
        outcome: OcrDryRunOutcome.genericOrAmbiguousBasis,
        resolvedExactBasis: '',
        bothPresent: false,
        nutritionConsistency: NutritionConsistencyResult.notApplicable,
        futureRecoverable: false,
        sourceIdentityValid: true,
        diagnosticCode: ocrResult.evidenceNutritionBasis ?? 'no_evidence_candidates',
      );
    }

    final resolvedBasis = basis.classification == OcrBasisClassification.per100g
        ? 'per_100g'
        : 'per_100ml';

    final storedInput = resolveStoredInputForConsistencyCheck(
      product,
      selectedStaging,
    );
    final consistency = evaluateNutritionConsistency(
      storedInput: storedInput,
      ocrNutritionMap: ocrResult.nutrition,
    );

    final outcome = switch (consistency) {
      NutritionConsistencyResult.consistent =>
        OcrDryRunOutcome.exactBasisAndNutritionConsistent,
      NutritionConsistencyResult.mismatch =>
        OcrDryRunOutcome.exactBasisButNutritionMismatch,
      NutritionConsistencyResult.insufficientToVerify ||
      NutritionConsistencyResult.notApplicable =>
        OcrDryRunOutcome.exactBasisButNutritionInsufficientToVerify,
    };

    return OcrDryRunRow(
      productId: candidate.productId,
      productName: candidate.productName,
      originalBasisBlockerGroup: candidate.originalBasisBlockerGroup,
      imageKind: image.kind,
      outcome: outcome,
      resolvedExactBasis: resolvedBasis,
      bothPresent: basis.bothPresent,
      nutritionConsistency: consistency,
      futureRecoverable:
          outcome == OcrDryRunOutcome.exactBasisAndNutritionConsistent,
      sourceIdentityValid: true,
      diagnosticCode: consistency.name,
    );
  } on Object catch (error) {
    return blocked(
      OcrDryRunOutcome.unexpectedError,
      code: error.runtimeType.toString(),
    );
  }
}

bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;

/// Same canonical Migros URL product identifier extraction already used by
/// the basis-revalidation identity gate
/// (MigrosBasisSourceFetcher.extractCanonicalIdentifier) — duplicated here
/// as a tiny, self-contained pure regex (not importing the fetcher class,
/// which pulls in dart:io/Process bridging this dry-run never needs) so
/// this file's identity check matches that gate's definition exactly.
String? _extractMigrosCanonicalIdentifier(String sourceUrl) {
  final match = RegExp(
    r'-p-([a-z0-9]+)',
    caseSensitive: false,
  ).firstMatch(sourceUrl);
  return match?.group(1)?.toLowerCase();
}

// ─────────────────────────────────────────────────────────────────────────
// Bounded concurrency helper.
// ─────────────────────────────────────────────────────────────────────────

Future<List<T>> _runBounded<T>(
  List<Future<T> Function()> tasks,
  int concurrency,
) async {
  final results = List<T?>.filled(tasks.length, null);
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final index = next;
      next += 1;
      if (index >= tasks.length) return;
      results[index] = await tasks[index]();
    }
  }

  await Future.wait(
    List.generate(
      concurrency.clamp(1, tasks.isEmpty ? 1 : tasks.length),
      (_) => worker(),
    ),
  );
  return results.cast<T>();
}

// ─────────────────────────────────────────────────────────────────────────
// CLI / REST plumbing (I/O only below this point).
// ─────────────────────────────────────────────────────────────────────────

class _TransientOcrFailure implements Exception {
  _TransientOcrFailure(this.code);
  final String code;
}

class _RestOcrProductLabelClient implements OcrProductLabelClient {
  _RestOcrProductLabelClient({
    required this.edgeFunctionUri,
    required this.supabaseAnonKey,
  });

  final Uri edgeFunctionUri;
  final String supabaseAnonKey;
  static const _timeout = Duration(seconds: 45);
  static const _maxAttempts = 3;
  final HttpClient _client = HttpClient();

  void close() => _client.close(force: true);

  @override
  Future<OcrProductLabelCallResult> extractProductLabel(String imageUrl) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        return await _attempt(imageUrl).timeout(_timeout);
      } on TimeoutException {
        if (attempt >= _maxAttempts) {
          return const OcrProductLabelCallResult(
            success: false,
            errorType: 'timeout',
          );
        }
      } on _TransientOcrFailure catch (error) {
        if (attempt >= _maxAttempts) {
          return OcrProductLabelCallResult(success: false, errorType: error.code);
        }
      } catch (error) {
        return OcrProductLabelCallResult(
          success: false,
          errorType: error.runtimeType.toString(),
        );
      }
      await Future.delayed(Duration(milliseconds: 500 * attempt));
    }
    return const OcrProductLabelCallResult(
      success: false,
      errorType: 'unexpected_retry_exhaustion',
    );
  }

  Future<OcrProductLabelCallResult> _attempt(String imageUrl) async {
    final request = await _client.postUrl(edgeFunctionUri);
    request.headers.contentType = ContentType.json;
    final authHeaders = buildOcrRequestHeaders(
      baseUrl: edgeFunctionUri.toString(),
      supabaseAnonKey: supabaseAnonKey,
    );
    authHeaders.forEach((key, value) {
      if (value == null) return;
      if (key.toLowerCase() == 'content-type') return;
      request.headers.set(key, value.toString());
    });
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'etiketly-final-retained-label-basis-ocr-dry-run/1',
    );
    request.write(jsonEncode({'image_url': imageUrl, 'language_hint': 'tr'}));

    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    if (response.statusCode >= 500) {
      throw _TransientOcrFailure('http_${response.statusCode}');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return OcrProductLabelCallResult(
        success: false,
        errorType: 'http_${response.statusCode}',
      );
    }

    Map<String, dynamic>? decoded;
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map) decoded = Map<String, dynamic>.from(parsed);
    } catch (_) {
      // decoded stays null — handled below.
    }
    if (decoded == null) {
      return const OcrProductLabelCallResult(
        success: false,
        errorType: 'malformed_response',
      );
    }

    // OCR basis-evidence contract fix: this tool never reads or classifies
    // `ingredients.raw_text` — nutrition-basis evidence comes ONLY from the
    // backend's own structured `evidence_candidates`, which the backend
    // derives exclusively from the isolated NUTRITION_FACTS declaration
    // (see backend/ocr_service/main.py's
    // `_build_product_label_evidence_candidates`).
    final evidenceCandidates = decoded['evidence_candidates'];
    final nutrition = decoded['nutrition'];
    return OcrProductLabelCallResult(
      success: true,
      extractionStatus: decoded['extraction_status']?.toString(),
      evidenceNutritionBasis: evidenceCandidates is Map
          ? evidenceCandidates['nutrition_basis']?.toString()
          : null,
      evidenceNutritionBasisText: evidenceCandidates is Map
          ? evidenceCandidates['nutrition_basis_text']?.toString()
          : null,
      nutrition: nutrition is Map ? Map<String, dynamic>.from(nutrition) : null,
    );
  }
}

class _CliOptions {
  const _CliOptions({
    required this.help,
    required this.projectRef,
    required this.inputPath,
    required this.outputPath,
    required this.limit,
    required this.concurrency,
    required this.quietPerProduct,
  });

  final bool help;
  final String projectRef;
  final String inputPath;
  final String outputPath;
  final int? limit;
  final int concurrency;
  final bool quietPerProduct;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(
        help: true,
        projectRef: '',
        inputPath: '',
        outputPath: '',
        limit: null,
        concurrency: 4,
        quietPerProduct: false,
      );
    }

    final projectRef = _requiredValue(arguments, '--project-ref');
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef)) {
      throw const FormatException('invalid --project-ref');
    }

    final limit = _intValue(arguments, '--limit');
    if (limit != null && limit < 1) {
      throw const FormatException('--limit must be at least 1');
    }
    final concurrency = _intValue(arguments, '--concurrency') ?? 4;
    if (concurrency < 1 || concurrency > 16) {
      throw const FormatException('--concurrency must be between 1 and 16');
    }

    return _CliOptions(
      help: false,
      projectRef: projectRef,
      inputPath:
          _value(arguments, '--input') ??
          'tmp/basis_enrichment_inventory.tsv',
      outputPath:
          _value(arguments, '--output') ??
          'tmp/retained_label_basis_ocr_dry_run.tsv',
      limit: limit,
      concurrency: concurrency,
      quietPerProduct: arguments.contains('--quiet-per-product'),
    );
  }

  static String _requiredValue(List<String> arguments, String name) {
    final value = _value(arguments, name);
    if (value == null || value.isEmpty) {
      throw FormatException('$name is required');
    }
    return value;
  }

  static int? _intValue(List<String> arguments, String name) {
    final raw = _value(arguments, name);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null) throw FormatException('$name must be an integer');
    return value;
  }

  static String? _value(List<String> arguments, String name) {
    final index = arguments.indexOf(name);
    if (index < 0) return null;
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('-')) {
      throw FormatException('$name requires a value');
    }
    return arguments[index + 1];
  }

  static void _validateArguments(List<String> arguments) {
    const flags = {'--help', '-h', '--quiet-per-product'};
    const valueOptions = {
      '--project-ref',
      '--input',
      '--output',
      '--limit',
      '--concurrency',
    };
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (flags.contains(argument)) continue;
      if (!valueOptions.contains(argument)) {
        throw const FormatException('unknown_argument');
      }
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        throw FormatException('$argument requires a value');
      }
      index++;
    }
  }
}

class _RestOcrCandidateDataSource {
  _RestOcrCandidateDataSource({
    required this.baseUri,
    required this.serviceRoleKey,
  });

  final Uri baseUri;
  final String serviceRoleKey;
  final HttpClient _client = HttpClient();

  void close() => _client.close(force: true);

  Future<Map<String, Product>> fetchProductsByIds(Set<String> ids) async {
    final result = <String, Product>{};
    final ordered = ids.toList()..sort();
    for (var offset = 0; offset < ordered.length; offset += 50) {
      final end = (offset + 50).clamp(0, ordered.length);
      final filter = ordered
          .sublist(offset, end)
          .map(_postgrestQuoted)
          .join(',');
      final rows = await _getRows('products', {
        'select':
            'id,name,barcode,source,source_url,image_url,scoring_evidence,'
            'category_tags,canonical_category,canonical_subcategory,'
            'nutrition_text,verification_status,created_at,updated_at',
        'id': 'in.($filter)',
      });
      for (final row in rows) {
        final product = Product.fromJson(row);
        result[product.id] = product;
      }
    }
    return result;
  }

  Future<Map<String, List<OcrCandidateStagingRow>>> fetchStagingRowsBySourceUrl(
    Set<String> sourceUrls,
  ) async {
    final result = <String, List<OcrCandidateStagingRow>>{};
    final ordered = sourceUrls.toList()..sort();
    for (var offset = 0; offset < ordered.length; offset += 20) {
      final end = (offset + 20).clamp(0, ordered.length);
      final filter = ordered
          .sublist(offset, end)
          .map(_postgrestQuoted)
          .join(',');
      final rows = await _getRows('product_staging', {
        'select':
            'id,source_url,source,ingredients_source,ingredients_text,'
            'nutrition_source,nutrition_json,raw_source_payload,'
            'image_nutrition_url',
        'source_url': 'in.($filter)',
        'order': 'id.asc',
      });
      for (final row in rows) {
        final id = row['id'];
        final sourceUrl = row['source_url'];
        if (id is! String || sourceUrl is! String) continue;
        final normalizedSourceUrl = sourceUrl.trim();
        if (normalizedSourceUrl.isEmpty) continue;
        final payload = _map(row['raw_source_payload']);
        final warnings = payload?['nutrition_warnings'];
        final evidence = LegacyStagingScoringEvidence(
          id: id,
          sourceUrl: normalizedSourceUrl,
          nutritionBasis: _string(payload?['nutrition_basis']),
          nutritionWarnings: warnings is List
              ? warnings.map((value) => value.toString())
              : const [],
          nutritionProductState: _string(payload?['nutrition_product_state']),
          source: _string(row['source']),
          ingredientsSource: _string(row['ingredients_source']),
          ingredientsRaw: _string(payload?['ingredients_raw']),
          ingredientsText: _string(row['ingredients_text']),
          ingredientsQuality: _string(payload?['ingredients_quality']),
          nutritionSource: _string(row['nutrition_source']),
          nutritionStrategy: _string(payload?['nutrition_strategy']),
          nutritionJson: _map(row['nutrition_json']),
        );
        final stagingRow = OcrCandidateStagingRow(
          evidence: evidence,
          imageNutritionUrl: _string(row['image_nutrition_url']),
          nutritionLabelRoleCandidateUrl: _nutritionLabelRoleCandidateUrl(
            payload,
          ),
        );
        result.putIfAbsent(normalizedSourceUrl, () => []).add(stagingRow);
      }
    }
    return result;
  }

  static String? _nutritionLabelRoleCandidateUrl(
    Map<String, dynamic>? payload,
  ) {
    final candidates = payload?['image_candidates'];
    if (candidates is! List) return null;
    for (final candidate in candidates) {
      if (candidate is! Map) continue;
      if (candidate['role'] == 'nutrition_label') {
        final url = candidate['url'];
        if (url is String && url.trim().isNotEmpty) return url.trim();
      }
    }
    return null;
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static String _postgrestQuoted(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  Future<List<Map<String, dynamic>>> _getRows(
    String table,
    Map<String, String> query,
  ) async {
    final response = await _request('GET', _uri(table, query));
    if (response is! List) throw const FormatException('expected_rows');
    return response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return baseUri.replace(path: '/rest/v1/$path', queryParameters: query);
  }

  Future<Object?> _request(String method, Uri uri) async {
    final request = await _client.openUrl(method, uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
      ..set('apikey', serviceRoleKey)
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(
        HttpHeaders.userAgentHeader,
        'etiketly-final-retained-label-basis-ocr-dry-run/1',
      );
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Remote request failed with HTTP ${response.statusCode}.',
      );
    }
    if (responseBody.trim().isEmpty) return null;
    return jsonDecode(responseBody);
  }
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run tool/final_retained_label_basis_ocr_dry_run.dart --project-ref <ref>

Options:
  --project-ref <ref>   Supabase project ref (20 lowercase alnum chars). Required.
  --input <path>         Inventory TSV path (default: tmp/basis_enrichment_inventory.tsv).
  --output <path>        Dry-run TSV output path (default: tmp/retained_label_basis_ocr_dry_run.tsv).
  --limit <n>            Process only the first n selected candidates (local testing only).
  --concurrency <n>      Bounded OCR request concurrency, 1-16 (default: 4).
  --quiet-per-product     Suppress per-product stdout lines; summary only.

STRICTLY DRY-RUN: zero Supabase writes, zero scoring/audit writes. External
requests are made ONLY to retained nutrition-label image URLs via the
existing production OCR path (Supabase Edge Function ocr/product-label).

Credentials are read only from SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (or
SUPABASE_SERVICE_KEY), and SUPABASE_ANON_KEY. They are never printed.
''');
}
