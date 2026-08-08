import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class EtiketlyScoreReadinessEvaluator {
  const EtiketlyScoreReadinessEvaluator();

  EtiketlyScoreReadinessResult evaluate({
    required ScoringReadinessResult nutritionReadiness,
    required IngredientEvidenceCompleteness ingredientEvidenceCompleteness,
    required AdditiveQualityResult additiveQuality,
  }) {
    final blockers = <EtiketlyScoreReadinessBlocker>{};
    final assessment = additiveQuality.canonicalAssessment;
    final canonicalAdditives = assessment.canonicalAdditives;

    if (!nutritionReadiness.isScorable) {
      blockers.add(EtiketlyScoreReadinessBlocker.nutritionNotReady);
    }
    if (ingredientEvidenceCompleteness !=
        IngredientEvidenceCompleteness.complete) {
      blockers.add(EtiketlyScoreReadinessBlocker.ingredientEvidenceIncomplete);
    }
    if (assessment.unresolvedIngredients.isNotEmpty) {
      blockers.add(EtiketlyScoreReadinessBlocker.unresolvedIngredientEvidence);
    }
    if (canonicalAdditives.any(
      (item) => item.matchAuthority == CanonicalMatchAuthority.reviewRequired,
    )) {
      blockers.add(
        EtiketlyScoreReadinessBlocker.reviewRequiredAdditiveEvidence,
      );
    }
    if (canonicalAdditives.any((item) => item.conflicts.isNotEmpty)) {
      blockers.add(EtiketlyScoreReadinessBlocker.additiveRiskConflict);
    }
    if (canonicalAdditives.any(
      (item) => item.riskLevel == CanonicalRiskLevel.unknown,
    )) {
      blockers.add(EtiketlyScoreReadinessBlocker.unknownAdditiveRisk);
    }
    if (canonicalAdditives.any(
      (item) => !item.eligibleForFutureAdditiveScore,
    )) {
      blockers.add(EtiketlyScoreReadinessBlocker.additiveAssessmentIncomplete);
    }

    return EtiketlyScoreReadinessResult(
      nutritionReadiness: nutritionReadiness,
      ingredientEvidenceCompleteness: ingredientEvidenceCompleteness,
      additiveQuality: additiveQuality,
      blockingReasons: blockers,
    );
  }
}
