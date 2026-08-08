import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

enum EtiketlyScoreReadinessBlocker {
  nutritionNotReady,
  ingredientEvidenceIncomplete,
  unresolvedIngredientEvidence,
  reviewRequiredAdditiveEvidence,
  additiveRiskConflict,
  unknownAdditiveRisk,
  additiveAssessmentIncomplete,
}

class EtiketlyScoreReadinessResult {
  EtiketlyScoreReadinessResult({
    required this.nutritionReadiness,
    required this.ingredientEvidenceCompleteness,
    required this.additiveQuality,
    required Iterable<EtiketlyScoreReadinessBlocker> blockingReasons,
  }) : blockingReasons = Set.unmodifiable(blockingReasons);

  final ScoringReadinessResult nutritionReadiness;
  final IngredientEvidenceCompleteness ingredientEvidenceCompleteness;
  final AdditiveQualityResult additiveQuality;
  final Set<EtiketlyScoreReadinessBlocker> blockingReasons;

  bool get isCalculable => blockingReasons.isEmpty;
  bool get isEligible => isCalculable;

  int get unresolvedIngredientCount =>
      additiveQuality.canonicalAssessment.unresolvedIngredients.length;

  int get reviewRequiredAdditiveCount => additiveQuality
      .canonicalAssessment
      .canonicalAdditives
      .where(
        (item) => item.matchAuthority == CanonicalMatchAuthority.reviewRequired,
      )
      .length;

  int get additiveRiskConflictCount => additiveQuality
      .canonicalAssessment
      .canonicalAdditives
      .expand((item) => item.conflicts)
      .length;

  int get unknownAdditiveRiskCount => additiveQuality
      .canonicalAssessment
      .canonicalAdditives
      .where((item) => item.riskLevel == CanonicalRiskLevel.unknown)
      .length;
}
