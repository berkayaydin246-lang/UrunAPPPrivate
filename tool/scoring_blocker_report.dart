import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/scoring_blocker_diagnostic.dart';

const _majorBlockerGroups = <String>[
  'fvl_unknown',
  'missing_fiber',
  'canonical_additive_unresolved',
  'canonical_additive_risk_conflict',
  'canonical_additive_unknown_risk',
  'ingredients_incomplete',
  'basis_unit_ambiguous',
  'missing_classification',
  'basis_unknown',
  'missing_energy_kj',
];

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

  final dataSource = _RestScoringBlockerDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  try {
    final catalogue = await dataSource.fetchIngredientCatalogue();
    if (options.blockerSamples != null) {
      final samples = await _collectBlockerSamples(
        dataSource: dataSource,
        ingredientCatalogue: catalogue,
        samplesPerGroup: options.blockerSamples!,
        batchSize: options.batchSize,
        scanLimit: options.scanLimit,
      );
      stdout.writeln(_formatBlockerSamples(samples));
      return;
    }

    final List<Product> products;
    if (options.productId != null) {
      final product = await dataSource.fetchProductById(options.productId!);
      products = product == null ? const [] : [product];
    } else {
      products = await dataSource.fetchProductsByExactName(
        options.productName!,
      );
    }
    if (products.isEmpty) {
      stdout.writeln('[RESULT]\nproduct_not_found=true');
      exitCode = 2;
      return;
    }
    final staging = await dataSource.fetchStagingMatches(
      products
          .map((product) => product.sourceUrl?.trim())
          .whereType<String>()
          .where((sourceUrl) => sourceUrl.isNotEmpty)
          .toSet(),
    );
    const service = ScoringBlockerDiagnosticService();
    const formatter = ScoringBlockerReportFormatter();
    for (var index = 0; index < products.length; index++) {
      final product = products[index];
      final report = await service.inspect(
        product: product,
        stagingMatches: staging[product.sourceUrl?.trim()] ?? const [],
        ingredientCatalogue: catalogue,
      );
      if (index > 0) stdout.writeln();
      stdout.writeln(formatter.format(report));
    }
  } on Object catch (error) {
    // Remote failures can contain request metadata. Report only the type.
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

class _CliOptions {
  const _CliOptions({
    required this.help,
    required this.productName,
    required this.productId,
    required this.blockerSamples,
    required this.batchSize,
    required this.scanLimit,
  });

  final bool help;
  final String? productName;
  final String? productId;
  final int? blockerSamples;
  final int batchSize;
  final int scanLimit;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(
        help: true,
        productName: null,
        productId: null,
        blockerSamples: null,
        batchSize: 50,
        scanLimit: 1000,
      );
    }
    final productName = _value(arguments, '--product-name')?.trim();
    final productId = _value(arguments, '--product-id')?.trim();
    final blockerSamples = _intValue(arguments, '--blocker-samples');
    final selectedModes = [
      productName?.isNotEmpty == true,
      productId?.isNotEmpty == true,
      blockerSamples != null,
    ].where((selected) => selected).length;
    if (selectedModes != 1) {
      throw const FormatException(
        'choose exactly one of --product-name, --product-id, or '
        '--blocker-samples',
      );
    }
    if (blockerSamples != null && (blockerSamples < 1 || blockerSamples > 20)) {
      throw const FormatException('--blocker-samples must be between 1 and 20');
    }
    final batchSize = _intValue(arguments, '--batch-size') ?? 50;
    if (batchSize < 1 || batchSize > 100) {
      throw const FormatException('--batch-size must be between 1 and 100');
    }
    final scanLimit = _intValue(arguments, '--scan-limit') ?? 1000;
    if (scanLimit < 1) {
      throw const FormatException('--scan-limit must be positive');
    }
    return _CliOptions(
      help: false,
      productName: productName,
      productId: productId,
      blockerSamples: blockerSamples,
      batchSize: batchSize,
      scanLimit: scanLimit,
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
    const flags = {'--help', '-h'};
    const valueOptions = {
      '--product-name',
      '--product-id',
      '--blocker-samples',
      '--batch-size',
      '--scan-limit',
    };
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

class _BlockerSample {
  const _BlockerSample({
    required this.productId,
    required this.productName,
    required this.blocker,
  });

  final String productId;
  final String productName;
  final String blocker;
}

class _BlockerSampleSummary {
  const _BlockerSampleSummary({
    required this.samplesPerGroup,
    required this.scanLimit,
    required this.productsExamined,
    required this.completed,
    required this.samples,
  });

  final int samplesPerGroup;
  final int scanLimit;
  final int productsExamined;
  final bool completed;
  final Map<String, List<_BlockerSample>> samples;
}

Future<_BlockerSampleSummary> _collectBlockerSamples({
  required _RestScoringBlockerDataSource dataSource,
  required List<Ingredient> ingredientCatalogue,
  required int samplesPerGroup,
  required int batchSize,
  required int scanLimit,
}) async {
  final samples = {
    for (final blocker in _majorBlockerGroups) blocker: <_BlockerSample>[],
  };
  const recovery = LegacyScoringEvidenceRecoveryService();
  String? cursor;
  var productsExamined = 0;
  var completed = false;
  while (productsExamined < scanLimit) {
    final limit = (scanLimit - productsExamined).clamp(1, batchSize);
    final products = await dataSource.fetchSamplingProductsAfter(
      afterProductId: cursor,
      limit: limit,
    );
    if (products.isEmpty) {
      completed = true;
      break;
    }
    final staging = await dataSource.fetchStagingMatches(
      products
          .map((product) => product.sourceUrl?.trim())
          .whereType<String>()
          .where((sourceUrl) => sourceUrl.isNotEmpty)
          .toSet(),
    );
    for (final product in products) {
      productsExamined++;
      cursor = product.id;
      final result = await recovery.recover(
        product: product,
        stagingMatches: staging[product.sourceUrl?.trim()] ?? const [],
        ingredientCatalogue: ingredientCatalogue,
      );
      for (final blocker in result.blockerReasons) {
        final group = samples[blocker];
        if (group == null || group.length >= samplesPerGroup) continue;
        group.add(
          _BlockerSample(
            productId: product.id,
            productName: product.name,
            blocker: blocker,
          ),
        );
      }
      if (samples.values.every((items) => items.length >= samplesPerGroup)) {
        return _BlockerSampleSummary(
          samplesPerGroup: samplesPerGroup,
          scanLimit: scanLimit,
          productsExamined: productsExamined,
          completed: false,
          samples: samples,
        );
      }
      if (productsExamined >= scanLimit) break;
    }
  }
  return _BlockerSampleSummary(
    samplesPerGroup: samplesPerGroup,
    scanLimit: scanLimit,
    productsExamined: productsExamined,
    completed: completed,
    samples: samples,
  );
}

String _formatBlockerSamples(_BlockerSampleSummary summary) {
  String safe(String value) =>
      value.trim().replaceAll(RegExp(r'[\r\n\t]+'), ' ');
  final lines = <String>[
    '[BLOCKER SAMPLES]',
    'samples_per_group=${summary.samplesPerGroup}',
    'products_examined=${summary.productsExamined}',
    'scan_limit=${summary.scanLimit}',
    'catalogue_exhausted=${summary.completed}',
    'server_filters=scoring_evidence_is_null,ingredients_text_not_null,nutrition_text_not_null',
  ];
  for (final blocker in _majorBlockerGroups) {
    final samples = summary.samples[blocker] ?? const [];
    lines
      ..add('')
      ..add('[$blocker]')
      ..add('sample_count=${samples.length}');
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index];
      lines.add(
        'sample[$index]=product_id=${safe(sample.productId)} '
        'name=${safe(sample.productName)} blocker=${sample.blocker}',
      );
    }
  }
  return lines.join('\n');
}

class _RestScoringBlockerDataSource {
  _RestScoringBlockerDataSource({
    required this.baseUri,
    required this.serviceRoleKey,
  });

  final Uri baseUri;
  final String serviceRoleKey;
  final HttpClient _client = HttpClient();

  void close() => _client.close(force: true);

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

  Future<Product?> fetchProductById(String productId) async {
    final rows = await _getRows('products', {
      'select': '*',
      'id': 'eq.$productId',
      'limit': '1',
    });
    return rows.isEmpty ? null : Product.fromJson(rows.single);
  }

  Future<List<Product>> fetchProductsByExactName(String productName) async {
    final rows = await _getRows('products', {
      'select': '*',
      'name': 'eq.$productName',
      'order': 'id.asc',
      'limit': '20',
    });
    return rows.map(Product.fromJson).toList(growable: false);
  }

  Future<List<Product>> fetchSamplingProductsAfter({
    required String? afterProductId,
    required int limit,
  }) async {
    final rows = await _getRows('products', {
      'select': '*',
      'scoring_evidence': 'is.null',
      'ingredients_text': 'not.is.null',
      'nutrition_text': 'not.is.null',
      'order': 'id.asc',
      'limit': '$limit',
      if (afterProductId != null) 'id': 'gt.$afterProductId',
    });
    return rows.map(Product.fromJson).toList(growable: false);
  }

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
    final request = await _client.getUrl(uri);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
      ..set('apikey', serviceRoleKey)
      ..set(HttpHeaders.acceptHeader, 'application/json')
      ..set(HttpHeaders.userAgentHeader, 'etiketly-scoring-blocker-report/1');
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Read-only request failed.');
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! List) {
      throw const FormatException('Expected a row list.');
    }
    return decoded
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }
}

void _printUsage() {
  stdout.writeln(r'''
Usage:
  dart run tool/scoring_blocker_report.dart \
    --product-name "7 Days Çilekli Kruvasan 60 G"
  dart run tool/scoring_blocker_report.dart --product-id UUID
  dart run tool/scoring_blocker_report.dart --blocker-samples 5 [options]

Options:
  --batch-size N       Sampling page size, 1-100 (default: 50)
  --scan-limit N       Maximum products sampled client-side (default: 1000)

The tool performs GET requests only. Sampling applies server-side filters for
NULL scoring evidence and visible ingredient/nutrition data, then stops when
all groups are full or the scan limit is reached.

Credentials are read only from SUPABASE_URL and
SUPABASE_SERVICE_ROLE_KEY. They are never printed or loaded from a file.
''');
}
