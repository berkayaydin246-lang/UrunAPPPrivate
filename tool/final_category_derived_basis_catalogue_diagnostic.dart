import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Category-derived nutrition-basis fallback — read-only catalogue
/// diagnostic.
///
/// STRICTLY READ-ONLY: zero Supabase writes, zero scoring/audit writes.
/// Runs the REAL, already-fixed [LegacyScoringEvidenceRecoveryService]
/// (the exact same service both the fresh-recovery path AND the
/// existing-evidence-upgrade path in
/// legacy_scoring_recovery_lifecycle_runner.dart already call) against
/// every catalogue product, purely to MEASURE how many products the new
/// deterministic category-derived basis fallback (product decision) now
/// resolves — never to apply anything.
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

  final dataSource = _RestDiagnosticDataSource(
    baseUri: baseUri,
    serviceRoleKey: serviceRoleKey,
  );
  const recoveryService = LegacyScoringEvidenceRecoveryService();
  const biscolataProductId = 'b7473a54-42d6-4844-a41e-9151ee81fa10';

  try {
    stdout.writeln('[fetch]');
    final catalogue = await dataSource.fetchIngredientCatalogue();
    stdout.writeln('ingredient_catalogue_size=${catalogue.length}');

    final products = await dataSource.fetchAllProducts(limit: options.limit);
    stdout.writeln('products_fetched=${products.length}');

    final sourceUrls = products
        .map((product) => product.sourceUrl?.trim())
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet();
    final stagingByUrl = await dataSource.fetchStagingRowsBySourceUrl(
      sourceUrls,
    );
    stdout.writeln('distinct_source_urls=${sourceUrls.length}');

    var alreadyTrustedBasis = 0;
    var notScoreEligible = 0;
    var noStagingMatch = 0;
    var alreadyExactSourceBasis = 0;
    var currentlyBlockedUnknownBasis = 0;
    var categoryFallbackPer100g = 0;
    var categoryFallbackPer100ml = 0;
    var stillBasisAmbiguous = 0;
    var wouldBeScoreableAfterFallback = 0;
    var stillBlockedOtherReasons = 0;
    var unexpectedErrors = 0;

    Map<String, Object?>? biscolataReport;

    for (final product in products) {
      try {
        final existingProvenance =
            product.scoringEvidence?.nutritionBasisEvidence?.provenance;
        if (existingProvenance == EvidenceProvenance.declaredLabel ||
            existingProvenance == EvidenceProvenance.adminVerified) {
          alreadyTrustedBasis++;
          if (product.id == biscolataProductId) {
            biscolataReport = {
              'resolved_basis':
                  product.scoringEvidence!.nutritionBasisEvidence!.value!.name,
              'basis_provenance': existingProvenance!.name,
              'remaining_blockers': '(already trusted before this pass)',
              'would_display_numeric_score': 'true (already trusted)',
            };
          }
          continue;
        }

        final sourceUrl = product.sourceUrl?.trim();
        final matches = (sourceUrl != null && sourceUrl.isNotEmpty)
            ? (stagingByUrl[sourceUrl] ?? const <LegacyStagingScoringEvidence>[])
            : const <LegacyStagingScoringEvidence>[];

        final result = await recoveryService.recover(
          product: product,
          stagingMatches: matches,
          ingredientCatalogue: catalogue,
        );

        if (result.notScoreEligible) {
          notScoreEligible++;
          continue;
        }
        if (!result.stagingMatch) {
          noStagingMatch++;
          if (product.id == biscolataProductId) {
            biscolataReport = {
              'resolved_basis': 'unknown',
              'basis_provenance': 'none',
              'remaining_blockers': 'missing_staging_match',
              'would_display_numeric_score': 'false',
            };
          }
          continue;
        }

        final resultProvenance =
            result.evidence?.nutritionBasisEvidence?.provenance;
        Map<String, Object?>? thisReport;
        if (product.id == biscolataProductId) {
          thisReport = {
            'resolved_basis':
                result.evidence?.nutritionBasisEvidence?.value?.name ??
                    'unknown',
            'basis_provenance': resultProvenance?.name ?? 'none',
            'remaining_blockers': result.blockerReasons.isEmpty
                ? '(none)'
                : result.blockerReasons.join(','),
            'would_display_numeric_score':
                '${result.finalScoreReady} (predicted eligibility only — '
                'actual public display additionally requires an applied '
                'write and a matching current audit snapshot)',
          };
        }

        if (resultProvenance == EvidenceProvenance.declaredLabel) {
          alreadyExactSourceBasis++;
          biscolataReport ??= thisReport;
          continue;
        }

        // From here, this product IS part of the "basis was generic/
        // unproven from source" population this pass targets.
        currentlyBlockedUnknownBasis++;

        if (resultProvenance == EvidenceProvenance.categoryDerived) {
          final basisValue = result.evidence!.nutritionBasisEvidence!.value!;
          if (basisValue == NutritionBasis.per100g) categoryFallbackPer100g++;
          if (basisValue == NutritionBasis.per100ml) {
            categoryFallbackPer100ml++;
          }
          if (result.finalScoreReady) {
            wouldBeScoreableAfterFallback++;
          } else {
            stillBlockedOtherReasons++;
          }
        } else {
          stillBasisAmbiguous++;
        }

        biscolataReport ??= thisReport;
      } on Object catch (error) {
        unexpectedErrors++;
        if (product.id == biscolataProductId) {
          biscolataReport = {
            'resolved_basis': 'unexpected_error',
            'basis_provenance': 'none',
            'remaining_blockers': error.runtimeType.toString(),
            'would_display_numeric_score': 'false',
          };
        }
      }
    }

    stdout.writeln('[category_derived_basis_catalogue_diagnostic]');
    stdout.writeln('total_catalogue=${products.length}');
    stdout.writeln('currently_blocked_unknown_basis=$currentlyBlockedUnknownBasis');
    stdout.writeln('category_fallback_per100g=$categoryFallbackPer100g');
    stdout.writeln('category_fallback_per100ml=$categoryFallbackPer100ml');
    stdout.writeln('still_basis_ambiguous=$stillBasisAmbiguous');
    stdout.writeln('would_be_scoreable_after_fallback=$wouldBeScoreableAfterFallback');
    stdout.writeln('still_blocked_other_reasons=$stillBlockedOtherReasons');
    stdout.writeln('unexpected_errors=$unexpectedErrors');

    stdout.writeln('[other_populations_not_in_the_above_counts]');
    stdout.writeln(
      'already_trusted_basis_before_this_pass=$alreadyTrustedBasis',
    );
    stdout.writeln('not_score_eligible=$notScoreEligible');
    stdout.writeln('no_staging_match=$noStagingMatch');
    stdout.writeln('already_exact_source_basis=$alreadyExactSourceBasis');

    stdout.writeln('[biscolata_starz_bitter]');
    stdout.writeln('product_id=$biscolataProductId');
    if (biscolataReport == null) {
      stdout.writeln('status=not_found_in_scanned_range');
    } else {
      for (final entry in biscolataReport.entries) {
        stdout.writeln('${entry.key}=${entry.value}');
      }
    }
  } on Object catch (error) {
    stderr.writeln('error=${error.runtimeType}');
    exitCode = 1;
  } finally {
    dataSource.close();
  }
}

class _CliOptions {
  const _CliOptions({required this.help, required this.projectRef, this.limit});

  final bool help;
  final String projectRef;
  final int? limit;

  static _CliOptions parse(List<String> arguments) {
    _validateArguments(arguments);
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const _CliOptions(help: true, projectRef: '');
    }
    final projectRef = _requiredValue(arguments, '--project-ref');
    if (!RegExp(r'^[a-z0-9]{20}$').hasMatch(projectRef)) {
      throw const FormatException('invalid --project-ref');
    }
    final limit = _intValue(arguments, '--limit');
    if (limit != null && limit < 1) {
      throw const FormatException('--limit must be at least 1');
    }
    return _CliOptions(help: false, projectRef: projectRef, limit: limit);
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
    const flags = {'--help', '-h'};
    const valueOptions = {'--project-ref', '--limit'};
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

class _RestDiagnosticDataSource {
  _RestDiagnosticDataSource({required this.baseUri, required this.serviceRoleKey});

  final Uri baseUri;
  final String serviceRoleKey;
  final HttpClient _client = HttpClient();

  void close() => _client.close(force: true);

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

  Future<List<Product>> fetchAllProducts({int? limit}) async {
    final result = <Product>[];
    String? cursor;
    while (limit == null || result.length < limit) {
      final pageSize = limit == null ? 200 : (limit - result.length).clamp(1, 200);
      final rows = await _getRows('products', {
        'select': '*',
        'order': 'id.asc',
        'limit': '$pageSize',
        if (cursor != null) 'id': 'gt.$cursor',
      });
      if (rows.isEmpty) break;
      result.addAll(rows.map(Product.fromJson));
      cursor = result.last.id;
      if (rows.length < pageSize) break;
    }
    return result;
  }

  Future<Map<String, List<LegacyStagingScoringEvidence>>> fetchStagingRowsBySourceUrl(
    Set<String> sourceUrls,
  ) async {
    final result = <String, List<LegacyStagingScoringEvidence>>{};
    final ordered = sourceUrls.toList()..sort();
    for (var offset = 0; offset < ordered.length; offset += 20) {
      final end = (offset + 20).clamp(0, ordered.length);
      final filter = ordered.sublist(offset, end).map(_postgrestQuoted).join(',');
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
        result.putIfAbsent(normalizedSourceUrl, () => []).add(evidence);
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
        'etiketly-final-category-derived-basis-catalogue-diagnostic/1',
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
  dart run tool/final_category_derived_basis_catalogue_diagnostic.dart --project-ref <ref>

Options:
  --project-ref <ref>   Supabase project ref (20 lowercase alnum chars). Required.
  --limit <n>            Bound the number of catalogue products scanned (local testing only).

STRICTLY READ-ONLY: zero Supabase writes, zero scoring/audit writes.
Credentials are read only from SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
(or SUPABASE_SERVICE_KEY). They are never printed.
''');
}
