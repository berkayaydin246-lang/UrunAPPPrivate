import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart'
    show LegacyStagingScoringEvidence;
import 'package:food_analyzer_app/features/scoring/application/migros_basis_source_fetcher.dart'
    show MigrosBasisSourceFetcher;

/// Basis-only enrichment inventory pass.
///
/// STRICTLY READ-ONLY: this tool makes zero database writes and zero
/// external HTTP requests. It exists to answer exactly one question about
/// the 1265 products in `tmp/basis_only_enrichment_candidates.tsv` (every
/// product blocked ONLY on unproven nutrition basis, per the frozen
/// scoring/readiness pipeline): how many of them already have RETAINED
/// source evidence (staging rows, raw scraped text, retained image
/// references) that could prove an exact per-100g/per-100mL basis WITHOUT
/// fetching the internet again.
///
/// Never touches scoring math, readiness semantics, the taxonomy resolver,
/// the lifecycle runner, or the public audit gate — it only reads
/// `products`/`product_staging` and reports.
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
  final baseUri = Uri.tryParse(supabaseUrl);
  if (baseUri == null ||
      baseUri.scheme != 'https' ||
      baseUri.host != '${options.projectRef}.supabase.co' ||
      serviceRoleKey.isEmpty) {
    stderr.writeln('error=invalid_or_missing_supabase_environment');
    exitCode = 78;
    return;
  }

  final inputFile = File(options.inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('error=input_manifest_not_found path=${options.inputPath}');
    exitCode = 66;
    return;
  }
  final manifest = parseBasisEnrichmentManifest(inputFile.readAsStringSync());
  if (manifest.isEmpty) {
    stderr.writeln('error=input_manifest_empty_or_unparseable');
    exitCode = 65;
    return;
  }

  final dataSource = _RestBasisEnrichmentInventoryDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  try {
    final productsById = await dataSource.fetchProductsByIds(
      manifest.map((entry) => entry.productId).toSet(),
    );
    final sourceUrls = productsById.values
        .map((product) => product.sourceUrl?.trim())
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet();
    final stagingByUrl = await dataSource.fetchStagingRowsBySourceUrls(
      sourceUrls,
    );

    final rows = <BasisEnrichmentInventoryRow>[];
    final counts = {for (final bucket in BasisEnrichmentBucket.values) bucket: 0};
    final byGroupCounts = <String, Map<BasisEnrichmentBucket, int>>{};
    var identityAmbiguousOrUnusable = 0;
    var unexpectedErrors = 0;
    final outputLines = <String>[
      [
        'product_id',
        'product_name',
        'original_basis_blocker_group',
        'inventory_bucket',
        'has_exact_basis_evidence',
        'has_raw_basis_text',
        'raw_basis_normalized_summary',
        'has_label_image',
        'has_product_image',
        'has_source_url',
        'has_strict_source_identity',
        'matched_staging',
        'source',
        'source_fetched_at',
      ].join('\t'),
    ];

    for (final entry in manifest) {
      final product = productsById[entry.productId];
      if (product == null) {
        unexpectedErrors++;
        outputLines.add(
          [
            entry.productId,
            entry.productName,
            entry.originalBasisBlockerGroup,
            'unexpected_error_product_not_found',
            'false',
            'false',
            'none',
            'false',
            'false',
            'false',
            'false',
            'false',
            '',
            '',
          ].join('\t'),
        );
        continue;
      }

      final sourceUrl = product.sourceUrl?.trim();
      final stagingMatches =
          (sourceUrl != null && sourceUrl.isNotEmpty)
              ? (stagingByUrl[sourceUrl] ?? const [])
              : const <BasisEnrichmentStagingRow>[];

      final row = classifyBasisEnrichmentCandidate(
        productId: entry.productId,
        productName: entry.productName,
        originalBasisBlockerGroup: entry.originalBasisBlockerGroup,
        productBarcode: product.barcode,
        productSource: product.source,
        productSourceUrl: product.sourceUrl,
        productImageUrl: product.imageUrl,
        stagingMatches: stagingMatches,
      );
      rows.add(row);
      counts[row.bucket] = (counts[row.bucket] ?? 0) + 1;
      if (row.identityAmbiguousOrUnusable) identityAmbiguousOrUnusable++;
      final groupCounts = byGroupCounts.putIfAbsent(
        entry.originalBasisBlockerGroup,
        () => {for (final bucket in BasisEnrichmentBucket.values) bucket: 0},
      );
      groupCounts[row.bucket] = (groupCounts[row.bucket] ?? 0) + 1;

      if (!options.quietPerProduct) {
        stdout.writeln(
          'product_id=${row.productId} '
          'bucket=${row.bucket.name} '
          'group=${row.originalBasisBlockerGroup} '
          'exact_basis=${row.hasExactBasisEvidence} '
          'raw_text_exact=${row.rawBasisNormalizedSummary} '
          'label_image=${row.hasLabelImage} '
          'ambiguous=${row.identityAmbiguousOrUnusable}',
        );
      }
      outputLines.add(row.toTsvFields().join('\t'));
    }

    File(
      options.outputPath,
    ).writeAsStringSync('${outputLines.join('\n')}\n');

    final countsSum =
        BasisEnrichmentBucket.values
            .map((bucket) => counts[bucket] ?? 0)
            .fold(0, (sum, value) => sum + value) +
        unexpectedErrors;

    stdout.writeln('[basis_enrichment_inventory_summary]');
    stdout.writeln('total_candidates=${manifest.length}');
    stdout.writeln(
      'retained_exact_basis=${counts[BasisEnrichmentBucket.retainedExactBasis]}',
    );
    stdout.writeln(
      'retained_raw_basis_text_exact='
      '${counts[BasisEnrichmentBucket.retainedRawBasisTextExact]}',
    );
    stdout.writeln(
      'retained_label_image_available='
      '${counts[BasisEnrichmentBucket.retainedLabelImageAvailable]}',
    );
    stdout.writeln(
      'retained_product_image_only='
      '${counts[BasisEnrichmentBucket.retainedProductImageOnly]}',
    );
    stdout.writeln(
      'source_url_available=${counts[BasisEnrichmentBucket.sourceUrlAvailable]}',
    );
    stdout.writeln(
      'no_useful_retained_source='
      '${counts[BasisEnrichmentBucket.noUsefulRetainedSource]}',
    );
    stdout.writeln('identity_ambiguous_or_unusable=$identityAmbiguousOrUnusable');
    stdout.writeln('unexpected_errors=$unexpectedErrors');
    stdout.writeln('counts_sum=$countsSum');
    stdout.writeln('counts_consistent=${countsSum == manifest.length}');

    stdout.writeln('[by_original_manifest_group]');
    for (final group in [
      'legacy_untrusted_basis',
      'basis_unknown',
      'generic_per100_exact_unit_unproven',
      'assumed_per100_untrusted',
    ]) {
      final groupCounts = byGroupCounts[group];
      if (groupCounts == null) {
        stdout.writeln('$group: no_candidates');
        continue;
      }
      stdout.writeln(
        '$group: '
        'exact_basis=${groupCounts[BasisEnrichmentBucket.retainedExactBasis]} '
        'raw_text_exact='
        '${groupCounts[BasisEnrichmentBucket.retainedRawBasisTextExact]} '
        'label_image='
        '${groupCounts[BasisEnrichmentBucket.retainedLabelImageAvailable]} '
        'product_image_only='
        '${groupCounts[BasisEnrichmentBucket.retainedProductImageOnly]} '
        'source_url_only='
        '${groupCounts[BasisEnrichmentBucket.sourceUrlAvailable]} '
        'no_useful_source='
        '${groupCounts[BasisEnrichmentBucket.noUsefulRetainedSource]}',
      );
    }
    stdout.writeln('output_file=${options.outputPath}');
  } on Object catch (error) {
    // Report only the type: remote errors can contain request metadata.
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Pure, testable classification logic (no I/O below this point).
// ─────────────────────────────────────────────────────────────────────────

/// Section 3 of the basis-enrichment inventory pass — the six mutually
/// exclusive, strongest-evidence-wins inventory buckets. Never a proof of
/// exact basis by itself except [retainedExactBasis]/
/// [retainedRawBasisTextExact] — the others only describe what a FUTURE,
/// separate enrichment step could use, never something this read-only tool
/// concludes on its own.
enum BasisEnrichmentBucket {
  retainedExactBasis,
  retainedRawBasisTextExact,
  retainedLabelImageAvailable,
  retainedProductImageOnly,
  sourceUrlAvailable,
  noUsefulRetainedSource,
}

/// Result of re-classifying ONE retained raw basis-declaration text string
/// against the strict exact-unit rule (Section 4) — mirrors
/// scripts/product_import/web_scraper/nutrition_parser.py's detect_basis()
/// g/mL precedence exactly (combined-pattern checked first), but is a
/// wholly independent, read-only, non-authoritative re-check: it never
/// writes a basis value anywhere and is never wired into scoring/basis
/// parsing — see [classifyRawBasisText].
enum RawBasisTextClassification { exactGrams, exactMl, combinedAmbiguous, generic, none }

/// One retained `product_staging` row's fields relevant to this inventory.
/// Deliberately narrower than [LegacyStagingScoringEvidence] (which has no
/// notion of retained images or the raw basis-declaration text) — wraps it
/// rather than extending/modifying it.
class BasisEnrichmentStagingRow {
  const BasisEnrichmentStagingRow({
    required this.evidence,
    this.rawBasisText,
    this.imageIngredientsUrl,
    this.imageNutritionUrl,
    this.imageFrontUrl,
    this.scrapedAt,
    this.createdAt,
  });

  final LegacyStagingScoringEvidence evidence;
  final String? rawBasisText;
  final String? imageIngredientsUrl;
  final String? imageNutritionUrl;
  final String? imageFrontUrl;
  final String? scrapedAt;
  final String? createdAt;
}

class BasisEnrichmentInventoryRow {
  const BasisEnrichmentInventoryRow({
    required this.productId,
    required this.productName,
    required this.originalBasisBlockerGroup,
    required this.bucket,
    required this.hasExactBasisEvidence,
    required this.hasRawBasisText,
    required this.rawBasisNormalizedSummary,
    required this.hasLabelImage,
    required this.hasProductImage,
    required this.hasSourceUrl,
    required this.hasStrictSourceIdentity,
    required this.matchedStaging,
    required this.identityAmbiguousOrUnusable,
    this.source,
    this.sourceFetchedAt,
  });

  final String productId;
  final String productName;
  final String originalBasisBlockerGroup;
  final BasisEnrichmentBucket bucket;
  final bool hasExactBasisEvidence;
  final bool hasRawBasisText;
  final String rawBasisNormalizedSummary;
  final bool hasLabelImage;
  final bool hasProductImage;
  final bool hasSourceUrl;
  final bool hasStrictSourceIdentity;
  final bool matchedStaging;
  final bool identityAmbiguousOrUnusable;
  final String? source;
  final String? sourceFetchedAt;

  List<String> toTsvFields() => [
    productId,
    productName,
    originalBasisBlockerGroup,
    bucket.name,
    hasExactBasisEvidence.toString(),
    hasRawBasisText.toString(),
    rawBasisNormalizedSummary,
    hasLabelImage.toString(),
    hasProductImage.toString(),
    hasSourceUrl.toString(),
    hasStrictSourceIdentity.toString(),
    matchedStaging.toString(),
    source ?? '',
    sourceFetchedAt ?? '',
  ];
}

/// Section 3/4/5 core: classifies ONE manifest candidate into exactly one
/// [BasisEnrichmentBucket], strongest evidence first. Deliberately takes NO
/// parameter for the product's OWN `scoring_evidence` nutrition-basis enum
/// or provenance — per Section 3's "Important" rule, a bare legacy enum
/// (however it was tagged, including `databaseImport`) is never evidence,
/// so it is structurally impossible for this function to use it: the only
/// source of exact-basis proof is [stagingMatches], independent retained
/// source evidence.
BasisEnrichmentInventoryRow classifyBasisEnrichmentCandidate({
  required String productId,
  required String productName,
  required String originalBasisBlockerGroup,
  required String? productBarcode,
  required String? productSource,
  required String? productSourceUrl,
  required String? productImageUrl,
  required List<BasisEnrichmentStagingRow> stagingMatches,
}) {
  final matchedStaging = stagingMatches.isNotEmpty;

  // Section 5: reuse the SAME strict-linkage ambiguity signal
  // legacy_scoring_evidence_recovery.dart's _recover() already uses
  // (LegacyStagingScoringEvidence.evidenceSignature) — if the matched rows
  // genuinely disagree, none of their evidence is usable. Never guessed.
  final signatures = stagingMatches
      .map((row) => row.evidence.evidenceSignature)
      .toSet();
  final identityAmbiguous = matchedStaging && signatures.length > 1;

  final usableStaging = identityAmbiguous
      ? const <BasisEnrichmentStagingRow>[]
      : ([...stagingMatches]
          ..sort((a, b) => a.evidence.id.compareTo(b.evidence.id)));
  final selected = usableStaging.isEmpty ? null : usableStaging.first;

  final normalizedBasis = selected?.evidence.nutritionBasis
      ?.trim()
      .toLowerCase();
  final hasExactBasisEvidence =
      normalizedBasis == 'per_100g' || normalizedBasis == 'per_100ml';

  final rawText = selected?.rawBasisText;
  final rawClassification = classifyRawBasisText(rawText);
  final hasRawBasisTextExact =
      rawClassification == RawBasisTextClassification.exactGrams ||
      rawClassification == RawBasisTextClassification.exactMl;
  final hasRawBasisText = _nonEmpty(rawText);

  final hasLabelImage =
      _nonEmpty(selected?.imageIngredientsUrl) ||
      _nonEmpty(selected?.imageNutritionUrl);
  final hasProductImage =
      hasLabelImage ||
      _nonEmpty(selected?.imageFrontUrl) ||
      _nonEmpty(productImageUrl);
  final hasSourceUrl =
      _nonEmpty(productSourceUrl) || _nonEmpty(selected?.evidence.sourceUrl);
  final hasStrictSourceIdentity =
      _nonEmpty(productBarcode) ||
      (productSourceUrl != null &&
          MigrosBasisSourceFetcher.extractCanonicalIdentifier(
                productSourceUrl,
              ) !=
              null);

  final BasisEnrichmentBucket bucket;
  if (hasExactBasisEvidence) {
    bucket = BasisEnrichmentBucket.retainedExactBasis;
  } else if (hasRawBasisTextExact) {
    bucket = BasisEnrichmentBucket.retainedRawBasisTextExact;
  } else if (hasLabelImage) {
    bucket = BasisEnrichmentBucket.retainedLabelImageAvailable;
  } else if (hasProductImage) {
    bucket = BasisEnrichmentBucket.retainedProductImageOnly;
  } else if (hasSourceUrl) {
    bucket = BasisEnrichmentBucket.sourceUrlAvailable;
  } else {
    bucket = BasisEnrichmentBucket.noUsefulRetainedSource;
  }

  return BasisEnrichmentInventoryRow(
    productId: productId,
    productName: productName,
    originalBasisBlockerGroup: originalBasisBlockerGroup,
    bucket: bucket,
    hasExactBasisEvidence: hasExactBasisEvidence,
    hasRawBasisText: hasRawBasisText,
    rawBasisNormalizedSummary: rawClassification.name,
    hasLabelImage: hasLabelImage,
    hasProductImage: hasProductImage,
    hasSourceUrl: hasSourceUrl,
    hasStrictSourceIdentity: hasStrictSourceIdentity,
    matchedStaging: matchedStaging,
    identityAmbiguousOrUnusable: identityAmbiguous,
    source: productSource ?? selected?.evidence.source,
    sourceFetchedAt: selected?.scrapedAt ?? selected?.createdAt,
  );
}

bool _nonEmpty(String? value) => value != null && value.trim().isNotEmpty;

final _combinedBasisPattern = RegExp(r'100\s*g[r]?\s*/\s*m\s*l\b');
final _gramsBasisPattern = RegExp(r'100\s*g[r]?\b');
final _mlBasisPattern = RegExp(r'100\s*m\s*l\b');

const _asciiFoldTable = {
  'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'İ': 'i',
  'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
  'â': 'a', 'î': 'i', 'û': 'u',
};

/// Read-only mirror of nutrition_parser.py's detect_basis() g/mL
/// precedence, scoped to ONLY the exact-vs-combined distinction this
/// inventory needs (Section 4): combined ("100 g / ml") is checked before
/// either single-unit pattern, so it is never misread as exact. Never used
/// to write a basis value — see [BasisEnrichmentInventoryRow].
RawBasisTextClassification classifyRawBasisText(String? text) {
  final trimmed = text?.trim() ?? '';
  if (trimmed.isEmpty) return RawBasisTextClassification.none;
  final folded = _asciiFold(trimmed);
  final hasCombined = _combinedBasisPattern.hasMatch(folded);
  final hasGrams = _gramsBasisPattern.hasMatch(folded) && !hasCombined;
  final hasMl = _mlBasisPattern.hasMatch(folded) && !hasCombined;
  if (hasCombined || (hasGrams && hasMl)) {
    return RawBasisTextClassification.combinedAmbiguous;
  }
  if (hasGrams) return RawBasisTextClassification.exactGrams;
  if (hasMl) return RawBasisTextClassification.exactMl;
  return RawBasisTextClassification.generic;
}

String _asciiFold(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_asciiFoldTable[char] ?? char);
  }
  return buffer.toString().toLowerCase();
}

// ─────────────────────────────────────────────────────────────────────────
// Manifest (tmp/basis_only_enrichment_candidates.tsv) parsing.
// ─────────────────────────────────────────────────────────────────────────

class BasisEnrichmentManifestEntry {
  const BasisEnrichmentManifestEntry({
    required this.productId,
    required this.productName,
    required this.outcome,
    required this.blockers,
    required this.originalBasisBlockerGroup,
  });

  final String productId;
  final String productName;
  final String outcome;
  final String blockers;
  final String originalBasisBlockerGroup;
}

/// The exact, closed set of `blockers` strings the manifest's generating
/// query can produce (see the taxonomy/trust-correction passes this
/// manifest was derived from) — a plain, exhaustive mapping, never a fuzzy
/// "contains" match, so an unrecognized value fails closed rather than
/// being silently miscategorized.
String classifyOriginalBasisBlockerGroup(String blockers) {
  switch (blockers.trim()) {
    case 'nutrition:unknownNutritionBasis':
      return 'legacy_untrusted_basis';
    case 'basis_unknown':
      return 'basis_unknown';
    case 'basis_generic_ambiguous_exact_unit_unproven,basis_unit_ambiguous':
      return 'generic_per100_exact_unit_unproven';
    case 'basis_unknown_assumed_per100':
      return 'assumed_per100_untrusted';
    default:
      return 'unrecognized_blocker_group';
  }
}

List<BasisEnrichmentManifestEntry> parseBasisEnrichmentManifest(
  String tsvContent,
) {
  final lines = const LineSplitter()
      .convert(tsvContent)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.isEmpty) return const [];
  final entries = <BasisEnrichmentManifestEntry>[];
  for (final line in lines.skip(1)) {
    final fields = line.split('\t');
    if (fields.length < 4) continue;
    final productId = fields[0].trim();
    final productName = fields[1].trim();
    final outcome = fields[2].trim();
    final blockers = fields[3].trim();
    if (productId.isEmpty) continue;
    entries.add(
      BasisEnrichmentManifestEntry(
        productId: productId,
        productName: productName,
        outcome: outcome,
        blockers: blockers,
        originalBasisBlockerGroup: classifyOriginalBasisBlockerGroup(blockers),
      ),
    );
  }
  return entries;
}

// ─────────────────────────────────────────────────────────────────────────
// CLI / REST plumbing (I/O only below this point). Zero writes: every
// request this data source issues is a GET against `products` or
// `product_staging`. Never calls any external (non-Supabase) host.
// ─────────────────────────────────────────────────────────────────────────

class _CliOptions {
  const _CliOptions({
    required this.help,
    required this.projectRef,
    required this.inputPath,
    required this.outputPath,
    required this.quietPerProduct,
  });

  final bool help;
  final String projectRef;
  final String inputPath;
  final String outputPath;
  final bool quietPerProduct;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(
        help: true,
        projectRef: '',
        inputPath: '',
        outputPath: '',
        quietPerProduct: false,
      );
    }

    final projectRef = _requiredValue(arguments, '--project-ref');
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef)) {
      throw const FormatException('invalid --project-ref');
    }

    return _CliOptions(
      help: false,
      projectRef: projectRef,
      inputPath:
          _value(arguments, '--input') ??
          'tmp/basis_only_enrichment_candidates.tsv',
      outputPath:
          _value(arguments, '--output') ??
          'tmp/basis_enrichment_inventory.tsv',
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

  static String? _value(List<String> arguments, String name) {
    final index = arguments.indexOf(name);
    if (index < 0) return null;
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw FormatException('$name requires a value');
    }
    return arguments[index + 1];
  }

  static void _validateArguments(List<String> arguments) {
    const flags = {'--help', '-h', '--quiet-per-product'};
    const valueOptions = {'--project-ref', '--input', '--output'};
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

class _RestBasisEnrichmentInventoryDataSource {
  _RestBasisEnrichmentInventoryDataSource({
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
            'id,name,barcode,source,source_url,image_url,verification_status,'
            'created_at,updated_at',
        'id': 'in.($filter)',
      });
      for (final row in rows) {
        final product = Product.fromJson(row);
        result[product.id] = product;
      }
    }
    return result;
  }

  Future<Map<String, List<BasisEnrichmentStagingRow>>>
  fetchStagingRowsBySourceUrls(Set<String> sourceUrls) async {
    final result = <String, List<BasisEnrichmentStagingRow>>{};
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
            'image_front_url,image_url,image_ingredients_url,'
            'image_nutrition_url,created_at',
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
        final stagingRow = BasisEnrichmentStagingRow(
          evidence: evidence,
          rawBasisText: _string(payload?['nutrition_basis_raw_text']),
          imageIngredientsUrl: _string(row['image_ingredients_url']),
          imageNutritionUrl: _string(row['image_nutrition_url']),
          imageFrontUrl:
              _string(row['image_front_url']) ?? _string(row['image_url']),
          scrapedAt: _string(payload?['scraped_at']),
          createdAt: _string(row['created_at']),
        );
        result.putIfAbsent(normalizedSourceUrl, () => []).add(stagingRow);
      }
    }
    return result;
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
        'etiketly-final-basis-enrichment-inventory/1',
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
  dart run tool/final_basis_enrichment_inventory.dart --project-ref <ref>

Options:
  --project-ref <ref>   Supabase project ref (20 lowercase alnum chars). Required.
  --input <path>        Manifest TSV path (default: tmp/basis_only_enrichment_candidates.tsv).
  --output <path>       Inventory TSV output path (default: tmp/basis_enrichment_inventory.tsv).
  --quiet-per-product    Suppress per-product stdout lines; summary only.

Strictly read-only: zero database writes, zero external HTTP requests.
Credentials are read only from SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
(or SUPABASE_SERVICE_KEY). They are never printed.
''');
}
