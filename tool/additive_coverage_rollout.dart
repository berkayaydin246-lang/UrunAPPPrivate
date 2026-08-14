import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/additive_coverage_impact_report.dart';
import 'package:food_analyzer_app/features/scoring/application/additive_coverage_rollout.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_backfill.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

Future<void> main(List<String> arguments) async {
  late final AdditiveCoverageRolloutCliOptions options;
  try {
    options = AdditiveCoverageRolloutCliOptions.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('error=${error.message}');
    printAdditiveCoverageRolloutUsage();
    exitCode = 64;
    return;
  }
  if (options.help) {
    printAdditiveCoverageRolloutUsage();
    return;
  }

  final environment = Platform.environment;
  final supabaseUrl = environment['SUPABASE_URL']?.trim() ?? '';
  final serviceRoleKey = environment['SUPABASE_SERVICE_ROLE_KEY']?.trim() ?? '';
  if (supabaseUrl.isEmpty || serviceRoleKey.isEmpty) {
    stderr.writeln(
      'error=SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be supplied '
      'through the process environment',
    );
    exitCode = 78;
    return;
  }
  final baseUri = Uri.tryParse(supabaseUrl);
  if (baseUri == null ||
      baseUri.scheme != 'https' ||
      !baseUri.host.endsWith('.supabase.co')) {
    stderr.writeln('error=SUPABASE_URL must be an HTTPS Supabase project URL');
    exitCode = 78;
    return;
  }

  final dataSource = _RestAdditiveCoverageRolloutDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  try {
    final summary = await AdditiveCoverageRolloutRunner(dataSource: dataSource)
        .run(
          AdditiveCoverageRolloutOptions(
            dryRun: options.dryRun,
            batchSize: options.batchSize,
            startAfterProductId: options.startAfterProductId,
            maxProducts: options.maxProducts,
          ),
        );
    stdout.writeln(const AdditiveCoverageRolloutFormatter().format(summary));
    if (summary.errors > 0) exitCode = 1;
  } on Object catch (error) {
    // Remote failures can contain request metadata. Report only the type.
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

class AdditiveCoverageRolloutCliOptions {
  const AdditiveCoverageRolloutCliOptions({
    required this.help,
    required this.dryRun,
    required this.batchSize,
    required this.startAfterProductId,
    required this.maxProducts,
  });

  final bool help;
  final bool dryRun;
  final int batchSize;
  final String? startAfterProductId;
  final int? maxProducts;

  static AdditiveCoverageRolloutCliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const AdditiveCoverageRolloutCliOptions(
        help: true,
        dryRun: true,
        batchSize: 100,
        startAfterProductId: null,
        maxProducts: null,
      );
    }
    final dryRun = arguments.contains('--dry-run');
    final apply = arguments.contains('--apply');
    if (dryRun == apply) {
      throw const FormatException('choose exactly one of --dry-run or --apply');
    }
    final confirmed = arguments.contains('--confirm-targeted-rollout');
    if (apply && !confirmed) {
      throw const FormatException(
        '--apply requires --confirm-targeted-rollout',
      );
    }
    if (!apply && confirmed) {
      throw const FormatException(
        '--confirm-targeted-rollout is valid only with --apply',
      );
    }
    final batchSize = _intValue(arguments, '--batch-size') ?? 100;
    final maxProducts = _intValue(arguments, '--max-products');
    if (batchSize < 1 || batchSize > 500) {
      throw const FormatException('--batch-size must be between 1 and 500');
    }
    if (maxProducts != null && maxProducts < 1) {
      throw const FormatException('--max-products must be positive');
    }
    if (apply && maxProducts == null) {
      throw const FormatException('--apply requires --max-products');
    }
    return AdditiveCoverageRolloutCliOptions(
      help: false,
      dryRun: dryRun,
      batchSize: batchSize,
      startAfterProductId: _value(arguments, '--start-after'),
      maxProducts: maxProducts,
    );
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
      '--confirm-targeted-rollout',
    };
    const valueOptions = {'--batch-size', '--start-after', '--max-products'};
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (flags.contains(argument)) continue;
      if (!valueOptions.contains(argument)) {
        throw FormatException('unknown argument: $argument');
      }
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('--')) {
        throw FormatException('$argument requires a value');
      }
      index++;
    }
  }
}

class _RestAdditiveCoverageRolloutDataSource
    implements AdditiveCoverageRolloutDataSource {
  _RestAdditiveCoverageRolloutDataSource({
    required this.baseUri,
    required this.serviceRoleKey,
  });

  final Uri baseUri;
  final String serviceRoleKey;
  final HttpClient _client = HttpClient();

  void close() => _client.close(force: true);

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async {
    final ingredients = <Ingredient>[];
    String? cursor;
    while (true) {
      final rows = await _getRows('ingredients', {
        'select': '*',
        'order': 'id.asc',
        'limit': '500',
        if (cursor != null) 'id': 'gt.$cursor',
      });
      if (rows.isEmpty) break;
      ingredients.addAll(rows.map(Ingredient.fromJson));
      cursor = ingredients.last.id;
    }
    return ingredients;
  }

  @override
  Future<List<Product>> fetchCandidateProductsAfter({
    required String? afterProductId,
    required int limit,
  }) async {
    final rows = await _getRows('products', {
      'select': '*',
      'or': additiveCoveragePostgrestOrFilter(),
      'order': 'id.asc',
      'limit': '$limit',
      if (afterProductId != null) 'id': 'gt.$afterProductId',
    });
    return rows.map(Product.fromJson).toList(growable: false);
  }

  @override
  Future<Product?> fetchProductById(String productId) async {
    final rows = await _getRows('products', {
      'select': '*',
      'id': 'eq.$productId',
      'limit': '1',
    });
    return rows.isEmpty ? null : Product.fromJson(rows.single);
  }

  @override
  Future<Map<String, List<LegacyStagingScoringEvidence>>> fetchStagingMatches(
    Set<String> sourceUrls,
  ) async {
    final matches = <String, List<LegacyStagingScoringEvidence>>{};
    final orderedUrls =
        sourceUrls
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    for (var offset = 0; offset < orderedUrls.length; offset += 20) {
      final end = (offset + 20).clamp(0, orderedUrls.length);
      final filter = orderedUrls
          .sublist(offset, end)
          .map(_postgrestQuoted)
          .join(',');
      final rows = await _getRows('product_staging', {
        'select':
            'id,source_url,source,ingredients_source,ingredients_text,'
            'nutrition_source,nutrition_json,raw_source_payload',
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
        matches.putIfAbsent(normalizedSourceUrl, () => []).add(evidence);
      }
    }
    for (final entries in matches.values) {
      entries.sort((left, right) => left.id.compareTo(right.id));
    }
    return matches;
  }

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  ) async {
    final response = await _postRpc(
      'get_current_product_score_audit_snapshot',
      {
        'p_product_id': current.productId,
        'p_input_fingerprint': current.inputFingerprint,
        'p_score_version': current.scoreVersion,
        'p_nutrition_methodology_version': current.nutritionMethodologyVersion,
        'p_nutrition_transform_version': current.nutritionTransformVersion,
        'p_additive_transform_version': current.additiveTransformVersion,
      },
    );
    if (response == null) return null;
    final snapshot = EtiketlyScoreAuditSnapshot.tryFromJson(response);
    if (snapshot == null) {
      throw const FormatException('Malformed audit snapshot response.');
    }
    return snapshot;
  }

  @override
  Future<AdditiveCoverageEvidencePersistenceResult>
  persistScoringEvidenceIfNull(
    String productId,
    ScoringEvidenceSnapshot evidence,
  ) async {
    final response = await _request(
      'PATCH',
      _uri('products', {
        'id': 'eq.$productId',
        'scoring_evidence': 'is.null',
        'select': '*',
      }),
      body: {'scoring_evidence': evidence.toJson()},
      prefer: 'return=representation',
    );
    if (response is! List) {
      throw const FormatException('Expected a row list after evidence write.');
    }
    if (response.length > 1) {
      throw StateError('Evidence write changed more than one row.');
    }
    if (response.length == 1) {
      return AdditiveCoverageEvidencePersistenceResult(
        product: Product.fromJson(
          Map<String, dynamic>.from(response.single as Map),
        ),
        written: true,
      );
    }
    final existing = await fetchProductById(productId);
    if (existing == null || existing.scoringEvidence == null) {
      throw StateError('Conditional evidence write did not persist evidence.');
    }
    return AdditiveCoverageEvidencePersistenceResult(
      product: existing,
      written: false,
    );
  }

  @override
  Future<ScoreAuditBackfillWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot,
  ) async {
    final response = await _postRpc('record_product_score_audit_snapshot', {
      'p_product_id': snapshot.productId,
      'p_input_fingerprint': snapshot.inputFingerprint,
      'p_snapshot_schema_version': snapshot.schemaVersion,
      'p_score_version': snapshot.scoreVersion,
      'p_nutrition_methodology_version': snapshot.nutritionMethodologyVersion,
      'p_nutrition_transform_version': snapshot.nutritionTransformVersion,
      'p_additive_transform_version': snapshot.additiveTransformVersion,
      'p_trigger_source': 'controlled_backfill',
      'p_snapshot': snapshot.toJson(),
    });
    if (response is! Map) {
      throw const FormatException('Malformed audit write response.');
    }
    final snapshotId = response['snapshot_id'];
    final inserted = response['inserted'];
    if (snapshotId is! String || inserted is! bool) {
      throw const FormatException('Malformed audit write response.');
    }
    return ScoreAuditBackfillWriteResult(
      snapshotId: snapshotId,
      inserted: inserted,
    );
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return Map<String, dynamic>.from(value);
  }

  static String? _string(Object? value) => value is String ? value : null;

  static String _postgrestQuoted(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }

  Future<List<Map<String, dynamic>>> _getRows(
    String table,
    Map<String, String> query,
  ) async {
    final response = await _request('GET', _uri(table, query));
    if (response is! List) {
      throw const FormatException('Expected a row list.');
    }
    return response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<Object?> _postRpc(String function, Map<String, Object?> body) {
    return _request('POST', _uri('rpc/$function'), body: body);
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
        'etiketly-additive-coverage-rollout/1',
      );
    if (prefer != null) request.headers.set('Prefer', prefer);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
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

void printAdditiveCoverageRolloutUsage() {
  stdout.writeln(r'''
Usage:
  dart run tool/additive_coverage_rollout.dart --dry-run [options]
  dart run tool/additive_coverage_rollout.dart --apply \
    --confirm-targeted-rollout --max-products N [options]

Options:
  --batch-size N      Candidate page size, 1-500 (default: 100)
  --start-after UUID  Resume strictly after this candidate product ID
  --max-products N    Maximum targeted candidate products examined

Candidate products are selected server-side only through the shared E202,
E471, E282, and generic flavouring ingredient filter. Apply writes recovered
scoring evidence only when the column is NULL, then idempotently records the
current v2 audit snapshot. Credentials are read only from SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY and are never printed.
''');
}
