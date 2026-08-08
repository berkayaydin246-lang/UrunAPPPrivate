import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';

const etiketlyScoreVersion = 'etiketly_score_v1';

enum EtiketlyScoreStatus { calculated, notCalculable }

enum EtiketlyScoreExplanationCode {
  nutritionDominantFactor,
  additivesAffectedScore,
  noEligibleAdditivePenalty,
  beverageNnsHandledInNutrition,
  scoreUnavailableNutritionNotReady,
  scoreUnavailableIngredientEvidenceIncomplete,
  scoreUnavailableUnresolvedIngredientEvidence,
  scoreUnavailableReviewRequiredAdditiveEvidence,
  scoreUnavailableAdditiveRiskConflict,
  scoreUnavailableUnknownAdditiveRisk,
  scoreUnavailableAdditiveAssessmentIncomplete,
}

class EtiketlyScoreResult {
  EtiketlyScoreResult._({
    required this.status,
    required this.score,
    required this.nutritionQuality,
    required this.additiveQuality,
    required this.nutritionContribution,
    required this.additiveContribution,
    required this.readiness,
    required Iterable<EtiketlyScoreExplanationCode> explanationCodes,
  }) : assert(score == null || (score >= 0 && score <= 100)),
       assert(
         status == EtiketlyScoreStatus.calculated
             ? nutritionQuality != null &&
                   score != null &&
                   nutritionContribution != null &&
                   additiveContribution != null
             : score == null &&
                   nutritionContribution == null &&
                   additiveContribution == null,
       ),
       scoreVersion = etiketlyScoreVersion,
       nutritionMethodologyVersion =
           nutritionQuality?.rawResult.methodologyVersion,
       nutritionTransformVersion = nutritionQuality?.transformVersion,
       additiveTransformVersion = additiveQuality.transformVersion,
       explanationCodes = Set.unmodifiable(explanationCodes);

  factory EtiketlyScoreResult.calculated({
    required double score,
    required NutritionQualityResult nutritionQuality,
    required AdditiveQualityResult additiveQuality,
    required double nutritionContribution,
    required double additiveContribution,
    required EtiketlyScoreReadinessResult readiness,
    required Iterable<EtiketlyScoreExplanationCode> explanationCodes,
  }) {
    return EtiketlyScoreResult._(
      status: EtiketlyScoreStatus.calculated,
      score: score,
      nutritionQuality: nutritionQuality,
      additiveQuality: additiveQuality,
      nutritionContribution: nutritionContribution,
      additiveContribution: additiveContribution,
      readiness: readiness,
      explanationCodes: explanationCodes,
    );
  }

  factory EtiketlyScoreResult.notCalculable({
    NutritionQualityResult? nutritionQuality,
    required AdditiveQualityResult additiveQuality,
    required EtiketlyScoreReadinessResult readiness,
    required Iterable<EtiketlyScoreExplanationCode> explanationCodes,
  }) {
    return EtiketlyScoreResult._(
      status: EtiketlyScoreStatus.notCalculable,
      score: null,
      nutritionQuality: nutritionQuality,
      additiveQuality: additiveQuality,
      nutritionContribution: null,
      additiveContribution: null,
      readiness: readiness,
      explanationCodes: explanationCodes,
    );
  }

  final EtiketlyScoreStatus status;
  final double? score;
  final NutritionQualityResult? nutritionQuality;
  final AdditiveQualityResult additiveQuality;
  final double? nutritionContribution;
  final double? additiveContribution;
  final String scoreVersion;
  final String? nutritionMethodologyVersion;
  final String? nutritionTransformVersion;
  final String additiveTransformVersion;
  final EtiketlyScoreReadinessResult readiness;
  final Set<EtiketlyScoreExplanationCode> explanationCodes;

  bool get isCalculated => status == EtiketlyScoreStatus.calculated;
  int? get futureDisplayScore => score?.round();
}
