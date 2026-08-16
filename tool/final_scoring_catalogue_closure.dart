import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_recovery_lifecycle_runner.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

/// Final whole-catalogue scoring closure CLI.
///
/// This is the terminal pass for the Etiketly historical scoring project:
/// for every product in the catalogue, regardless of whether
/// `scoring_evidence` is null or already populated, it drives exactly one
/// of the two valid terminal states — currently scoreable (evidence +
/// matching current audit snapshot + public gate approval) or
/// deterministically blocked with exact reasons — using ONLY the existing,
/// frozen scoring services:
///
///   - [LegacyScoringEvidenceRecoveryService] (CASE 1: recover trusted
///     historical evidence for never-recovered products)
///   - [ProductScoringLifecycleService] (via
///     [LegacyScoringRecoveryLifecycleRunner], the single write path for
///     both evidence persistence and audit-snapshot insertion)
///   - [ProductScoreAuditEvaluator] / [EtiketlyPublicScoreAuditGate] (CASE
///     2: evaluate and, if needed, repair the audit for products that
///     already have score-ready evidence)
///
/// This tool contains no scoring math, no category rules, and no additive
/// logic of its own — it only orchestrates and reports. It never
/// constructs a [ScoringEvidenceSnapshot] itself and never writes
/// `scoring_evidence` for a product that already has it (see
/// [LegacyScoringRecoveryLifecycleRunner]'s audit-repair path, which uses
/// an identity evidence resolver).
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

  final dataSource = _RestCatalogueClosureDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  const formatter = LegacyScoringRecoveryReportFormatter();
  final runner = LegacyScoringRecoveryLifecycleRunner(dataSource: dataSource);
  try {
    final summary = await runner.runFullCatalogueClosure(
      dryRun: options.dryRun,
      limit: options.limit,
      batchSize: options.batchSize,
      startAfterProductId: options.startAfterProductId,
    );

    if (!options.quietPerProduct) {
      for (final result in summary.results) {
        stdout.writeln(formatter.formatProduct(result));
      }
    }
    stdout.writeln(formatter.formatSummary(summary));
    final byCategory = groupResultsByCategory(summary.results);
    stdout.writeln(formatter.formatCategoryBreakdown(byCategory));

    final postcondition = computeClosurePostcondition(summary.results);
    stdout.writeln(formatter.formatPostcondition(postcondition));
    stdout.writeln(formatter.formatFinalStateSummary(summary.results));

    // Internal-accounting assertion: every recorded result increments
    // exactly one of the nine mutually-exclusive terminal outcome
    // counters, so this sum must always equal total_examined. This is not
    // a diagnostic backlog signal (unlike closure_clean) — a mismatch here
    // means the report itself is not trustworthy, so it fails in BOTH
    // modes, never only apply.
    if (!summary.outcomeCountsAreConsistent) {
      stderr.writeln(
        'error=outcome_accounting_inconsistent '
        'outcome_counts_sum=${summary.outcomeCountsSum} '
        'total_examined=${summary.totalExamined}',
      );
      exitCode = 1;
      return;
    }

    if (summary.halted) {
      stderr.writeln('error=run_halted_before_completion');
      exitCode = 1;
      return;
    }
    if (options.dryRun) {
      // closure_clean reflects the real state in both modes (see
      // ClosurePostcondition) — a dry-run legitimately reports a nonzero
      // scoreable_but_not_current backlog (that is its purpose), so this
      // is diagnostic only and never fails the dry-run exit code. Only a
      // genuine unexpectedError count is ever a dry-run failure signal.
      if (postcondition.unexpectedErrors > 0) exitCode = 1;
      return;
    }
    if (!postcondition.isClean) {
      stderr.writeln(
        'error=closure_not_clean '
        'scoreable_but_not_current=${postcondition.scoreableButNotCurrent} '
        'unexpected_errors=${postcondition.unexpectedErrors}',
      );
      exitCode = 1;
    }
  } on Object catch (error) {
    // Remote failures can contain request metadata. Report only the type.
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

// Bounded, deliberately conservative for a whole-catalogue pass that can
// trigger a large batch of database writes in apply mode. Raise only with a
// deliberate, reviewed change — never silently.
const _maxLimit = 10000;

class _CliOptions {
  const _CliOptions({
    required this.help,
    required this.dryRun,
    required this.projectRef,
    required this.limit,
    required this.batchSize,
    required this.startAfterProductId,
    required this.quietPerProduct,
  });

  final bool help;
  final bool dryRun;
  final String projectRef;
  final int limit;
  final int batchSize;
  final String? startAfterProductId;
  final bool quietPerProduct;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(
        help: true,
        dryRun: true,
        projectRef: '',
        limit: 0,
        batchSize: 50,
        startAfterProductId: null,
        quietPerProduct: false,
      );
    }

    final explicitDryRun = arguments.contains('--dry-run');
    final apply = arguments.contains('--apply');
    if (explicitDryRun && apply) {
      throw const FormatException('choose exactly one of --dry-run or --apply');
    }
    if (apply &&
        !arguments.contains(
          '--confirm-apply-final-scoring-catalogue-closure',
        )) {
      throw const FormatException(
        '--apply requires --confirm-apply-final-scoring-catalogue-closure',
      );
    }
    // Default to dry-run whenever --apply is not explicitly requested.
    final dryRun = !apply;

    final limit = _intValue(arguments, '--limit');
    if (limit == null) {
      throw const FormatException('--limit is required (no unbounded mode)');
    }
    if (limit < 1) throw const FormatException('--limit must be positive');
    if (limit > _maxLimit) {
      throw const FormatException('--limit must be $_maxLimit or fewer');
    }

    final batchSize = _intValue(arguments, '--batch-size') ?? 50;
    if (batchSize < 1 || batchSize > 100) {
      throw const FormatException('--batch-size must be between 1 and 100');
    }

    final startAfterProductId = _value(arguments, '--start-after')?.trim();
    if (startAfterProductId != null &&
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(startAfterProductId)) {
      throw const FormatException('invalid_start_after_format');
    }

    final projectRef = _requiredValue(arguments, '--project-ref');
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef)) {
      throw const FormatException('invalid --project-ref');
    }

    return _CliOptions(
      help: false,
      dryRun: dryRun,
      projectRef: projectRef,
      limit: limit,
      batchSize: batchSize,
      startAfterProductId: startAfterProductId,
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
      '--confirm-apply-final-scoring-catalogue-closure',
      '--quiet-per-product',
    };
    const valueOptions = {
      '--project-ref',
      '--limit',
      '--batch-size',
      '--start-after',
    };
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (flags.contains(argument)) continue;
      if (!valueOptions.contains(argument)) {
        // Never echo the raw stray token: a mistakenly pasted secret/JWT
        // here must not be reflected back in terminal output.
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

class _RestCatalogueClosureDataSource
    implements LegacyScoringRecoveryLifecycleDataSource {
  _RestCatalogueClosureDataSource({
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
    // Not used by the whole-catalogue closure pass (see
    // fetchCataloguePage below) — implemented only to satisfy the shared
    // interface, kept identical to the historical-recovery tool's exact
    // (never LIKE/ILIKE) match semantics in case a future caller reuses
    // this data source for a targeted recovery run.
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
    // Deliberately unconditional — no scoring_evidence filter, no source
    // filter. This is what makes the closure pass cover already-evidenced
    // products (CASE 2) as well as never-recovered ones (CASE 1).
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
        'etiketly-final-scoring-catalogue-closure/1',
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

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static String? _string(Object? value) => value is String ? value : null;
}

void _printUsage() {
  stdout.writeln(r'''
Usage (dry-run is the default; nothing is written):
  dart run tool/final_scoring_catalogue_closure.dart \
    --project-ref REF --limit 6000

Apply (writes ONLY via ProductScoringLifecycleService — recovers evidence
for never-recovered products, or repairs a missing/stale audit for
already-evidenced score-ready products; existing evidence is never
overwritten):
  dart run tool/final_scoring_catalogue_closure.dart \
    --project-ref REF --apply \
    --confirm-apply-final-scoring-catalogue-closure --limit 6000

Options:
  --limit N               Required. Max products examined this run
                          (max $_maxLimit — no unbounded mode).
  --batch-size N           Page size, 1-100 (default: 50).
  --start-after UUID       Resume strictly after this product ID.
  --quiet-per-product      Suppress the per-product lines; print only the
                          summary, category breakdown, and postcondition.

Covers EVERY product regardless of scoring_evidence nullness in one pass —
never only `scoring_evidence IS NULL` rows.

closure_clean in [postcondition] always reflects the real state in both
modes: false whenever scoreable_but_not_current > 0 (this includes
audit_repairable in dry-run — score-ready evidence with no current audit IS
scoreable, just not yet current) or unexpected_errors > 0. A dry-run
legitimately reports closure_clean=false when there is a real backlog to
apply — that is diagnostic, not a failure, so dry-run's exit code only
reacts to unexpectedError. Exit code is non-zero if the run halted, if the
internal outcome-accounting assertion fails (in either mode — this signals
the report itself is untrustworthy, not a backlog), if any unexpectedError
occurred, or (apply mode only) if closure_clean is false after processing —
in which case the affected product IDs are printed under
[scoreable_but_not_current_product_ids] and [unexpected_error_product_ids].

Credentials are read only from SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY (or legacy SUPABASE_SERVICE_KEY). They are never
printed or loaded from a file.
''');
}
