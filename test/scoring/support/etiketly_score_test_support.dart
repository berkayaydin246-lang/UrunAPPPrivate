import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/validated_nutrition_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_readiness_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_raw_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

import '../scoring_test_fixtures.dart';
import 'additive_quality_test_support.dart';

const etiketlyScoreCalculator = EtiketlyScoreCalculator();
const etiketlyScoreReadinessEvaluator = EtiketlyScoreReadinessEvaluator();
const scoringReadinessEvaluator = ScoringReadinessEvaluator();
const nutritionRawScoreCalculator = NutritionRawScoreCalculator();
const nutritionQualityTransformer = NutritionQualityTransformer();
const additiveQualityTransformer = AdditiveQualityTransformer();

class EtiketlyScorePipelineResult {
  const EtiketlyScorePipelineResult({
    required this.nutritionQuality,
    required this.additiveQuality,
    required this.readiness,
    required this.scoreResult,
  });

  final NutritionQualityResult nutritionQuality;
  final AdditiveQualityResult additiveQuality;
  final EtiketlyScoreReadinessResult readiness;
  final EtiketlyScoreResult scoreResult;
}

EtiketlyScorePipelineResult runEtiketlyScorePipeline(
  EtiketlyScoringInput input, {
  Iterable<String> additiveCodes = const [],
}) {
  final nutritionReadiness = scoringReadinessEvaluator.evaluate(input);
  final validated = ValidatedNutritionScoringInput.validate(input);
  final raw = nutritionRawScoreCalculator.calculate(validated);
  final nutritionQuality = nutritionQualityTransformer.transform(raw);
  final additiveQuality = additiveQualityTransformer.transform(
    assessmentForCodes(additiveCodes, category: validated.category),
  );
  final readiness = etiketlyScoreReadinessEvaluator.evaluate(
    nutritionReadiness: nutritionReadiness,
    ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness,
    additiveQuality: additiveQuality,
  );
  final scoreResult = etiketlyScoreCalculator.calculate(
    nutritionQuality: nutritionQuality,
    additiveQuality: additiveQuality,
    readiness: readiness,
  );
  return EtiketlyScorePipelineResult(
    nutritionQuality: nutritionQuality,
    additiveQuality: additiveQuality,
    readiness: readiness,
    scoreResult: scoreResult,
  );
}

NutritionQualityResult syntheticNutritionQuality(
  double quality, {
  ScoringCategory category = ScoringCategory.generalFood,
}) {
  return NutritionQualityResult(
    qualityScore: quality,
    rawResult: CalculatedNutritionRawScoreResult(
      resolvedCategory: category,
      negativePoints: const NutritionNegativePointBreakdown(),
      positivePoints: const NutritionPositivePointBreakdown(
        proteinPointsCalculated: 0,
        proteinPointsApplied: 0,
        fiberPoints: 0,
        fvlPoints: 0,
      ),
      rawScore: 0,
    ),
    specialCase: NutritionQualitySpecialCase.none,
  );
}

AdditiveQualityResult syntheticAdditiveQuality(double quality) {
  final assessment = assessmentForCodes(const []);
  return AdditiveQualityResult(
    qualityScore: quality,
    unclampedQualityScore: quality,
    totalPenalty: 100 - quality,
    canonicalAssessment: assessment,
    eligibleUniqueAdditiveCount: 0,
    lowCount: 0,
    mediumCount: 0,
    highCount: 0,
    penalizedLowCount: 0,
    penalizedMediumCount: 0,
    penalizedHighCount: 0,
    unknownOrIneligibleCount: 0,
    ordinaryIngredientCount: 0,
    contributions: const [],
    overlapExclusions: const [],
  );
}

ScoringReadinessResult readyNutritionReadiness({
  ScoringCategory category = ScoringCategory.generalFood,
}) {
  return ScoringReadinessResult(
    isScorable: true,
    resolvedCategory: category,
    evidenceQuality: ScoringEvidenceQuality.high,
  );
}

EtiketlyScoreReadinessResult readyFinalReadiness(
  AdditiveQualityResult additiveQuality, {
  ScoringCategory category = ScoringCategory.generalFood,
}) {
  return etiketlyScoreReadinessEvaluator.evaluate(
    nutritionReadiness: readyNutritionReadiness(category: category),
    ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.complete,
    additiveQuality: additiveQuality,
  );
}

EtiketlyScoreResult calculateSyntheticScore({
  required double nutritionQuality,
  required double additiveQuality,
}) {
  final additiveResult = syntheticAdditiveQuality(additiveQuality);
  return etiketlyScoreCalculator.calculate(
    nutritionQuality: syntheticNutritionQuality(nutritionQuality),
    additiveQuality: additiveResult,
    readiness: readyFinalReadiness(additiveResult),
  );
}

EtiketlyScoringInput nutritionFixtureInput({
  required ScoringCategory category,
  double energyKj = 0,
  double totalFat = 100,
  double saturatedFat = 0,
  double sugars = 0,
  double salt = 0,
  double protein = 0,
  double fiber = 0,
  double fvl = 0,
  bool nnsPresent = false,
  bool plainWater = false,
}) {
  return completeInput(
    category: category,
    nutrition: completeNutrition(
      energyKj: verifiedValue(energyKj),
      totalFat: verifiedValue(totalFat),
      saturatedFat: verifiedValue(saturatedFat),
      sugars: verifiedValue(sugars),
      salt: verifiedValue(salt),
      protein: verifiedValue(protein),
      fiber: verifiedValue(fiber),
    ),
    fvlEvidence: CompositionPercentageEvidence.known(
      fvl,
      provenance: EvidenceProvenance.adminVerified,
      verification: EvidenceVerification.verified,
    ),
    nnsEvidence: nnsPresent
        ? const PresenceEvidence.present(
            provenance: EvidenceProvenance.adminVerified,
            verification: EvidenceVerification.verified,
          )
        : const PresenceEvidence.absent(
            provenance: EvidenceProvenance.adminVerified,
            verification: EvidenceVerification.verified,
          ),
    classificationFacts: ScoringClassificationFacts(
      isPlainWater: plainWater ? verifiedValue(true) : null,
    ),
  );
}
