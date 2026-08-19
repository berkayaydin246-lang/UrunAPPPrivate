import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_snapshot_builder.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';

/// PART E/F: READ-ONLY V3 shadow-coverage verifier + simulated-cutover
/// check. NO write code path exists anywhere in this file -- it never
/// imports or calls insertSnapshot/record_product_score_audit_snapshot.
/// Every network call is a GET (products/ingredients) or the read-only
/// get_current_product_score_audit_snapshot RPC.
///
/// For each scoreable product it:
///   1. Evaluates V3 (NutritionQualityTransformer.v3()) via the exact same
///      ProductScoreAuditEvaluator the real backfill tool uses.
///   2. If not finalScoreReady -> counts as blocked (PART H: blocked stays
///      blocked; this tool never re-derives or repairs evidence).
///   3. If ready: independently re-validates the freshly-built snapshot
///      via EtiketlyScoreAuditValidator (validator_failures if it fails --
///      expect 0, now that the version-set gap is fixed).
///   4. Looks up whether a matching TRUSTED v3 snapshot already exists via
///      the real, production read RPC (matching_trusted_snapshot vs
///      missing_trusted_snapshot).
///   5. PART F simulation: runs the REAL EtiketlyPublicScoreAuditGate with
///      current=the fresh v3 evaluation, trusted=the fetched v3 snapshot
///      (if any) -- proving whether cutover to v3 would actually resolve
///      to `matching` (publicly displayable) for this product, not just
///      "a row exists". The production default transformer is NEVER
///      touched by this simulation.
///
/// coverage_complete = (v3_missing_trusted_snapshot == 0
///                       && v3_validator_failures == 0
///                       && unexpected_errors == 0
///                       && examined all currently-scoreable products,
///                          i.e. reached_limit == false)
Future<void> main(List<String> arguments) async {
  final projectRef = _requiredValue(arguments, '--project-ref');
  final maxProducts = _intValue(arguments, '--max-products');
  final startAfter = _value(arguments, '--start-after');
  // Post-cutover (TASK E): exercise the REAL default code path -- the
  // exact same ProductScoreAuditEvaluator()/ProductEtiketlyScoreOrchestrator()
  // construction production uses, with NO explicit transformer override at
  // all. Without this flag (pre-cutover / Phase 1 shadow usage), an
  // explicitly-.v3()-configured evaluator is used instead, so this tool
  // stays useful both before and after cutover.
  final useDefaultOrchestrator = arguments.contains('--use-default-orchestrator');

  final environment = Platform.environment;
  final supabaseUrl = environment['SUPABASE_URL']?.trim() ?? '';
  final serviceRoleKey =
      environment['SUPABASE_SERVICE_ROLE_KEY']?.trim() ??
      environment['SUPABASE_SERVICE_KEY']?.trim() ??
      '';
  final baseUri = Uri.tryParse(supabaseUrl);
  if (baseUri == null ||
      baseUri.scheme != 'https' ||
      baseUri.host != '$projectRef.supabase.co' ||
      serviceRoleKey.isEmpty) {
    stderr.writeln('error=invalid_or_missing_supabase_environment');
    exitCode = 78;
    return;
  }

  final client = HttpClient();
  // Explicit-v3 evaluator: used pre-cutover (Phase 1 shadow verification),
  // where the production default is still V2 and we need to deliberately
  // ask for V3 to check shadow coverage.
  const explicitV3Evaluator = ProductScoreAuditEvaluator(
    matcher: IngredientMatcherService(),
    riskService: CanonicalIngredientRiskService(),
    inputAdapter: ProductScoringInputAdapter(),
    orchestrator: ProductEtiketlyScoreOrchestrator(
      nutritionQualityTransformer: NutritionQualityTransformer.v3(),
    ),
    builder: EtiketlyScoreAuditSnapshotBuilder(),
    validator: EtiketlyScoreAuditValidator(),
  );
  // Bare-default evaluator: the exact same construction production uses
  // (ProductScoreAuditEvaluator()'s own defaults all the way down to
  // ProductEtiketlyScoreOrchestrator()'s default NutritionQualityTransformer()).
  // Used post-cutover (TASK E) to prove the ACTUAL default code path, not
  // a parallel explicitly-configured one.
  const defaultEvaluator = ProductScoreAuditEvaluator();
  final v3Evaluator = useDefaultOrchestrator ? defaultEvaluator : explicitV3Evaluator;
  stdout.writeln(
    'evaluator_mode=${useDefaultOrchestrator ? 'PRODUCTION_DEFAULT (no explicit version injected)' : 'explicit_v3_shadow'}',
  );
  const gate = EtiketlyPublicScoreAuditGate();
  const validator = EtiketlyScoreAuditValidator();

  var v2CurrentScoreablePopulation = 0;
  var v3Eligible = 0;
  var v3MatchingTrustedSnapshot = 0;
  var v3MissingTrustedSnapshot = 0;
  var v3ValidatorFailures = 0;
  var v3Blocked = 0;
  var unexpectedErrors = 0;
  var simulatedCutoverWouldDisplay = 0;
  var simulatedCutoverWouldNotDisplay = 0;
  var examined = 0;
  var reachedLimit = false;
  String? lastCursor = startAfter;
  String? observedDefaultTransformVersion;

  try {
    final catalogue = await _fetchIngredientCatalogue(client, baseUri, serviceRoleKey);
    stderr.writeln('catalogue size=${catalogue.length}');

    while (true) {
      if (maxProducts != null && examined >= maxProducts) {
        reachedLimit = true;
        break;
      }
      final pageLimit = maxProducts == null
          ? 200
          : (maxProducts - examined).clamp(1, 200);
      final rows = await _getRows(client, baseUri, serviceRoleKey, 'products', {
        'select': '*',
        'order': 'id.asc',
        'limit': '$pageLimit',
        if (lastCursor != null) 'id': 'gt.$lastCursor',
      });
      if (rows.isEmpty) break;

      for (final row in rows) {
        if (maxProducts != null && examined >= maxProducts) {
          reachedLimit = true;
          break;
        }
        examined += 1;
        lastCursor = row['id'] as String;
        final product = Product.fromJson(row);
        if (product.scoringEvidence == null) continue;

        try {
          final result = await v3Evaluator.evaluate(product, catalogue);
          if (!result.finalScoreReady) {
            v3Blocked += 1;
            continue;
          }
          v2CurrentScoreablePopulation += 1;
          v3Eligible += 1;
          final snapshot = result.snapshot!;
          observedDefaultTransformVersion ??= snapshot.nutritionTransformVersion;

          final ownValidation = validator.validate(snapshot);
          if (!ownValidation.isValid) {
            v3ValidatorFailures += 1;
            stdout.writeln(
              'validator_failure product_id=${product.id} issues=${ownValidation.issues}',
            );
            continue;
          }

          final trusted = await _fetchMatchingSnapshot(
            client,
            baseUri,
            serviceRoleKey,
            snapshot,
          );
          if (trusted == null) {
            v3MissingTrustedSnapshot += 1;
          } else {
            v3MatchingTrustedSnapshot += 1;
          }

          final decision = gate.evaluate(current: snapshot, trusted: trusted);
          if (decision.mayDisplayNumericScore) {
            simulatedCutoverWouldDisplay += 1;
          } else {
            simulatedCutoverWouldNotDisplay += 1;
          }
        } catch (error) {
          unexpectedErrors += 1;
          stdout.writeln(
            'unexpected_error product_id=${product.id} type=${error.runtimeType} error=$error',
          );
        }
      }
      if (rows.length < pageLimit) break; // natural end of catalogue
    }
  } finally {
    client.close(force: true);
  }

  final coverageComplete = v3MissingTrustedSnapshot == 0 &&
      v3ValidatorFailures == 0 &&
      unexpectedErrors == 0 &&
      !reachedLimit;

  stdout.writeln('[coverage_summary]');
  stdout.writeln('observed_default_transform_version=${observedDefaultTransformVersion ?? '-'}');
  stdout.writeln('examined=$examined');
  stdout.writeln('v2_current_scoreable_population=$v2CurrentScoreablePopulation');
  stdout.writeln('v3_eligible=$v3Eligible');
  stdout.writeln('v3_matching_trusted_snapshot=$v3MatchingTrustedSnapshot');
  stdout.writeln('v3_missing_trusted_snapshot=$v3MissingTrustedSnapshot');
  stdout.writeln('v3_validator_failures=$v3ValidatorFailures');
  stdout.writeln('v3_blocked=$v3Blocked');
  stdout.writeln('unexpected_errors=$unexpectedErrors');
  stdout.writeln(
    'v2_snapshots_still_present=not_queryable_directly '
    '(product_score_audit_snapshots has no direct SELECT grant by design; '
    'see tool/v3_migration_contract_verifier.dart for the structural '
    'no-mutation guarantee instead)',
  );
  stdout.writeln(
    'duplicate_or_conflicting_v3_snapshot_count=0_by_construction '
    '(product_score_audit_snapshots_current_input_key UNIQUE constraint '
    'makes a true duplicate impossible at the database level)',
  );
  stdout.writeln('reached_limit=$reachedLimit');
  stdout.writeln('coverage_complete=$coverageComplete');
  stdout.writeln('[simulated_cutover_summary]');
  stdout.writeln('would_display_publicly_under_v3=$simulatedCutoverWouldDisplay');
  stdout.writeln('would_NOT_display_publicly_under_v3=$simulatedCutoverWouldNotDisplay');
  stdout.writeln(
    useDefaultOrchestrator
        ? 'production_default_transformer_MUTATED_by_this_run=false '
              '(this run READS the real default ProductEtiketlyScoreOrchestrator()/'
              'ProductScoreAuditEvaluator() construction to prove the actual '
              'default code path -- it never assigns to or redefines that default)'
        : 'production_default_transformer_touched_by_this_run=false '
              '(this run uses an explicitly-.v3()-configured evaluator, never '
              'the default ProductEtiketlyScoreOrchestrator() at all)',
  );
  stdout.writeln('safe_resume_cursor=${lastCursor ?? '-'}');

  if (!coverageComplete) exitCode = 1;
}

Future<EtiketlyScoreAuditSnapshot?> _fetchMatchingSnapshot(
  HttpClient client,
  Uri baseUri,
  String serviceRoleKey,
  EtiketlyScoreAuditSnapshot current,
) async {
  final response = await _postRpc(
    client,
    baseUri,
    serviceRoleKey,
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
  return EtiketlyScoreAuditSnapshot.tryFromJson(response);
}

Future<Object?> _postRpc(
  HttpClient client,
  Uri baseUri,
  String serviceRoleKey,
  String functionName,
  Map<String, Object?> body,
) async {
  final uri = baseUri.replace(path: '/rest/v1/rpc/$functionName');
  final request = await client.postUrl(uri);
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
    ..set('apikey', serviceRoleKey)
    ..set(HttpHeaders.acceptHeader, 'application/json')
    ..set(HttpHeaders.userAgentHeader, 'etiketly-v3-coverage-verifier/1');
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('remote_http_${response.statusCode}: $responseBody');
  }
  if (responseBody.trim().isEmpty) return null;
  return jsonDecode(responseBody);
}

Future<List<Ingredient>> _fetchIngredientCatalogue(
  HttpClient client,
  Uri baseUri,
  String serviceRoleKey,
) async {
  final ingredients = <Ingredient>[];
  String? cursor;
  while (true) {
    final query = <String, String>{
      'select': '*',
      'order': 'id.asc',
      'limit': '500',
      if (cursor != null) 'id': 'gt.$cursor',
    };
    final rows = await _getRows(client, baseUri, serviceRoleKey, 'ingredients', query);
    if (rows.isEmpty) break;
    ingredients.addAll(rows.map(Ingredient.fromJson));
    cursor = rows.last['id'] as String;
    if (rows.length < 500) break;
  }
  return ingredients;
}

Future<List<Map<String, dynamic>>> _getRows(
  HttpClient client,
  Uri baseUri,
  String serviceRoleKey,
  String table,
  Map<String, String> query,
) async {
  final uri = baseUri.replace(path: '/rest/v1/$table', queryParameters: query);
  final request = await client.getUrl(uri);
  request.headers
    ..set(HttpHeaders.authorizationHeader, 'Bearer $serviceRoleKey')
    ..set('apikey', serviceRoleKey)
    ..set(HttpHeaders.acceptHeader, 'application/json');
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('remote_http_${response.statusCode}');
  }
  final decoded = jsonDecode(body);
  if (decoded is! List) throw const FormatException('expected_rows');
  return decoded
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList(growable: false);
}

String _requiredValue(List<String> arguments, String name) {
  final value = _value(arguments, name);
  if (value == null || value.isEmpty) {
    throw FormatException('$name is required');
  }
  return value;
}

int? _intValue(List<String> arguments, String name) {
  final raw = _value(arguments, name);
  if (raw == null) return null;
  final value = int.tryParse(raw);
  if (value == null) throw FormatException('$name must be an integer');
  return value;
}

String? _value(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0) return null;
  if (index + 1 >= arguments.length) {
    throw FormatException('$name requires a value');
  }
  return arguments[index + 1];
}
