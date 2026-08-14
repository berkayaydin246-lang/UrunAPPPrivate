import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/additive_coverage_impact_report.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';

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

  final dataSource = _RestAdditiveCoverageImpactDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  try {
    final summary = await AdditiveCoverageImpactRunner(
      dataSource: dataSource,
    ).run(AdditiveCoverageImpactOptions(batchSize: options.batchSize));
    stdout.writeln(const AdditiveCoverageImpactFormatter().format(summary));
    if (summary.errors > 0) exitCode = 1;
  } on Object catch (error) {
    // Remote failures can contain request metadata. Report only the type.
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

class _CliOptions {
  const _CliOptions({required this.help, required this.batchSize});

  final bool help;
  final int batchSize;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(help: true, batchSize: 100);
    }
    final batchSize = _intValue(arguments, '--batch-size') ?? 100;
    if (batchSize < 1 || batchSize > 500) {
      throw const FormatException('--batch-size must be between 1 and 500');
    }
    return _CliOptions(help: false, batchSize: batchSize);
  }

  static int? _intValue(List<String> arguments, String name) {
    final index = arguments.indexOf(name);
    if (index < 0) return null;
    if (index + 1 >= arguments.length ||
        arguments[index + 1].startsWith('--')) {
      throw FormatException('$name requires a value');
    }
    final value = int.tryParse(arguments[index + 1]);
    if (value == null) throw FormatException('$name must be an integer');
    return value;
  }

  static void _validateArguments(List<String> arguments) {
    const flags = {'--help', '-h'};
    const valueOptions = {'--batch-size'};
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

class _RestAdditiveCoverageImpactDataSource
    implements AdditiveCoverageImpactDataSource {
  _RestAdditiveCoverageImpactDataSource({
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
    final response = await _postReadOnlyRpc(
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
    final uri = baseUri.replace(
      path: '/rest/v1/$table',
      queryParameters: query,
    );
    final response = await _request('GET', uri);
    if (response is! List) {
      throw const FormatException('Expected a row list.');
    }
    return response
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<Object?> _postReadOnlyRpc(String function, Map<String, Object?> body) {
    final uri = baseUri.replace(path: '/rest/v1/rpc/$function');
    return _request('POST', uri, body: body);
  }

  Future<Object?> _request(
    String method,
    Uri uri, {
    Map<String, Object?>? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
      ..set('apikey', serviceRoleKey)
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(
        HttpHeaders.userAgentHeader,
        'etiketly-additive-coverage-impact-report/1',
      );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Read-only request failed with HTTP ${response.statusCode}.',
      );
    }
    if (responseBody.trim().isEmpty) return null;
    return jsonDecode(responseBody);
  }
}

void _printUsage() {
  stdout.writeln(r'''
Usage:
  dart run tool/additive_coverage_impact_report.dart [--batch-size N]

Options:
  --batch-size N  Candidate product page size, 1-500 (default: 100)

The tool is read-only. Candidate products are selected server-side only when
ingredients_text contains an affected E202, E471, E282, or generic flavouring
term. Product IDs are deduplicated before evaluation. Null scoring evidence is
recovered in memory and is never persisted.

Credentials are read only from SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY. They are never printed or loaded from a file.
''');
}
