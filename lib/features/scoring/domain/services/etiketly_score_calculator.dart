import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';

class EtiketlyScoreCalculator {
  const EtiketlyScoreCalculator();

  static const double nutritionWeight = 0.80;
  static const double additiveWeight = 0.20;

  EtiketlyScoreResult calculate({
    NutritionQualityResult? nutritionQuality,
    required AdditiveQualityResult additiveQuality,
    required EtiketlyScoreReadinessResult readiness,
  }) {
    if (!identical(readiness.additiveQuality, additiveQuality)) {
      throw ArgumentError(
        'readiness must be evaluated from the supplied additiveQuality',
      );
    }

    final explanations = _explanations(readiness, additiveQuality);
    if (!readiness.isCalculable) {
      return EtiketlyScoreResult.notCalculable(
        nutritionQuality: nutritionQuality,
        additiveQuality: additiveQuality,
        readiness: readiness,
        explanationCodes: explanations,
      );
    }
    if (nutritionQuality == null) {
      throw ArgumentError(
        'nutritionQuality is required when final-score readiness is calculable',
      );
    }
    if (readiness.nutritionReadiness.resolvedCategory !=
        nutritionQuality.category) {
      throw ArgumentError(
        'nutritionQuality category must match final-score readiness',
      );
    }

    final nutritionContribution =
        nutritionQuality.qualityScore * nutritionWeight;
    final additiveContribution = additiveQuality.qualityScore * additiveWeight;
    final score = nutritionContribution + additiveContribution;

    return EtiketlyScoreResult.calculated(
      score: score,
      nutritionQuality: nutritionQuality,
      additiveQuality: additiveQuality,
      nutritionContribution: nutritionContribution,
      additiveContribution: additiveContribution,
      readiness: readiness,
      explanationCodes: explanations,
    );
  }

  Set<EtiketlyScoreExplanationCode> _explanations(
    EtiketlyScoreReadinessResult readiness,
    AdditiveQualityResult additiveQuality,
  ) {
    final explanations = <EtiketlyScoreExplanationCode>{};
    if (readiness.isCalculable) {
      explanations.add(EtiketlyScoreExplanationCode.nutritionDominantFactor);
      if (additiveQuality.totalPenalty > 0) {
        explanations.add(EtiketlyScoreExplanationCode.additivesAffectedScore);
      } else {
        explanations.add(
          EtiketlyScoreExplanationCode.noEligibleAdditivePenalty,
        );
      }
      if (additiveQuality.excludedForNutritionOverlapCount > 0) {
        explanations.add(
          EtiketlyScoreExplanationCode.beverageNnsHandledInNutrition,
        );
      }
      return explanations;
    }

    for (final blocker in readiness.blockingReasons) {
      explanations.add(switch (blocker) {
        EtiketlyScoreReadinessBlocker.nutritionNotReady =>
          EtiketlyScoreExplanationCode.scoreUnavailableNutritionNotReady,
        EtiketlyScoreReadinessBlocker.ingredientEvidenceIncomplete =>
          EtiketlyScoreExplanationCode
              .scoreUnavailableIngredientEvidenceIncomplete,
        EtiketlyScoreReadinessBlocker.unresolvedIngredientEvidence =>
          EtiketlyScoreExplanationCode
              .scoreUnavailableUnresolvedIngredientEvidence,
        EtiketlyScoreReadinessBlocker.reviewRequiredAdditiveEvidence =>
          EtiketlyScoreExplanationCode
              .scoreUnavailableReviewRequiredAdditiveEvidence,
        EtiketlyScoreReadinessBlocker.additiveRiskConflict =>
          EtiketlyScoreExplanationCode.scoreUnavailableAdditiveRiskConflict,
        EtiketlyScoreReadinessBlocker.unknownAdditiveRisk =>
          EtiketlyScoreExplanationCode.scoreUnavailableUnknownAdditiveRisk,
        EtiketlyScoreReadinessBlocker.additiveAssessmentIncomplete =>
          EtiketlyScoreExplanationCode
              .scoreUnavailableAdditiveAssessmentIncomplete,
      });
    }
    return explanations;
  }
}
