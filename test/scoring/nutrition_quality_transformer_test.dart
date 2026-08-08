import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';

void main() {
  const transformer = NutritionQualityTransformer();

  CalculatedNutritionRawScoreResult raw(ScoringCategory category, int score) {
    return CalculatedNutritionRawScoreResult(
      resolvedCategory: category,
      negativePoints: const NutritionNegativePointBreakdown(),
      positivePoints: const NutritionPositivePointBreakdown(
        proteinPointsCalculated: 0,
        proteinPointsApplied: 0,
        fiberPoints: 0,
        fvlPoints: 0,
      ),
      rawScore: score,
    );
  }

  double quality(ScoringCategory category, int score) =>
      transformer.transform(raw(category, score)).qualityScore;

  void expectMonotonic(ScoringCategory category) {
    var previous = quality(category, -100);
    for (var score = -99; score <= 100; score += 1) {
      final current = quality(category, score);
      expect(
        current,
        lessThanOrEqualTo(previous),
        reason: '${category.name}: raw ${score - 1} -> $score',
      );
      previous = current;
    }
  }

  void expectSmoothTransition(
    ScoringCategory category,
    int betterRaw,
    int worseRaw,
  ) {
    final better = quality(category, betterRaw);
    final worse = quality(category, worseRaw);
    expect(better, greaterThan(worse));
    expect(
      better - worse,
      lessThan(10),
      reason: '${category.name}: raw $betterRaw/$worseRaw',
    );
  }

  test('result retains raw input, category, version, and double precision', () {
    final rawResult = raw(ScoringCategory.beverage, 3);
    final result = transformer.transform(rawResult);

    expect(result.rawResult, same(rawResult));
    expect(result.category, ScoringCategory.beverage);
    expect(result.transformVersion, nutritionQualityTransformVersion);
    expect(result.qualityScore, closeTo(66.875, 0.0000001));
    expect(result.specialCase, NutritionQualitySpecialCase.none);
  });

  test('score remains in 0..100 across wide supported raw ranges', () {
    for (final category in [
      ScoringCategory.generalFood,
      ScoringCategory.cheese,
      ScoringCategory.redMeat,
      ScoringCategory.fatsOilsNutsSeeds,
      ScoringCategory.beverage,
    ]) {
      for (var score = -100; score <= 100; score += 1) {
        expect(quality(category, score), inInclusiveRange(0, 100));
      }
    }
  });

  test('same raw result produces the same nutrition quality', () {
    final rawResult = raw(ScoringCategory.generalFood, 7);
    final first = transformer.transform(rawResult);
    final second = transformer.transform(rawResult);

    expect(second.qualityScore, first.qualityScore);
    expect(second.transformVersion, first.transformVersion);
    expect(second.specialCase, first.specialCase);
  });

  test('GENERAL is exhaustive monotonic', () {
    expectMonotonic(ScoringCategory.generalFood);
  });

  test('CHEESE is exhaustive monotonic', () {
    expectMonotonic(ScoringCategory.cheese);
  });

  test('RED_MEAT is exhaustive monotonic', () {
    expectMonotonic(ScoringCategory.redMeat);
  });

  test('FATS_OILS_NUTS_SEEDS is exhaustive monotonic', () {
    expectMonotonic(ScoringCategory.fatsOilsNutsSeeds);
  });

  test('BEVERAGE is exhaustive monotonic', () {
    expectMonotonic(ScoringCategory.beverage);
  });

  test('plain water maps directly to special maximum quality', () {
    final rawResult = PlainWaterNutritionRawScoreResult();
    final result = transformer.transform(rawResult);

    expect(result.qualityScore, 100);
    expect(result.rawResult, same(rawResult));
    expect(result.isPlainWaterSpecialCase, isTrue);
    expect(result.specialCase, NutritionQualitySpecialCase.plainWater);
  });

  test('GENERAL 0/1 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.generalFood, 0, 1);
  });

  test('GENERAL 2/3 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.generalFood, 2, 3);
  });

  test('GENERAL 10/11 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.generalFood, 10, 11);
  });

  test('GENERAL 18/19 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.generalFood, 18, 19);
  });

  test('FATS -6/-5 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.fatsOilsNutsSeeds, -6, -5);
  });

  test('FATS 2/3 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.fatsOilsNutsSeeds, 2, 3);
  });

  test('BEVERAGE 2/3 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.beverage, 2, 3);
  });

  test('BEVERAGE 6/7 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.beverage, 6, 7);
  });

  test('BEVERAGE 9/10 transition has no giant discontinuity', () {
    expectSmoothTransition(ScoringCategory.beverage, 9, 10);
  });

  test('extreme favorable raw values clamp safely by category', () {
    expect(quality(ScoringCategory.generalFood, -100), 100);
    expect(quality(ScoringCategory.cheese, -100), 100);
    expect(quality(ScoringCategory.redMeat, -100), 100);
    expect(quality(ScoringCategory.fatsOilsNutsSeeds, -100), 100);
    expect(quality(ScoringCategory.beverage, -100), 85);
  });

  test('extreme adverse raw values clamp safely to zero', () {
    for (final category in [
      ScoringCategory.generalFood,
      ScoringCategory.cheese,
      ScoringCategory.redMeat,
      ScoringCategory.fatsOilsNutsSeeds,
      ScoringCategory.beverage,
    ]) {
      expect(quality(category, 100), 0);
    }
  });

  test('unsupported calculated categories are rejected', () {
    for (final category in [
      ScoringCategory.unknown,
      ScoringCategory.outOfScope,
    ]) {
      expect(
        () => transformer.transform(raw(category, 0)),
        throwsArgumentError,
      );
    }
  });
}
