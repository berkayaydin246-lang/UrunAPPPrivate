import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_backfill.dart';
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
  final expectedHost = '${options.projectRef}.supabase.co';
  if (baseUri == null ||
      baseUri.scheme != 'https' ||
      baseUri.host != expectedHost) {
    stderr.writeln('error=SUPABASE_URL does not match project ref');
    exitCode = 78;
    return;
  }

  final dataSource = _RestScoreAuditBackfillDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  try {
    if (options.runBackfill) {
      final summary = await ScoreAuditBackfillRunner(dataSource: dataSource)
          .run(
            ScoreAuditBackfillOptions(
              dryRun: options.dryRun,
              batchSize: options.batchSize,
              startAfterProductId: options.startAfterProductId,
              maxProducts: options.maxProducts,
            ),
            onBatchComplete: (summary) {
              stdout.writeln(
                '[batch] examined=${summary.totalProductsExamined} '
                'last_cursor=${summary.lastExaminedCursor ?? '-'} '
                'safe_resume_cursor=${summary.safeResumeCursor ?? '-'} '
                'errors=${summary.errors}',
              );
            },
          );
      _printSummary(summary);
      if (summary.errors > 0 || summary.halted) exitCode = 1;
    }

    if (options.sampleProductIds.isNotEmpty) {
      final inspections = await ScoreAuditSampleInspector(
        dataSource: dataSource,
      ).inspect(options.sampleProductIds);
      for (final result in inspections) {
        _printInspection(result);
      }
      if (inspections.any((result) => result.error != null)) exitCode = 1;
    }
  } on Object catch (error) {
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

class _CliOptions {
  const _CliOptions({
    required this.help,
    required this.dryRun,
    required this.runBackfill,
    required this.projectRef,
    required this.batchSize,
    required this.startAfterProductId,
    required this.maxProducts,
    required this.sampleProductIds,
  });

  final bool help;
  final bool dryRun;
  final bool runBackfill;
  final String projectRef;
  final int batchSize;
  final String? startAfterProductId;
  final int? maxProducts;
  final List<String> sampleProductIds;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(
        help: true,
        dryRun: true,
        runBackfill: false,
        projectRef: '',
        batchSize: 100,
        startAfterProductId: null,
        maxProducts: null,
        sampleProductIds: [],
      );
    }
    final dryRun = arguments.contains('--dry-run');
    final apply = arguments.contains('--apply');
    if (dryRun && apply) {
      throw const FormatException('choose exactly one of --dry-run or --apply');
    }
    if (apply && !arguments.contains('--confirm-write-audit-snapshots')) {
      throw const FormatException(
        '--apply requires --confirm-write-audit-snapshots',
      );
    }
    final samples = (_value(arguments, '--sample-product-ids') ?? '')
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final runBackfill = dryRun || apply;
    if (!runBackfill && samples.isEmpty) {
      throw const FormatException(
        'select --dry-run, --apply, or --sample-product-ids',
      );
    }
    final projectRef = _requiredValue(arguments, '--project-ref');
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
    return _CliOptions(
      help: false,
      dryRun: dryRun,
      runBackfill: runBackfill,
      projectRef: projectRef,
      batchSize: batchSize,
      startAfterProductId: _value(arguments, '--start-after'),
      maxProducts: maxProducts,
      sampleProductIds: samples,
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
      '--confirm-write-audit-snapshots',
    };
    const valueOptions = {
      '--project-ref',
      '--batch-size',
      '--start-after',
      '--max-products',
      '--sample-product-ids',
    };
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (flags.contains(argument)) continue;
      if (!valueOptions.contains(argument)) {
        throw FormatException('unknown argument: $argument');
      }
      if (index + 1 >= arguments.length ||
          arguments[index + 1].startsWith('-')) {
        throw FormatException('$argument requires a value');
      }
      index++;
    }
  }
}

class _RestScoreAuditBackfillDataSource
    implements ScoreAuditBackfillDataSource {
  _RestScoreAuditBackfillDataSource({
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
      final query = <String, String>{
        'select': '*',
        'order': 'id.asc',
        'limit': '500',
        if (cursor != null) 'id': 'gt.$cursor',
      };
      final rows = await _getRows('ingredients', query);
      if (rows.isEmpty) break;
      ingredients.addAll(rows.map(Ingredient.fromJson));
      cursor = ingredients.last.id;
    }
    return ingredients;
  }

  @override
  Future<List<Product>> fetchProductsAfter({
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
  Future<Product?> fetchProductById(String productId) async {
    final rows = await _getRows('products', {
      'select': '*',
      'id': 'eq.$productId',
      'limit': '1',
    });
    return rows.isEmpty ? null : Product.fromJson(rows.single);
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

  Future<Object?> _postRpc(String functionName, Map<String, Object?> body) {
    return _request('POST', _uri('rpc/$functionName'), body: body);
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return baseUri.replace(path: '/rest/v1/$path', queryParameters: query);
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
      ..set(HttpHeaders.userAgentHeader, 'etiketly-score-audit-backfill/1');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Remote request failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    if (responseBody.trim().isEmpty) return null;
    return jsonDecode(responseBody);
  }
}

void _printSummary(ScoreAuditBackfillSummary summary) {
  stdout.writeln('[summary]');
  stdout.writeln('mode=${summary.dryRun ? 'dry_run' : 'apply'}');
  stdout.writeln('total_products_examined=${summary.totalProductsExamined}');
  stdout.writeln('nutrition_ready=${summary.nutritionReady}');
  stdout.writeln('additive_ready=${summary.additiveReady}');
  stdout.writeln('final_score_ready=${summary.finalScoreReady}');
  stdout.writeln('already_current_audit=${summary.alreadyCurrentAudit}');
  stdout.writeln('missing_audit=${summary.missingAudit}');
  stdout.writeln('stale_audit=${summary.staleAudit}');
  stdout.writeln('invalid_audit=${summary.invalidAudit}');
  stdout.writeln(
    'existing_audit_requires_review=${summary.existingAuditRequiresReview}',
  );
  stdout.writeln('would_insert=${summary.wouldInsert}');
  stdout.writeln('inserted=${summary.inserted}');
  stdout.writeln('duplicate_at_write=${summary.duplicateAtWrite}');
  stdout.writeln('not_scorable=${summary.notScorable}');
  stdout.writeln('errors=${summary.errors}');
  stdout.writeln('batch_errors=${summary.batchErrors}');
  stdout.writeln('completed=${summary.completed}');
  stdout.writeln('reached_limit=${summary.reachedLimit}');
  stdout.writeln('halted=${summary.halted}');
  stdout.writeln('last_examined_cursor=${summary.lastExaminedCursor ?? '-'}');
  stdout.writeln('safe_resume_cursor=${summary.safeResumeCursor ?? '-'}');
  stdout.writeln('[top_blocker_reasons]');
  for (final entry in summary.topBlockerReasons()) {
    stdout.writeln('${entry.key}=${entry.value}');
  }
  if (summary.failedProductIds.isNotEmpty) {
    stdout.writeln('[failed_product_ids]');
    for (final productId in summary.failedProductIds) {
      stdout.writeln(productId);
    }
  }
}

void _printInspection(ScoreAuditSampleInspection result) {
  stdout.writeln('[sample]');
  stdout.writeln('product_id=${result.productId}');
  stdout.writeln('barcode=${result.barcode ?? '-'}');
  stdout.writeln(
    'current_calculated_score=${result.currentCalculatedScore ?? '-'}',
  );
  stdout.writeln('snapshot_score=${result.snapshotScore ?? '-'}');
  stdout.writeln('fingerprint_match=${result.fingerprintMatch}');
  stdout.writeln('current_versions=${result.currentVersions ?? '-'}');
  stdout.writeln('snapshot_versions=${result.snapshotVersions ?? '-'}');
  stdout.writeln('validation_status=${result.validationStatus}');
  stdout.writeln('gate_status=${result.gateStatus}');
  if (result.error != null) stdout.writeln('error=${result.error}');
}

void _printUsage() {
  stdout.writeln('''
Usage:
  dart run tool/score_audit_backfill.dart --project-ref REF --dry-run [options]
  dart run tool/score_audit_backfill.dart --project-ref REF --apply \\
    --confirm-write-audit-snapshots [options]
  dart run tool/score_audit_backfill.dart --project-ref REF \\
    --sample-product-ids ID[,ID...]

Options:
  --batch-size N          Product page size, 1-500 (default: 100)
  --start-after UUID      Resume strictly after this product ID
  --max-products N        Bound the number of products examined
  --sample-product-ids    Read-only post-backfill sample inspection

Credentials are read only from SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY. They are never printed or loaded from a file.
Apply mode requires --max-products as an additional production safety bound.
''');
}
