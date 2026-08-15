import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_recovery_lifecycle_runner.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

/// Historical scoring recovery CLI.
///
/// Reuses [LegacyScoringEvidenceRecoveryService] and
/// [ProductScoringLifecycleService] (via [LegacyScoringRecoveryLifecycleRunner])
/// exclusively. This tool never constructs a [ScoringEvidenceSnapshot] itself
/// and never writes `scoring_evidence` directly.
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

  final dataSource = _RestRecoveryLifecycleDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  const formatter = LegacyScoringRecoveryReportFormatter();
  final runner = LegacyScoringRecoveryLifecycleRunner(dataSource: dataSource);
  try {
    final summary = options.productIds.isNotEmpty
        ? await runner.runForProductIds(
            dryRun: options.dryRun,
            productIds: options.productIds,
          )
        : await runner.runForSource(
            dryRun: options.dryRun,
            source: options.source!,
            limit: options.limit!,
            batchSize: options.batchSize,
            startAfterProductId: options.startAfterProductId,
          );

    for (final result in summary.results) {
      stdout.writeln(formatter.formatProduct(result));
    }
    stdout.writeln(formatter.formatSummary(summary));

    if (summary.unexpectedErrors > 0 || summary.halted) exitCode = 1;
  } on Object catch (error) {
    // Remote failures can contain request metadata. Report only the type.
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

// Bounded, deliberately conservative for a backfill tool that can trigger a
// batch of database writes in apply mode.
const _maxLimit = 500;

class _CliOptions {
  const _CliOptions({
    required this.help,
    required this.dryRun,
    required this.projectRef,
    required this.productIds,
    required this.source,
    required this.limit,
    required this.batchSize,
    required this.startAfterProductId,
  });

  final bool help;
  final bool dryRun;
  final String projectRef;
  final List<String> productIds;
  final String? source;
  final int? limit;
  final int batchSize;
  final String? startAfterProductId;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(
        help: true,
        dryRun: true,
        projectRef: '',
        productIds: [],
        source: null,
        limit: null,
        batchSize: 50,
        startAfterProductId: null,
      );
    }

    final explicitDryRun = arguments.contains('--dry-run');
    final apply = arguments.contains('--apply');
    if (explicitDryRun && apply) {
      throw const FormatException('choose exactly one of --dry-run or --apply');
    }
    if (apply && !arguments.contains('--confirm-apply-legacy-scoring-recovery')) {
      throw const FormatException(
        '--apply requires --confirm-apply-legacy-scoring-recovery',
      );
    }
    // Default to dry-run whenever --apply is not explicitly requested.
    final dryRun = !apply;

    // Deduplicate while preserving first-seen order — repeated IDs must
    // never be processed more than once.
    final productIds = <String>[
      ..._values(arguments, '--product-id').toSet(),
    ];
    for (final id in productIds) {
      if (!RegExp(
        r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      ).hasMatch(id)) {
        // Never echo the raw value: a mistakenly pasted secret/JWT here
        // must not be reflected back in terminal output.
        throw const FormatException('invalid_product_id_format');
      }
    }
    final source = _value(arguments, '--source')?.trim();
    final limit = _intValue(arguments, '--limit');
    final startAfterProductId = _value(arguments, '--start-after')?.trim();

    final hasProductIds = productIds.isNotEmpty;
    final hasSource = source != null && source.isNotEmpty;
    if (hasProductIds == hasSource) {
      throw const FormatException(
        'choose exactly one of --product-id (repeatable) or --source '
        '(with --limit)',
      );
    }
    if (hasSource && limit == null) {
      throw const FormatException('--source requires --limit');
    }
    if (!hasSource && limit != null) {
      throw const FormatException('--limit is only valid with --source');
    }
    if (limit != null && limit < 1) {
      throw const FormatException('--limit must be positive');
    }
    if (limit != null && limit > _maxLimit) {
      throw const FormatException('--limit must be $_maxLimit or fewer');
    }
    if (startAfterProductId != null && !hasSource) {
      throw const FormatException('--start-after is only valid with --source');
    }
    if (startAfterProductId != null &&
        !RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(startAfterProductId)) {
      throw const FormatException('invalid_start_after_format');
    }

    final batchSize = _intValue(arguments, '--batch-size') ?? 50;
    if (batchSize < 1 || batchSize > 100) {
      throw const FormatException('--batch-size must be between 1 and 100');
    }

    final projectRef = _requiredValue(arguments, '--project-ref');
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef)) {
      throw const FormatException('invalid --project-ref');
    }

    return _CliOptions(
      help: false,
      dryRun: dryRun,
      projectRef: projectRef,
      productIds: productIds,
      source: source,
      limit: limit,
      batchSize: batchSize,
      startAfterProductId: startAfterProductId,
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

  static List<String> _values(List<String> arguments, String name) {
    final values = <String>[];
    for (var index = 0; index < arguments.length; index++) {
      if (arguments[index] != name) continue;
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('--')) {
        throw FormatException('$name requires a value');
      }
      values.add(arguments[index + 1]);
    }
    return values;
  }

  static void _validateArguments(List<String> arguments) {
    const flags = {
      '--help',
      '-h',
      '--dry-run',
      '--apply',
      '--confirm-apply-legacy-scoring-recovery',
    };
    const valueOptions = {
      '--project-ref',
      '--product-id',
      '--source',
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

class _RestRecoveryLifecycleDataSource
    implements LegacyScoringRecoveryLifecycleDataSource {
  _RestRecoveryLifecycleDataSource({
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
    // Exact match only — never ILIKE/LIKE. A prefix or wildcard pattern
    // built from caller-supplied text could be broadened by embedded
    // %/_ metacharacters; `eq.` cannot be broadened this way.
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
      ingredientsRaw: _string(payload?['ingredients_raw']),
      ingredientsText: _string(row['ingredients_text']),
      ingredientsQuality: _string(payload?['ingredients_quality']),
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
        'etiketly-legacy-scoring-recovery-lifecycle/1',
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
  dart run tool/legacy_scoring_recovery_lifecycle.dart \
    --project-ref REF --product-id UUID [--product-id UUID ...]

  dart run tool/legacy_scoring_recovery_lifecycle.dart \
    --project-ref REF --source web_scraper:migros --limit 50

Apply (writes evidence + a current audit snapshot through the trusted
ProductScoringLifecycleService, triggerSource=controlled_backfill):
  dart run tool/legacy_scoring_recovery_lifecycle.dart \
    --project-ref REF --apply --confirm-apply-legacy-scoring-recovery \
    --product-id UUID [--product-id UUID ...]

  dart run tool/legacy_scoring_recovery_lifecycle.dart \
    --project-ref REF --apply --confirm-apply-legacy-scoring-recovery \
    --source web_scraper:migros --limit 50

Options:
  --product-id UUID     Repeatable (duplicates are deduplicated). Targeted
                          mode — never scans the catalogue. A product that
                          already has scoring_evidence is never overwritten;
                          it is only diagnosed (already_current or
                          existing_evidence_audit_unavailable).
  --source VALUE          Bounded batch by an EXACT products.source match
                          (e.g. web_scraper:migros) — never a prefix or
                          wildcard pattern. Requires --limit.
  --limit N               Required with --source. Max 500.
  --batch-size N          Page size for --source scans, 1-100 (default: 50).
  --start-after UUID      Resume a --source batch strictly after this
                          product ID. Only valid with --source.

Exactly one of --product-id (repeatable) or --source (+--limit) is required.

Credentials are read only from SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY (or legacy SUPABASE_SERVICE_KEY). They are never
printed or loaded from a file.
''');
}
