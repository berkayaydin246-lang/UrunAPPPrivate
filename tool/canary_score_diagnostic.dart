import 'dart:convert';
import 'dart:io';

import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/validated_nutrition_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';

/// READ-ONLY diagnostic: runs the REAL, unmodified production scoring
/// pipeline (ProductScoringInputAdapter -> ScoringReadinessEvaluator ->
/// NutritionRawScoreCalculator -> NutritionQualityTransformer,
/// CanonicalIngredientRiskService.assessForScoring ->
/// AdditiveQualityTransformer, EtiketlyScoreCalculator) for one or more
/// real products and prints a complete numeric breakdown as JSON, one line
/// per product.
///
/// GET-only against Supabase. There is no write code path in this file at
/// all — no PATCH/POST/DELETE is ever issued.
Future<void> main(List<String> arguments) async {
  final productIds = _values(arguments, '--product-id');
  final nameContains = _values(arguments, '--name-contains');
  final allScoreableSummary = arguments.contains('--all-scoreable-summary');
  final projectRef = _requiredValue(arguments, '--project-ref');
  final transformVersionArg = _values(arguments, '--transform-version');
  final nutritionQualityTransformer = switch (transformVersionArg) {
    ['v1'] => const NutritionQualityTransformer.v1(),
    ['v2'] => const NutritionQualityTransformer.v2(),
    ['v3'] => const NutritionQualityTransformer.v3(),
    // No flag given: use whatever is CURRENTLY production-default (follows
    // cutover automatically -- this is V3 as of the V3 cutover).
    [] => const NutritionQualityTransformer(),
    _ => throw const FormatException(
      '--transform-version must be one of v1, v2, v3',
    ),
  };
  if (productIds.isEmpty && nameContains.isEmpty && !allScoreableSummary) {
    stderr.writeln(
      'error=at_least_one_of_--product-id_or_--name-contains_or_'
      '--all-scoreable-summary_required',
    );
    exitCode = 64;
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
      baseUri.host != '$projectRef.supabase.co' ||
      serviceRoleKey.isEmpty) {
    stderr.writeln('error=invalid_or_missing_supabase_environment');
    exitCode = 78;
    return;
  }

  final client = HttpClient();
  try {
    stderr.writeln('fetching ingredient catalogue...');
    final catalogue = await _fetchIngredientCatalogue(
      client,
      baseUri,
      serviceRoleKey,
    );
    stderr.writeln('catalogue size=${catalogue.length}');

    if (allScoreableSummary) {
      var cursor = '';
      var examined = 0;
      while (true) {
        final query = <String, String>{
          'select':
              'id,name,source,source_url,category_tags,canonical_category,'
              'canonical_subcategory,ingredients_text,scoring_evidence,'
              'created_at,updated_at',
          'scoring_evidence': 'not.is.null',
          'order': 'id.asc',
          'limit': '500',
          if (cursor.isNotEmpty) 'id': 'gt.$cursor',
        };
        final page = await _getRows(
          client,
          baseUri,
          serviceRoleKey,
          'products',
          query,
        );
        if (page.isEmpty) break;
        for (final row in page) {
          final product = Product.fromJson(row);
          final report = await _diagnose(
            product,
            catalogue,
            nutritionQualityTransformer,
          );
          stdout.writeln(jsonEncode(_summarize(report)));
          examined += 1;
        }
        cursor = page.last['id'] as String;
        if (page.length < 500) break;
        if (examined % 500 == 0) {
          stderr.writeln('examined=$examined...');
        }
      }
      stderr.writeln('done, examined=$examined');
      return;
    }

    final rows = <Map<String, dynamic>>[];
    for (final id in productIds) {
      rows.addAll(
        await _getRows(client, baseUri, serviceRoleKey, 'products', {
          'select': '*',
          'id': 'eq.$id',
          'limit': '1',
        }),
      );
    }
    for (final term in nameContains) {
      rows.addAll(
        await _getRows(client, baseUri, serviceRoleKey, 'products', {
          'select': '*',
          'name': 'ilike.*$term*',
          'limit': '25',
        }),
      );
    }

    for (final row in rows) {
      final product = Product.fromJson(row);
      final report = await _diagnose(
        product,
        catalogue,
        nutritionQualityTransformer,
      );
      stdout.writeln(jsonEncode(report));
    }
  } finally {
    client.close(force: true);
  }
}

Map<String, Object?> _summarize(Map<String, Object?> report) {
  final finalScore = report['final_score'] as Map<String, Object?>?;
  final categoryEvidence = report['category_evidence'] as Map<String, Object?>?;
  final nutritionRawScore = report['nutrition_raw_score'] as Map<String, Object?>?;
  return {
    'product_id': report['product_id'],
    'name': report['name'],
    'category': categoryEvidence?['resolved_category'],
    'error': report['error'],
    'is_calculated': report['is_calculated'],
    'score': finalScore?['score'],
    'raw_score': nutritionRawScore?['raw_score'],
    'nutrition_quality_score': report['nutrition_quality_score'],
    'additive_quality_score':
        (report['additive_quality'] as Map<String, Object?>?)?['quality_score'],
  };
}

Future<Map<String, Object?>> _diagnose(
  Product product,
  List<Ingredient> catalogue,
  NutritionQualityTransformer nutritionQualityTransformer,
) async {
  const matcher = IngredientMatcherService();
  const riskService = CanonicalIngredientRiskService();
  const inputAdapter = ProductScoringInputAdapter();
  final orchestrator = ProductEtiketlyScoreOrchestrator(
    nutritionQualityTransformer: nutritionQualityTransformer,
  );

  final base = <String, Object?>{
    'product_id': product.id,
    'transform_version': nutritionQualityTransformer.transformVersion,
    'name': product.name,
    'source': product.source,
    'source_url': product.sourceUrl,
    'category_tags': product.categoryTags,
    'canonical_category': product.canonicalCategory,
    'canonical_subcategory': product.canonicalSubcategory,
  };

  if (product.scoringEvidence == null) {
    return {...base, 'error': 'no_scoring_evidence'};
  }

  final ingredientText = product.ingredientsText?.trim() ?? '';
  base['ingredients_text'] = ingredientText;

  final input = inputAdapter.fromProduct(product);
  base['category_evidence'] = {
    'resolved_category': input.categoryEvidence.resolvedCategory.name,
    'source': input.categoryEvidence.source.name,
    'evidence_values': input.categoryEvidence.evidenceValues,
    'reasons': input.categoryEvidence.reasons.map((r) => r.name).toList(),
  };
  base['nutrition_basis'] = input.nutritionBasis.name;
  base['product_state'] = input.productState.name;
  base['fvl_evidence'] = {
    'state': input.fvlEvidence.state.name,
    'percentage': input.fvlEvidence.percentage,
    'provenance': input.fvlEvidence.provenance.name,
    'verification': input.fvlEvidence.verification.name,
  };
  base['nns_evidence'] = {
    'state': input.nnsEvidence.state.name,
    'provenance': input.nnsEvidence.provenance.name,
    'verification': input.nnsEvidence.verification.name,
  };
  base['ingredient_evidence_completeness'] =
      input.ingredientEvidenceCompleteness.name;
  base['classification_facts'] = {
    'is_plain_water': input.classificationFacts.isPlainWater?.value,
    'is_beverage': input.classificationFacts.isBeverage?.value,
    'is_food_supplement': input.classificationFacts.isFoodSupplement?.value,
    'is_drinkable_dairy': input.classificationFacts.isDrinkableDairy?.value,
  };

  final nutrition = input.nutrition;
  base['nutrition_raw_evidence'] = {
    'energy_kj': _ev(nutrition.energyKj),
    'energy_kcal': _ev(nutrition.energyKcal),
    'total_fat': _ev(nutrition.totalFat),
    'saturated_fat': _ev(nutrition.saturatedFat),
    'sugars': _ev(nutrition.sugars),
    'protein': _ev(nutrition.protein),
    'fiber': _ev(nutrition.fiber),
    'salt': _ev(nutrition.salt),
    'sodium': _ev(nutrition.sodium),
  };

  if (ingredientText.isEmpty) {
    return {...base, 'error': 'missing_ingredients_text'};
  }
  final tokens = matcher.parseIngredients(ingredientText);
  if (tokens.isEmpty) {
    return {...base, 'error': 'unparseable_ingredients_text'};
  }

  final matching = await matcher.matchIngredientTokens(tokens, catalogue);
  final scoringCategory = input.categoryEvidence.resolvedCategory;
  final canonicalAssessment = riskService.assessForScoring(
    matching,
    scoringCategory: scoringCategory,
  );

  base['ingredient_matches'] = {
    'ordinary_count': canonicalAssessment.ordinaryIngredients.length,
    'unresolved_count': canonicalAssessment.unresolvedIngredients.length,
    'unresolved_tokens': canonicalAssessment.unresolvedIngredients
        .map((u) => u.normalizedToken)
        .toList(),
    'canonical_additives': canonicalAssessment.canonicalAdditives
        .map(
          (item) => {
            'canonical_name': item.canonicalName,
            'e_code': item.eCode,
            'is_additive': item.isAdditive,
            'affects_current_analysis': item.affectsCurrentAnalysis,
            'risk_level': item.riskLevel.name,
            'risk_source': item.riskSource.name,
            'match_authority': item.matchAuthority.name,
            'nutrition_methodology_overlap': item.nutritionMethodologyOverlap
                .name,
          },
        )
        .toList(),
  };

  final evaluation = orchestrator.calculate(
    product: product,
    canonicalAssessment: canonicalAssessment,
  );
  if (evaluation == null) {
    return {...base, 'error': 'canonical_assessment_unavailable'};
  }

  base['nutrition_readiness'] = {
    'is_scorable': evaluation.nutritionReadiness.isScorable,
    'blocking_reasons': evaluation.nutritionReadiness.blockingReasons
        .map((b) => b.name)
        .toList(),
  };

  if (evaluation.nutritionReadiness.isScorable) {
    final validated = ValidatedNutritionScoringInput.validate(input);
    base['validated_nutrition_input'] = {
      'category': validated.category.name,
      'nutrition_basis': validated.nutritionBasis.name,
      'product_state': validated.productState.name,
      'energy_kj': validated.energyKj,
      'total_fat': validated.totalFat,
      'saturated_fat': validated.saturatedFat,
      'sugars': validated.sugars,
      'salt': validated.salt,
      'protein': validated.protein,
      'fiber': validated.fiber,
      'fvl_percentage': validated.fvlPercentage,
      'nns_present': validated.nnsPresent,
      'is_plain_water': validated.isPlainWater,
    };
  }

  final raw = evaluation.rawNutrition;
  if (raw != null && raw is CalculatedNutritionRawScoreResult) {
    base['nutrition_raw_score'] = {
      'resolved_category': raw.resolvedCategory.name,
      'negative_points': {
        'energy': raw.negativePoints.energyPoints,
        'sugars': raw.negativePoints.sugarsPoints,
        'saturated_fat': raw.negativePoints.saturatedFatPoints,
        'salt': raw.negativePoints.saltPoints,
        'nns': raw.negativePoints.nnsPoints,
        'saturated_energy': raw.negativePoints.saturatedEnergyPoints,
        'saturated_fat_ratio': raw.negativePoints.saturatedFatRatioPoints,
        'saturated_energy_kj': raw.negativePoints.saturatedEnergyKj,
        'saturated_fat_ratio_percent':
            raw.negativePoints.saturatedFatRatioPercent,
        'total': raw.negativePoints.total,
      },
      'positive_points': {
        'protein_calculated': raw.positivePoints.proteinPointsCalculated,
        'protein_applied': raw.positivePoints.proteinPointsApplied,
        'fiber': raw.positivePoints.fiberPoints,
        'fvl': raw.positivePoints.fvlPoints,
        'calculated_total': raw.positivePoints.calculatedTotal,
        'applied_total': raw.positivePoints.appliedTotal,
      },
      'raw_score': raw.rawScore,
      'special_rules': raw.specialRules.map((r) => r.name).toList(),
    };
  } else if (raw != null && raw.isPlainWaterSpecialCase) {
    base['nutrition_raw_score'] = {'special_case': 'plain_water'};
  }

  final nq = evaluation.nutritionQuality;
  if (nq != null) {
    base['nutrition_quality_score'] = nq.qualityScore;
    base['nutrition_transform_version'] = nq.transformVersion;
    base['nutrition_special_case'] = nq.specialCase.name;
  }

  final aq = evaluation.additiveQuality;
  base['additive_quality'] = {
    'quality_score': aq.qualityScore,
    'unclamped_quality_score': aq.unclampedQualityScore,
    'total_penalty': aq.totalPenalty,
    'eligible_unique_additive_count': aq.eligibleUniqueAdditiveCount,
    'low_count': aq.lowCount,
    'medium_count': aq.mediumCount,
    'high_count': aq.highCount,
    'penalized_low_count': aq.penalizedLowCount,
    'penalized_medium_count': aq.penalizedMediumCount,
    'penalized_high_count': aq.penalizedHighCount,
    'unknown_or_ineligible_count': aq.unknownOrIneligibleCount,
    'ordinary_ingredient_count': aq.ordinaryIngredientCount,
    // Note: this diagnostic deliberately does NOT report a per-item
    // ("itemPenalties") or unresolved-additive-candidate breakdown — those
    // fields are not part of the committed AdditiveQualityResult API this
    // tool is built against (see the additive-quarantine "item D5" work,
    // tracked separately, not part of the V3 cutover). Tier-level
    // contributions below are sufficient for every V3 diagnostic use
    // (transform version, raw score, nutrition/additive/final score,
    // canary and full-population validation) this tool exists for.
    'contributions': aq.contributions
        .map(
          (c) => {
            'risk_level': c.riskLevel.name,
            'penalized_count': c.penalizedCount,
            'first_item_impact': c.firstItemImpact,
            'additional_item_decay': c.additionalItemDecay,
            'penalty': c.penalty,
          },
        )
        .toList(),
  };

  base['final_readiness'] = {
    'is_calculable': evaluation.finalReadiness.isCalculable,
    'blocking_reasons': evaluation.finalReadiness.blockingReasons
        .map((b) => b.name)
        .toList(),
  };

  final result = evaluation.result;
  base['is_calculated'] = result.isCalculated;
  if (result.isCalculated) {
    base['final_score'] = {
      'score': result.score,
      'nutrition_contribution': result.nutritionContribution,
      'additive_contribution': result.additiveContribution,
    };
  }

  return base;
}

Map<String, Object?> _ev(EvidenceValue<double> value) => {
  'value': value.value,
  'provenance': value.provenance.name,
  'verification': value.verification.name,
};

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
    final rows = await _getRows(
      client,
      baseUri,
      serviceRoleKey,
      'ingredients',
      query,
    );
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

List<String> _values(List<String> arguments, String name) {
  final values = <String>[];
  for (var index = 0; index < arguments.length; index++) {
    if (arguments[index] != name) continue;
    if (index + 1 >= arguments.length) {
      throw FormatException('$name requires a value');
    }
    values.add(arguments[index + 1]);
  }
  return values;
}

String _requiredValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index < 0 || index + 1 >= arguments.length) {
    throw FormatException('$name is required');
  }
  return arguments[index + 1];
}
