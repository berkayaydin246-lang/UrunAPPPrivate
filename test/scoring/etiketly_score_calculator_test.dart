import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_readiness_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

import 'scoring_test_fixtures.dart';
import 'support/additive_quality_test_support.dart';
import 'support/etiketly_score_test_support.dart';

void main() {
  group('strict final-score readiness', () {
    test('fully ready component evidence calculates a final score', () {
      final result = runEtiketlyScorePipeline(completeInput());

      expect(result.readiness.isCalculable, isTrue);
      expect(result.scoreResult.status, EtiketlyScoreStatus.calculated);
      expect(result.scoreResult.score, isNotNull);
    });

    test('nutrition not ready returns no final score', () {
      final nutritionReadiness = const ScoringReadinessEvaluator().evaluate(
        completeInput(nutrition: completeNutrition(includeEnergyKj: false)),
      );
      final additive = const AdditiveQualityTransformer().transform(
        assessmentForCodes(const []),
      );
      final readiness = const EtiketlyScoreReadinessEvaluator().evaluate(
        nutritionReadiness: nutritionReadiness,
        ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.complete,
        additiveQuality: additive,
      );
      final result = const EtiketlyScoreCalculator().calculate(
        additiveQuality: additive,
        readiness: readiness,
      );

      expect(readiness.isCalculable, isFalse);
      expect(
        readiness.blockingReasons,
        contains(EtiketlyScoreReadinessBlocker.nutritionNotReady),
      );
      expect(result.status, EtiketlyScoreStatus.notCalculable);
      expect(result.score, isNull);
      expect(result.nutritionQuality, isNull);
      expect(result.nutritionMethodologyVersion, isNull);
      expect(result.nutritionTransformVersion, isNull);
      expect(result.nutritionContribution, isNull);
      expect(result.additiveContribution, isNull);
    });

    test('incomplete ingredient evidence blocks otherwise ready inputs', () {
      final additive = const AdditiveQualityTransformer().transform(
        assessmentForCodes(const []),
      );
      final readiness = const EtiketlyScoreReadinessEvaluator().evaluate(
        nutritionReadiness: readyNutritionReadiness(),
        ingredientEvidenceCompleteness:
            IngredientEvidenceCompleteness.incomplete,
        additiveQuality: additive,
      );

      expect(readiness.isCalculable, isFalse);
      expect(
        readiness.blockingReasons,
        contains(EtiketlyScoreReadinessBlocker.ingredientEvidenceIncomplete),
      );
    });

    test('unresolved ingredient evidence blocks conservatively', () {
      final additive = const AdditiveQualityTransformer().transform(
        unresolvedAssessment(),
      );
      final readiness = readyFinalReadiness(additive);

      expect(readiness.isCalculable, isFalse);
      expect(readiness.unresolvedIngredientCount, 1);
      expect(
        readiness.blockingReasons,
        contains(EtiketlyScoreReadinessBlocker.unresolvedIngredientEvidence),
      );
    });

    test('review-required additive evidence blocks', () {
      final additive = const AdditiveQualityTransformer().transform(
        fuzzyAssessment('E202'),
      );
      final readiness = readyFinalReadiness(additive);

      expect(readiness.isCalculable, isFalse);
      expect(readiness.reviewRequiredAdditiveCount, 1);
      expect(
        readiness.blockingReasons,
        contains(EtiketlyScoreReadinessBlocker.reviewRequiredAdditiveEvidence),
      );
      expect(
        readiness.blockingReasons,
        contains(EtiketlyScoreReadinessBlocker.additiveAssessmentIncomplete),
      );
    });

    test('canonical additive risk conflict blocks', () {
      final additive = const AdditiveQualityTransformer().transform(
        conflictingAssessment(),
      );
      final readiness = readyFinalReadiness(additive);

      expect(readiness.isCalculable, isFalse);
      expect(readiness.additiveRiskConflictCount, greaterThan(0));
      expect(
        readiness.blockingReasons,
        contains(EtiketlyScoreReadinessBlocker.additiveRiskConflict),
      );
    });

    test('unknown-risk canonical additive blocks', () {
      final additive = const AdditiveQualityTransformer().transform(
        assessmentForCodes(const ['E249']),
      );
      final readiness = readyFinalReadiness(additive);

      expect(readiness.isCalculable, isFalse);
      expect(readiness.unknownAdditiveRiskCount, 1);
      expect(
        readiness.blockingReasons,
        contains(EtiketlyScoreReadinessBlocker.unknownAdditiveRisk),
      );
    });

    test('recognized ordinary food ingredient does not block', () {
      final additive = const AdditiveQualityTransformer().transform(
        ordinaryAssessment(),
      );
      final readiness = readyFinalReadiness(additive);
      final result = const EtiketlyScoreCalculator().calculate(
        nutritionQuality: syntheticNutritionQuality(80),
        additiveQuality: additive,
        readiness: readiness,
      );

      expect(additive.ordinaryIngredientCount, 1);
      expect(readiness.isCalculable, isTrue);
      expect(result.isCalculated, isTrue);
    });

    test('legacy unsupported evidence remains without a final score', () {
      final legacyReadiness = const ScoringReadinessEvaluator().evaluate(
        completeInput(
          basis: NutritionBasis.unknown,
          productState: NutritionProductState.unknown,
          ingredientCompleteness: IngredientEvidenceCompleteness.unknown,
        ),
      );
      final additive = const AdditiveQualityTransformer().transform(
        assessmentForCodes(const []),
      );
      final readiness = const EtiketlyScoreReadinessEvaluator().evaluate(
        nutritionReadiness: legacyReadiness,
        ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.unknown,
        additiveQuality: additive,
      );
      final result = const EtiketlyScoreCalculator().calculate(
        nutritionQuality: syntheticNutritionQuality(80),
        additiveQuality: additive,
        readiness: readiness,
      );

      expect(result.status, EtiketlyScoreStatus.notCalculable);
      expect(result.score, isNull);
      expect(
        readiness.blockingReasons,
        containsAll([
          EtiketlyScoreReadinessBlocker.nutritionNotReady,
          EtiketlyScoreReadinessBlocker.ingredientEvidenceIncomplete,
        ]),
      );
    });

    test('complete evidence with zero eligible additives can score', () {
      final result = runEtiketlyScorePipeline(completeInput());

      expect(result.additiveQuality.eligibleUniqueAdditiveCount, 0);
      expect(result.additiveQuality.qualityScore, 100);
      expect(result.scoreResult.isCalculated, isTrue);
      expect(
        result.scoreResult.explanationCodes,
        contains(EtiketlyScoreExplanationCode.noEligibleAdditivePenalty),
      );
    });
  });

  group('v1 final-score mathematics', () {
    test('uses the documented 80/20 arithmetic formula exactly once', () {
      final result = calculateSyntheticScore(
        nutritionQuality: 90,
        additiveQuality: 76,
      );

      expect(EtiketlyScoreCalculator.nutritionWeight, 0.80);
      expect(EtiketlyScoreCalculator.additiveWeight, 0.20);
      expect(result.nutritionContribution, 72);
      expect(result.additiveContribution, closeTo(15.2, 0.0000001));
      expect(result.score, closeTo(87.2, 0.0000001));
    });

    test('same component inputs always produce the same result', () {
      final first = calculateSyntheticScore(
        nutritionQuality: 66.875,
        additiveQuality: 79.1875,
      );
      final second = calculateSyntheticScore(
        nutritionQuality: 66.875,
        additiveQuality: 79.1875,
      );

      expect(second.score, first.score);
      expect(second.nutritionContribution, first.nutritionContribution);
      expect(second.additiveContribution, first.additiveContribution);
    });

    test(
      'representative grid always remains within zero through one hundred',
      () {
        for (var nutrition = 0; nutrition <= 100; nutrition += 5) {
          for (var additives = 0; additives <= 100; additives += 5) {
            final score = calculateSyntheticScore(
              nutritionQuality: nutrition.toDouble(),
              additiveQuality: additives.toDouble(),
            ).score!;
            expect(score, inInclusiveRange(0, 100));
            expect(score.isFinite, isTrue);
          }
        }
      },
    );

    test(
      'nutrition direction is exhaustive monotonic on representative rows',
      () {
        for (var additives = 0; additives <= 100; additives += 5) {
          var previous = calculateSyntheticScore(
            nutritionQuality: 0,
            additiveQuality: additives.toDouble(),
          ).score!;
          for (var nutrition = 1; nutrition <= 100; nutrition += 1) {
            final current = calculateSyntheticScore(
              nutritionQuality: nutrition.toDouble(),
              additiveQuality: additives.toDouble(),
            ).score!;
            expect(current, greaterThanOrEqualTo(previous));
            previous = current;
          }
        }
      },
    );

    test(
      'additive direction is exhaustive monotonic on representative rows',
      () {
        for (var nutrition = 0; nutrition <= 100; nutrition += 5) {
          var previous = calculateSyntheticScore(
            nutritionQuality: nutrition.toDouble(),
            additiveQuality: 0,
          ).score!;
          for (var additives = 1; additives <= 100; additives += 1) {
            final current = calculateSyntheticScore(
              nutritionQuality: nutrition.toDouble(),
              additiveQuality: additives.toDouble(),
            ).score!;
            expect(current, greaterThanOrEqualTo(previous));
            previous = current;
          }
        }
      },
    );

    test('explicit extreme cases retain continuous weighted behavior', () {
      expect(
        calculateSyntheticScore(
          nutritionQuality: 100,
          additiveQuality: 100,
        ).score,
        100,
      );
      expect(
        calculateSyntheticScore(
          nutritionQuality: 100,
          additiveQuality: 0,
        ).score,
        80,
      );
      expect(
        calculateSyntheticScore(
          nutritionQuality: 0,
          additiveQuality: 100,
        ).score,
        20,
      );
      expect(
        calculateSyntheticScore(nutritionQuality: 0, additiveQuality: 0).score,
        0,
      );
      expect(
        calculateSyntheticScore(
          nutritionQuality: 90,
          additiveQuality: 58,
        ).score,
        closeTo(83.6, 0.0000001),
      );
      expect(
        calculateSyntheticScore(
          nutritionQuality: 30,
          additiveQuality: 100,
        ).score,
        44,
      );
      expect(
        calculateSyntheticScore(
          nutritionQuality: 30,
          additiveQuality: 30,
        ).score,
        30,
      );
    });

    test('does not round either component before combination', () {
      final result = calculateSyntheticScore(
        nutritionQuality: 75.296875,
        additiveQuality: 91,
      );

      expect(result.score, closeTo(78.4375, 0.0000001));
      expect(result.futureDisplayScore, 78);
    });

    test('future display rounding uses deterministic nearest integer', () {
      expect(
        calculateSyntheticScore(
          nutritionQuality: 75.375,
          additiveQuality: 91,
        ).futureDisplayScore,
        79,
      );
      expect(
        calculateSyntheticScore(
          nutritionQuality: 75.25,
          additiveQuality: 91,
        ).futureDisplayScore,
        78,
      );
    });

    test('result retains all independent methodology versions', () {
      final result = calculateSyntheticScore(
        nutritionQuality: 80,
        additiveQuality: 90,
      );

      expect(result.scoreVersion, etiketlyScoreVersion);
      expect(
        result.nutritionMethodologyVersion,
        nutritionRawMethodologyVersion,
      );
      expect(
        result.nutritionTransformVersion,
        nutritionQualityTransformVersion,
      );
      expect(result.additiveTransformVersion, additiveQualityTransformVersion);
    });

    test('readiness must be derived from the supplied additive result', () {
      final supplied = syntheticAdditiveQuality(90);
      final other = syntheticAdditiveQuality(90);

      expect(
        () => const EtiketlyScoreCalculator().calculate(
          nutritionQuality: syntheticNutritionQuality(80),
          additiveQuality: supplied,
          readiness: readyFinalReadiness(other),
        ),
        throwsArgumentError,
      );
    });

    test('calculated readiness requires a nutrition quality result', () {
      final additive = syntheticAdditiveQuality(100);

      expect(
        () => const EtiketlyScoreCalculator().calculate(
          additiveQuality: additive,
          readiness: readyFinalReadiness(additive),
        ),
        throwsArgumentError,
      );
    });
  });

  group('deterministic explanation metadata', () {
    test('eligible additive penalty is machine-readable', () {
      final additive = const AdditiveQualityTransformer().transform(
        assessmentForCodes(const ['E211']),
      );
      final result = const EtiketlyScoreCalculator().calculate(
        nutritionQuality: syntheticNutritionQuality(80),
        additiveQuality: additive,
        readiness: readyFinalReadiness(additive),
      );

      expect(
        result.explanationCodes,
        contains(EtiketlyScoreExplanationCode.additivesAffectedScore),
      );
      expect(
        result.explanationCodes,
        contains(EtiketlyScoreExplanationCode.nutritionDominantFactor),
      );
    });

    test('beverage NNS is represented once through nutrition methodology', () {
      final additive = const AdditiveQualityTransformer().transform(
        assessmentForCodes(const ['E955'], category: ScoringCategory.beverage),
      );
      final result = const EtiketlyScoreCalculator().calculate(
        nutritionQuality: syntheticNutritionQuality(
          70,
          category: ScoringCategory.beverage,
        ),
        additiveQuality: additive,
        readiness: readyFinalReadiness(
          additive,
          category: ScoringCategory.beverage,
        ),
      );

      expect(additive.qualityScore, 100);
      expect(additive.excludedForNutritionOverlapCount, 1);
      expect(result.score, 76);
      expect(
        result.explanationCodes,
        contains(EtiketlyScoreExplanationCode.beverageNnsHandledInNutrition),
      );
      expect(
        result.explanationCodes,
        contains(EtiketlyScoreExplanationCode.noEligibleAdditivePenalty),
      );
    });

    test('unavailable explanations mirror typed blocker reasons', () {
      final additive = const AdditiveQualityTransformer().transform(
        assessmentForCodes(const ['E249']),
      );
      final readiness = readyFinalReadiness(additive);
      final result = const EtiketlyScoreCalculator().calculate(
        nutritionQuality: syntheticNutritionQuality(80),
        additiveQuality: additive,
        readiness: readiness,
      );

      expect(
        result.explanationCodes,
        contains(
          EtiketlyScoreExplanationCode.scoreUnavailableUnknownAdditiveRisk,
        ),
      );
      expect(result.score, isNull);
    });
  });
}
