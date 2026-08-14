import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

Future<void> main(List<String> arguments) async {
  late final _Options options;
  try {
    options = _Options.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('error=${error.message}');
    _usage();
    exitCode = 64;
    return;
  }
  if (options.help) {
    _usage();
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

  final dataSource = _RestLifecycleDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  try {
    final result = await ProductScoringLifecycleService(dataSource: dataSource)
        .processCurrent(
          options.productId,
          triggerSource: options.triggerSource,
          evidenceResolver: (product, catalogue) async {
            final staging = await dataSource.fetchStagingMatches(
              product.sourceUrl,
            );
            final recovery = await const LegacyScoringEvidenceRecoveryService()
                .recoverEvidence(
                  product: product,
                  stagingMatches: staging,
                  ingredientCatalogue: catalogue,
                );
            return ProductScoringEvidenceResolution(
              evidence: recovery.evidence,
              blockerReasons: recovery.blockerReasons,
            );
          },
        );
    stdout.writeln(_format(result));
    if (!result.succeeded) exitCode = 1;
  } on Object catch (error) {
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

class _Options {
  const _Options({
    required this.help,
    required this.productId,
    required this.projectRef,
    required this.triggerSource,
  });

  final bool help;
  final String productId;
  final String projectRef;
  final ScoreAuditTriggerSource triggerSource;

  static _Options parse(List<String> arguments) {
    const allowed = {
      '--help',
      '-h',
      '--product-id',
      '--project-ref',
      '--trigger-source',
      '--confirm-ingestion-scoring',
    };
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (!allowed.contains(argument)) {
        throw FormatException('unknown argument: $argument');
      }
      if (const {
        '--product-id',
        '--project-ref',
        '--trigger-source',
      }.contains(argument)) {
        index++;
        if (index >= arguments.length || arguments[index].startsWith('--')) {
          throw FormatException('$argument requires a value');
        }
      }
    }
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _Options(
        help: true,
        productId: '',
        projectRef: '',
        triggerSource: ScoreAuditTriggerSource.catalogueChange,
      );
    }
    if (!arguments.contains('--confirm-ingestion-scoring')) {
      throw const FormatException('missing --confirm-ingestion-scoring');
    }
    final productId = _value(arguments, '--product-id');
    if (!RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
    ).hasMatch(productId)) {
      throw const FormatException('invalid --product-id');
    }
    final projectRef = _value(arguments, '--project-ref');
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef)) {
      throw const FormatException('invalid --project-ref');
    }
    final triggerValue = _value(arguments, '--trigger-source');
    final trigger = ScoreAuditTriggerSource.values
        .where((value) => value.databaseValue == triggerValue)
        .firstOrNull;
    if (trigger == null ||
        trigger == ScoreAuditTriggerSource.controlledBackfill) {
      throw const FormatException('invalid ingestion --trigger-source');
    }
    return _Options(
      help: false,
      productId: productId,
      projectRef: projectRef,
      triggerSource: trigger,
    );
  }

  static String _value(List<String> arguments, String name) {
    final index = arguments.indexOf(name);
    if (index < 0 || index + 1 >= arguments.length) {
      throw FormatException('missing $name');
    }
    return arguments[index + 1].trim();
  }
}

class _RestLifecycleDataSource implements ProductScoringLifecycleDataSource {
  _RestLifecycleDataSource({
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
        'etiketly-product-scoring-lifecycle/1',
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

String _format(ProductScoringLifecycleResult result) {
  return [
    'product_id=${result.productId}',
    'evidence_status=${result.evidenceStatus.name}',
    'nutrition_ready=${result.nutritionReady}',
    'additive_ready=${result.additiveReady}',
    'final_score_ready=${result.finalScoreReady}',
    'calculated_score=${result.calculatedScore ?? '-'}',
    'input_fingerprint=${result.inputFingerprint ?? '-'}',
    'audit_status=${result.auditStatus.name}',
    'snapshot_id=${result.snapshotId ?? '-'}',
    'blockers=${result.blockerReasons.isEmpty ? '-' : result.blockerReasons.join(',')}',
    'failure_type=${result.failureType ?? '-'}',
  ].join('\n');
}

void _usage() {
  stdout.writeln('''
Usage:
  dart run tool/product_scoring_lifecycle.dart \\
    --project-ref REF --product-id UUID \\
    --trigger-source staging_approval --confirm-ingestion-scoring

Credentials are read only from SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY (or legacy SUPABASE_SERVICE_KEY).
''');
}
