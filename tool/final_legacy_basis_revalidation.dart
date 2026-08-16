import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/basis_revalidation_candidate_planner.dart';
import 'package:food_analyzer_app/features/scoring/application/basis_source_fetcher.dart';
import 'package:food_analyzer_app/features/scoring/application/historical_basis_revalidation_service.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_recovery_lifecycle_runner.dart';
import 'package:food_analyzer_app/features/scoring/application/migros_basis_source_fetcher.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/basis_revalidation_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Sections F-L of the basis remediation pass: the historical basis
/// revalidation CLI.
///
/// This tool never writes scoring math, never invents evidence, and never
/// touches history — it drives exactly ONE new capability: independently
/// re-proving the exact per-100g/per-100mL unit for products whose only
/// historical evidence is generically ambiguous (see
/// [HistoricalBasisRevalidationService]), through the SAME central
/// [ProductScoringLifecycleService] write path every other evidence write
/// in this system already uses.
///
/// Default mode is a ZERO-WRITE dry-run. Apply mode (--apply) additionally
/// requires an explicit confirmation flag and only ever persists evidence
/// for [BasisRevalidationOutcome.exactBasisRevalidated] candidates — no
/// numeric score, no audit snapshot is ever fabricated directly here.
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

  final dataSource = _RestBasisRevalidationDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  final fetchersBySourcePrefix = <String, BasisSourceFetcher>{
    'migros': const MigrosBasisSourceFetcher(),
  };

  try {
    // Candidate SELECTION always runs as a read-only dry-run scan,
    // regardless of whether this tool's own mode is --apply — Section J
    // never writes anything while planning.
    final runner = LegacyScoringRecoveryLifecycleRunner(dataSource: dataSource);
    final closure = await runner.runFullCatalogueClosure(
      dryRun: true,
      limit: options.scanLimit,
      batchSize: options.batchSize,
    );
    if (closure.halted) {
      stderr.writeln('error=candidate_scan_halted_before_completion');
      exitCode = 1;
      return;
    }

    final currentCandidateIds = closure.results
        .where((r) => classifyFinalState(r) == ScoringFinalState.current)
        .map((r) => r.productId)
        .toSet();
    final productsById = <String, Product>{};
    for (final id in currentCandidateIds) {
      final product = await dataSource.fetchProduct(id);
      if (product != null) productsById[id] = product;
    }

    final candidates = planBasisRevalidationCandidates(
      closureResults: closure.results,
      productsById: productsById,
    );
    final bounded = candidates.take(options.maxFetches).toList(growable: false);

    stdout.writeln('[candidate_selection]');
    stdout.writeln('scan_total_examined=${closure.totalExamined}');
    stdout.writeln('total_candidates=${candidates.length}');
    stdout.writeln(
      'current_public_basis_unverified='
      '${candidates.where((c) => c.reason == BasisRevalidationCandidateReason.currentPublicBasisUnverified).length}',
    );
    stdout.writeln(
      'otherwise_scoreable_basis_only='
      '${candidates.where((c) => c.reason == BasisRevalidationCandidateReason.otherwiseReadyExceptBasis).length}',
    );
    stdout.writeln('bounded_for_this_run=${bounded.length} (--max-fetches=${options.maxFetches})');

    final results = <BasisRevalidationResult>[];
    for (final candidate in bounded) {
      final product =
          productsById[candidate.productId] ??
          await dataSource.fetchProduct(candidate.productId);
      if (product == null) {
        results.add(
          BasisRevalidationResult(
            productId: candidate.productId,
            outcome: BasisRevalidationOutcome.unexpectedError,
            errorType: 'product_not_found',
          ),
        );
        continue;
      }
      final source = product.source ?? '';
      final prefix = source.startsWith('web_scraper:')
          ? source.substring('web_scraper:'.length)
          : source;
      final fetcher = fetchersBySourcePrefix[prefix];
      final service = fetcher == null
          ? null
          : HistoricalBasisRevalidationService(
              fetcher: fetcher,
              extractCanonicalIdentifier:
                  MigrosBasisSourceFetcher.extractCanonicalIdentifier,
            );
      final result = service == null
          ? BasisRevalidationResult(
              productId: product.id,
              outcome: BasisRevalidationOutcome.sourceUnavailable,
              source: source,
              sourceUrl: product.sourceUrl,
            )
          : await service.revalidate(product);
      results.add(result);

      if (!options.quietPerProduct) {
        stdout.writeln(_formatResult(result));
      }

      if (options.apply &&
          result.outcome == BasisRevalidationOutcome.exactBasisRevalidated) {
        await _applyRevalidatedBasis(
          product: product,
          result: result,
          dataSource: dataSource,
        );
      }
    }

    stdout.writeln(_formatSummary(results));
  } on Object catch (error) {
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

/// Apply-mode write: constructs a new evidence object identical to the
/// product's existing evidence in every field EXCEPT nutrition basis,
/// which is replaced with the independently revalidated exact value,
/// tagged `declaredLabel` provenance (source-proven — see
/// legacy_scoring_evidence_recovery.dart's identical convention). Routes
/// through the ordinary [ProductScoringLifecycleService] — never writes
/// `scoring_evidence` directly, never fabricates a numeric score or audit
/// snapshot itself. The product's prior evidence and every historical
/// audit snapshot remain untouched; this only ever changes what
/// `products.scoring_evidence` currently points to and may insert one new
/// current audit row.
Future<void> _applyRevalidatedBasis({
  required Product product,
  required BasisRevalidationResult result,
  required _RestBasisRevalidationDataSource dataSource,
}) async {
  final existing = product.scoringEvidence;
  if (existing == null || result.revalidatedBasis == null) return;
  final revalidated = existing.copyWith(
    nutritionBasis: result.revalidatedBasis,
    nutritionBasisEvidence: EvidenceValue<NutritionBasis>(
      value: result.revalidatedBasis!,
      provenance: EvidenceProvenance.declaredLabel,
      verification: EvidenceVerification.verified,
    ),
  );
  final lifecycle = ProductScoringLifecycleService(dataSource: dataSource);
  await lifecycle.processCurrent(
    product.id,
    triggerSource: ScoreAuditTriggerSource.controlledBackfill,
    evidenceResolver: (currentProduct, _) async {
      return ProductScoringEvidenceResolution(
        evidence: revalidated,
        blockerReasons: const [],
      );
    },
  );
}

String _formatResult(BasisRevalidationResult result) {
  return [
    'product_id=${result.productId}',
    'outcome=${result.outcome.name}',
    'source=${result.source ?? '-'}',
    'normalized_basis=${result.normalizedBasis ?? '-'}',
    'revalidated_basis=${result.revalidatedBasis?.name ?? '-'}',
    'identity_method=${result.identityVerificationMethod ?? '-'}',
    'nutrition_mismatch_fields=${result.nutritionMismatchFields.isEmpty ? '-' : result.nutritionMismatchFields.join(',')}',
    'nutrition_missing_required_fields=${result.nutritionMissingRequiredFields.isEmpty ? '-' : result.nutritionMissingRequiredFields.join(',')}',
    'adapter_version=${result.adapterVersion ?? '-'}',
    if (result.errorType != null) 'error_type=${result.errorType}',
  ].join(' ');
}

String _formatSummary(List<BasisRevalidationResult> results) {
  final counts = {for (final outcome in BasisRevalidationOutcome.values) outcome: 0};
  for (final result in results) {
    counts[result.outcome] = counts[result.outcome]! + 1;
  }
  final lines = <String>[
    '[basis_revalidation_summary]',
    'total_processed=${results.length}',
    for (final outcome in BasisRevalidationOutcome.values)
      '${outcome.name}=${counts[outcome]}',
  ];
  return lines.join('\n');
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run tool/final_legacy_basis_revalidation.dart --dry-run --project-ref <ref> --scan-limit <n> --max-fetches <n>
  dart run tool/final_legacy_basis_revalidation.dart --apply --confirm-apply-legacy-basis-revalidation --project-ref <ref> --scan-limit <n> --max-fetches <n>

Options:
  --dry-run / --apply           Exactly one required. Default is dry-run.
  --confirm-apply-legacy-basis-revalidation   Required alongside --apply.
  --project-ref <ref>           Supabase project ref (20 lowercase alnum chars).
  --scan-limit <n>               Bound on the read-only candidate-selection scan.
  --batch-size <n>               Scan page size (default 50, max 100).
  --max-fetches <n>               Bound on live source fetches this run performs.
  --quiet-per-product            Suppress per-product lines; summary only.
''');
}

const _maxScanLimit = 10000;
const _maxFetchesLimit = 2000;

class _CliOptions {
  const _CliOptions({
    required this.help,
    required this.apply,
    required this.projectRef,
    required this.scanLimit,
    required this.batchSize,
    required this.maxFetches,
    required this.quietPerProduct,
  });

  final bool help;
  final bool apply;
  final String projectRef;
  final int scanLimit;
  final int batchSize;
  final int maxFetches;
  final bool quietPerProduct;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(
        help: true,
        apply: false,
        projectRef: '',
        scanLimit: 0,
        batchSize: 50,
        maxFetches: 0,
        quietPerProduct: false,
      );
    }

    final explicitDryRun = arguments.contains('--dry-run');
    final apply = arguments.contains('--apply');
    if (explicitDryRun && apply) {
      throw const FormatException('choose exactly one of --dry-run or --apply');
    }
    if (!explicitDryRun && !apply) {
      throw const FormatException('one of --dry-run or --apply is required');
    }
    if (apply &&
        !arguments.contains('--confirm-apply-legacy-basis-revalidation')) {
      throw const FormatException(
        '--apply requires --confirm-apply-legacy-basis-revalidation',
      );
    }

    final scanLimit = _intValue(arguments, '--scan-limit');
    if (scanLimit == null) {
      throw const FormatException('--scan-limit is required (no unbounded mode)');
    }
    if (scanLimit < 1 || scanLimit > _maxScanLimit) {
      throw FormatException('--scan-limit must be between 1 and $_maxScanLimit');
    }

    final batchSize = _intValue(arguments, '--batch-size') ?? 50;
    if (batchSize < 1 || batchSize > 100) {
      throw const FormatException('--batch-size must be between 1 and 100');
    }

    final maxFetches = _intValue(arguments, '--max-fetches');
    if (maxFetches == null) {
      throw const FormatException('--max-fetches is required (no unbounded mode)');
    }
    if (maxFetches < 1 || maxFetches > _maxFetchesLimit) {
      throw FormatException('--max-fetches must be between 1 and $_maxFetchesLimit');
    }

    final projectRef = _requiredValue(arguments, '--project-ref');
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef)) {
      throw const FormatException('invalid --project-ref');
    }

    return _CliOptions(
      help: false,
      apply: apply,
      projectRef: projectRef,
      scanLimit: scanLimit,
      batchSize: batchSize,
      maxFetches: maxFetches,
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
        arguments[index + 1].startsWith('--')) {
      throw FormatException('$name requires a value');
    }
    return arguments[index + 1];
  }

  static void _validateArguments(List<String> arguments) {
    const flags = {
      '--help',
      '-h',
      '--dry-run',
      '--apply',
      '--confirm-apply-legacy-basis-revalidation',
      '--quiet-per-product',
    };
    const valueOptions = {
      '--project-ref',
      '--scan-limit',
      '--batch-size',
      '--max-fetches',
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

class _RestBasisRevalidationDataSource
    implements LegacyScoringRecoveryLifecycleDataSource {
  _RestBasisRevalidationDataSource({
    required this.baseUri,
    required this.serviceRoleKey,
  });

  final Uri baseUri;
  final String serviceRoleKey;
  final HttpClient _client = HttpClient();

  void close() => _client.close(force: true);

  @override
  Future<Product?> fetchProduct(String productId) async {
    final rows = await _getRows('products', {
      'select': '*',
      'id': 'eq.$productId',
      'limit': '1',
    });
    return rows.isEmpty ? null : Product.fromJson(rows.single);
  }

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async {
    final result = <Ingredient>[];
    String? cursor;
    while (true) {
      final rows = await _getRows('ingredients', {
        'select': '*',
        'order': 'id.asc',
        'limit': '500',
        if (cursor != null) 'id': 'gt.$cursor',
      });
      if (rows.isEmpty) break;
      result.addAll(rows.map(Ingredient.fromJson));
      cursor = result.last.id;
    }
    return result;
  }

  @override
  Future<List<Product>> fetchRecoveryCandidates({
    required String source,
    required String? afterProductId,
    required int limit,
  }) async {
    final rows = await _getRows('products', {
      'select': '*',
      'scoring_evidence': 'is.null',
      'source': 'eq.$source',
      'order': 'id.asc',
      'limit': '$limit',
      if (afterProductId != null) 'id': 'gt.$afterProductId',
    });
    return rows.map(Product.fromJson).toList(growable: false);
  }

  @override
  Future<List<Product>> fetchCataloguePage({
    required String? afterProductId,
    required int limit,
  }) async {
    final rows = await _getRows('products', {
      'select': '*',
      'order': 'id.asc',
      'limit': '$limit',
      if (afterProductId != null) 'id': 'gt.$afterProductId',
    });
    return rows.map(Product.fromJson).toList(growable: false);
  }

  @override
  Future<List<LegacyStagingScoringEvidence>> fetchStagingMatches(
    String? sourceUrl,
  ) async {
    final normalized = sourceUrl?.trim() ?? '';
    if (normalized.isEmpty) return const [];
    final rows = await _getRows('product_staging', {
      'select':
          'id,source_url,source,ingredients_source,ingredients_text,'
          'nutrition_source,nutrition_json,raw_source_payload',
      'source_url': 'eq.$normalized',
      'order': 'id.asc',
    });
    return rows.map(_stagingEvidence).toList(growable: false);
  }

  @override
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence, {
    required ScoringEvidenceSnapshot? expectedCurrent,
  }) async {
    final response = await _request(
      'PATCH',
      _uri('products', {
        'id': 'eq.$productId',
        'scoring_evidence': expectedCurrent == null
            ? 'is.null'
            : 'eq.${jsonEncode(expectedCurrent.toJson())}',
        'select': 'id',
      }),
      body: {'scoring_evidence': evidence.toJson()},
      prefer: 'return=representation',
    );
    return response is List && response.isNotEmpty;
  }

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  ) async {
    final response = await _rpc('get_current_product_score_audit_snapshot', {
      'p_product_id': current.productId,
      'p_input_fingerprint': current.inputFingerprint,
      'p_score_version': current.scoreVersion,
      'p_nutrition_methodology_version': current.nutritionMethodologyVersion,
      'p_nutrition_transform_version': current.nutritionTransformVersion,
      'p_additive_transform_version': current.additiveTransformVersion,
    });
    if (response == null) return null;
    final snapshot = EtiketlyScoreAuditSnapshot.tryFromJson(response);
    if (snapshot == null) throw const FormatException('malformed_audit');
    return snapshot;
  }

  @override
  Future<ScoreAuditSnapshotWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    final response = await _rpc('record_product_score_audit_snapshot', {
      'p_product_id': snapshot.productId,
      'p_input_fingerprint': snapshot.inputFingerprint,
      'p_snapshot_schema_version': snapshot.schemaVersion,
      'p_score_version': snapshot.scoreVersion,
      'p_nutrition_methodology_version': snapshot.nutritionMethodologyVersion,
      'p_nutrition_transform_version': snapshot.nutritionTransformVersion,
      'p_additive_transform_version': snapshot.additiveTransformVersion,
      'p_trigger_source': triggerSource.databaseValue,
      'p_snapshot': snapshot.toJson(),
    });
    if (response is! Map ||
        response['snapshot_id'] is! String ||
        response['inserted'] is! bool) {
      throw const FormatException('malformed_audit_write');
    }
    return ScoreAuditSnapshotWriteResult(
      snapshotId: response['snapshot_id'] as String,
      inserted: response['inserted'] as bool,
    );
  }

  LegacyStagingScoringEvidence _stagingEvidence(Map<String, dynamic> row) {
    final payload = _map(row['raw_source_payload']);
    final warnings = payload?['nutrition_warnings'];
    final ingredientsRaw = _string(payload?['ingredients_raw']);
    final ingredientsText = _string(row['ingredients_text']);
    return LegacyStagingScoringEvidence(
      id: row['id'] as String,
      sourceUrl: (row['source_url'] as String).trim(),
      nutritionBasis: _string(payload?['nutrition_basis']),
      nutritionWarnings: warnings is List
          ? warnings.map((value) => value.toString())
          : const [],
      nutritionProductState: _string(payload?['nutrition_product_state']),
      source: _string(row['source']),
      ingredientsSource: _string(row['ingredients_source']),
      ingredientsRaw: ingredientsRaw,
      ingredientsText: ingredientsText,
      ingredientsQuality: resolveEffectiveIngredientsQuality(
        payload,
        ingredientsRaw: ingredientsRaw,
        ingredientsText: ingredientsText,
      ),
      nutritionSource: _string(row['nutrition_source']),
      nutritionStrategy: _string(payload?['nutrition_strategy']),
      nutritionJson: _map(row['nutrition_json']),
    );
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

  Future<Object?> _rpc(String name, Map<String, Object?> body) {
    return _request('POST', _uri('rpc/$name'), body: body);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return baseUri.replace(path: '/rest/v1/$path', queryParameters: query);
  }

  Future<Object?> _request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
    String? prefer,
  }) async {
    final request = await _client.openUrl(method, uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
      ..set('apikey', serviceRoleKey)
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(
        HttpHeaders.userAgentHeader,
        'etiketly-final-legacy-basis-revalidation/1',
      );
    if (prefer != null) request.headers.set('Prefer', prefer);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('remote_http_${response.statusCode}');
    }
    return responseBody.trim().isEmpty ? null : jsonDecode(responseBody);
  }

  Map<String, dynamic>? _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  String? _string(Object? value) => value is String ? value : null;
}
