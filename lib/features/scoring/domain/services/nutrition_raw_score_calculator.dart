import 'dart:math' as math;

import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/validated_nutrition_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_point_calculator.dart';

class NutritionRawScoreCalculator {
  final NutritionPointCalculator pointCalculator;

  const NutritionRawScoreCalculator({
    this.pointCalculator = const NutritionPointCalculator(),
  });

  NutritionRawScoreResult calculate(ValidatedNutritionScoringInput input) {
    if (input.isPlainWater) {
      return PlainWaterNutritionRawScoreResult();
    }

    return switch (input.category) {
      ScoringCategory.generalFood => _calculateGeneral(input),
      ScoringCategory.cheese => _calculateCheese(input),
      ScoringCategory.redMeat => _calculateRedMeat(input),
      ScoringCategory.fatsOilsNutsSeeds => _calculateFatCategory(input),
      ScoringCategory.beverage => _calculateBeverage(input),
      ScoringCategory.unknown || ScoringCategory.outOfScope => throw StateError(
        'Validated input cannot have ${input.category.name}',
      ),
    };
  }

  CalculatedNutritionRawScoreResult _calculateGeneral(
    ValidatedNutritionScoringInput input,
  ) {
    final negative = _generalNegative(input);
    final proteinCalculated = pointCalculator.generalProteinPoints(
      input.protein,
    );
    final proteinApplied = negative.total < 11 ? proteinCalculated : 0;
    return _result(
      category: input.category,
      negative: negative,
      proteinCalculated: proteinCalculated,
      proteinApplied: proteinApplied,
      fiberPoints: pointCalculator.fiberPoints(input.fiber),
      fvlPoints: pointCalculator.generalFvlPoints(input.fvlPercentage),
      specialRules: [
        if (proteinApplied != proteinCalculated)
          NutritionSpecialRule.generalProteinSuppressed,
      ],
    );
  }

  CalculatedNutritionRawScoreResult _calculateCheese(
    ValidatedNutritionScoringInput input,
  ) {
    final negative = _generalNegative(input);
    final protein = pointCalculator.generalProteinPoints(input.protein);
    return _result(
      category: input.category,
      negative: negative,
      proteinCalculated: protein,
      proteinApplied: protein,
      fiberPoints: pointCalculator.fiberPoints(input.fiber),
      fvlPoints: pointCalculator.generalFvlPoints(input.fvlPercentage),
      specialRules: [
        if (negative.total >= 11)
          NutritionSpecialRule.cheeseProteinAppliedAtHighNegativePoints,
      ],
    );
  }

  CalculatedNutritionRawScoreResult _calculateRedMeat(
    ValidatedNutritionScoringInput input,
  ) {
    final negative = _generalNegative(input);
    final proteinCalculated = pointCalculator.generalProteinPoints(
      input.protein,
    );
    final cappedProtein = math.min(proteinCalculated, 2);
    final proteinApplied = negative.total < 11 ? cappedProtein : 0;
    return _result(
      category: input.category,
      negative: negative,
      proteinCalculated: proteinCalculated,
      proteinApplied: proteinApplied,
      fiberPoints: pointCalculator.fiberPoints(input.fiber),
      fvlPoints: pointCalculator.generalFvlPoints(input.fvlPercentage),
      specialRules: [
        if (cappedProtein != proteinCalculated)
          NutritionSpecialRule.redMeatProteinCapped,
        if (negative.total >= 11) NutritionSpecialRule.redMeatProteinSuppressed,
      ],
    );
  }

  CalculatedNutritionRawScoreResult _calculateFatCategory(
    ValidatedNutritionScoringInput input,
  ) {
    final saturatedEnergyKj = input.saturatedFat * 37;
    final saturatedFatRatioPercent = 100 * input.saturatedFat / input.totalFat!;
    final negative = NutritionNegativePointBreakdown(
      sugarsPoints: pointCalculator.generalSugarPoints(input.sugars),
      saltPoints: pointCalculator.saltPoints(input.salt),
      saturatedEnergyPoints: pointCalculator.fatSaturatedEnergyPoints(
        saturatedEnergyKj,
      ),
      saturatedFatRatioPoints: pointCalculator.fatSaturatedRatioPoints(
        saturatedFatRatioPercent,
      ),
      saturatedEnergyKj: saturatedEnergyKj,
      saturatedFatRatioPercent: saturatedFatRatioPercent,
    );
    final proteinCalculated = pointCalculator.generalProteinPoints(
      input.protein,
    );
    final proteinApplied = negative.total < 7 ? proteinCalculated : 0;
    return _result(
      category: input.category,
      negative: negative,
      proteinCalculated: proteinCalculated,
      proteinApplied: proteinApplied,
      fiberPoints: pointCalculator.fiberPoints(input.fiber),
      fvlPoints: pointCalculator.generalFvlPoints(input.fvlPercentage),
      specialRules: [
        NutritionSpecialRule.fatSaturatedEnergyAndRatio,
        if (proteinApplied != proteinCalculated)
          NutritionSpecialRule.fatProteinSuppressed,
      ],
    );
  }

  CalculatedNutritionRawScoreResult _calculateBeverage(
    ValidatedNutritionScoringInput input,
  ) {
    final nnsPresent = input.nnsPresent!;
    final negative = NutritionNegativePointBreakdown(
      energyPoints: pointCalculator.beverageEnergyPoints(input.energyKj!),
      sugarsPoints: pointCalculator.beverageSugarPoints(input.sugars),
      saturatedFatPoints: pointCalculator.saturatedFatPoints(
        input.saturatedFat,
      ),
      saltPoints: pointCalculator.saltPoints(input.salt),
      nnsPoints: pointCalculator.beverageNnsPoints(nnsPresent),
    );
    final protein = pointCalculator.beverageProteinPoints(input.protein);
    return _result(
      category: input.category,
      negative: negative,
      proteinCalculated: protein,
      proteinApplied: protein,
      fiberPoints: pointCalculator.fiberPoints(input.fiber),
      fvlPoints: pointCalculator.beverageFvlPoints(input.fvlPercentage),
      specialRules: [if (nnsPresent) NutritionSpecialRule.beverageNnsApplied],
    );
  }

  NutritionNegativePointBreakdown _generalNegative(
    ValidatedNutritionScoringInput input,
  ) {
    return NutritionNegativePointBreakdown(
      energyPoints: pointCalculator.generalEnergyPoints(input.energyKj!),
      sugarsPoints: pointCalculator.generalSugarPoints(input.sugars),
      saturatedFatPoints: pointCalculator.saturatedFatPoints(
        input.saturatedFat,
      ),
      saltPoints: pointCalculator.saltPoints(input.salt),
    );
  }

  CalculatedNutritionRawScoreResult _result({
    required ScoringCategory category,
    required NutritionNegativePointBreakdown negative,
    required int proteinCalculated,
    required int proteinApplied,
    required int fiberPoints,
    required int fvlPoints,
    Iterable<NutritionSpecialRule> specialRules = const [],
  }) {
    final positive = NutritionPositivePointBreakdown(
      proteinPointsCalculated: proteinCalculated,
      proteinPointsApplied: proteinApplied,
      fiberPoints: fiberPoints,
      fvlPoints: fvlPoints,
    );
    return CalculatedNutritionRawScoreResult(
      resolvedCategory: category,
      negativePoints: negative,
      positivePoints: positive,
      rawScore: negative.total - positive.appliedTotal,
      specialRules: specialRules,
    );
  }
}
