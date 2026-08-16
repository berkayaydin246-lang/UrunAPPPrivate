import 'dart:math' as math;

import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_evaluation.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/score_audit_fingerprint.dart';

class EtiketlyScoreAuditSnapshotBuilder {
  const EtiketlyScoreAuditSnapshotBuilder();

  EtiketlyScoreAuditSnapshot build({
    required Product product,
    required ProductEtiketlyScoreEvaluation evaluation,
  }) {
    final result = evaluation.result;
    final rawNutrition = evaluation.rawNutrition;
    final nutritionQuality = evaluation.nutritionQuality;
    if (!result.isCalculated ||
        rawNutrition == null ||
        nutritionQuality == null ||
        result.score == null ||
        result.nutritionContribution == null ||
        result.additiveContribution == null ||
        result.nutritionMethodologyVersion == null ||
        result.nutritionTransformVersion == null) {
      throw StateError('A score audit snapshot requires a calculated score.');
    }

    final additiveQuality = evaluation.additiveQuality;
    final itemPenalties = _itemPenalties(additiveQuality);
    final snapshot = EtiketlyScoreAuditSnapshot(
      productId: product.id,
      barcode: _clean(product.barcode),
      productUpdatedAt: product.updatedAt.toUtc(),
      productVerificationStatus: product.verificationStatus,
      ingredientText: product.ingredientsText?.trim() ?? '',
      sourceEvidenceSchemaVersion: product.scoringEvidence?.schemaVersion,
      inputFingerprint: '',
      scoreVersion: result.scoreVersion,
      nutritionMethodologyVersion: result.nutritionMethodologyVersion!,
      nutritionTransformVersion: result.nutritionTransformVersion!,
      additiveTransformVersion: result.additiveTransformVersion,
      resolvedInput: _resolvedInput(
        evaluation.input,
        product.scoringEvidence?.nutritionBasisEvidence?.provenance,
      ),
      canonicalAdditives: additiveQuality.canonicalAssessment.canonicalAdditives
          .map((item) => _canonicalAdditive(item, itemPenalties[item]))
          .toList(growable: false),
      nutritionResult: _nutritionResult(
        rawNutrition,
        nutritionQuality.qualityScore,
      ),
      additiveResult: _additiveResult(additiveQuality),
      nutritionContribution: result.nutritionContribution!,
      additiveContribution: result.additiveContribution!,
      finalScore: result.score!,
    );
    return snapshot.withInputFingerprint(
      ScoreAuditFingerprint.create(snapshot.fingerprintPayload()),
    );
  }

  ScoreAuditResolvedInputSnapshot _resolvedInput(
    EtiketlyScoringInput input,
    EvidenceProvenance? nutritionBasisProvenance,
  ) {
    final nutrition = input.nutrition;
    return ScoreAuditResolvedInputSnapshot(
      nutrition: {
        'energy_kj': _evidence(nutrition.energyKj),
        'energy_kcal': _evidence(nutrition.energyKcal),
        'total_fat': _evidence(nutrition.totalFat),
        'saturated_fat': _evidence(nutrition.saturatedFat),
        'sugars': _evidence(nutrition.sugars),
        'protein': _evidence(nutrition.protein),
        'fiber': _evidence(nutrition.fiber),
        'salt': _evidence(nutrition.salt),
        'sodium': _evidence(nutrition.sodium),
      },
      nutritionBasis: input.nutritionBasis.name,
      nutritionBasisProvenance: nutritionBasisProvenance?.name,
      productState: input.productState.name,
      resolvedCategory: input.categoryEvidence.resolvedCategory.name,
      categorySource: input.categoryEvidence.source.name,
      categoryEvidenceValues: [...input.categoryEvidence.evidenceValues]
        ..sort(),
      categoryReasons:
          input.categoryEvidence.reasons.map((reason) => reason.name).toList()
            ..sort(),
      fvlEvidence: ScoreAuditCompositionSnapshot(
        state: input.fvlEvidence.state.name,
        percentage: input.fvlEvidence.percentage,
        provenance: input.fvlEvidence.provenance.name,
        verification: input.fvlEvidence.verification.name,
        dependency: input.fvlEvidence.dependency.name,
      ),
      nnsEvidence: ScoreAuditPresenceSnapshot(
        state: input.nnsEvidence.state.name,
        provenance: input.nnsEvidence.provenance.name,
        verification: input.nnsEvidence.verification.name,
        dependency: input.nnsEvidence.dependency.name,
      ),
      ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness.name,
      classificationFacts: _classificationFacts(input.classificationFacts),
    );
  }

  Map<String, ScoreAuditEvidenceValueSnapshot?> _classificationFacts(
    ScoringClassificationFacts facts,
  ) {
    return {
      'is_plain_water': _optionalEvidence(facts.isPlainWater),
      'red_meat_percentage': _optionalEvidence(facts.redMeatPercentage),
      'red_meat_is_primary_ingredient': _optionalEvidence(
        facts.redMeatIsPrimaryIngredient,
      ),
      'nut_seed_percentage': _optionalEvidence(facts.nutSeedPercentage),
      'is_plant_based_cheese_alternative': _optionalEvidence(
        facts.isPlantBasedCheeseAlternative,
      ),
      'is_compound_product': _optionalEvidence(facts.isCompoundProduct),
      'is_drinkable_dairy': _optionalEvidence(facts.isDrinkableDairy),
      'is_beverage': _optionalEvidence(facts.isBeverage),
      'is_food_supplement': _optionalEvidence(facts.isFoodSupplement),
      'is_infant_food': _optionalEvidence(facts.isInfantFood),
      'is_medical_food': _optionalEvidence(facts.isMedicalFood),
      'is_sports_nutrition': _optionalEvidence(facts.isSportsNutrition),
      'is_meal_replacement': _optionalEvidence(facts.isMealReplacement),
    };
  }

  ScoreAuditEvidenceValueSnapshot _evidence(EvidenceValue<Object?> value) {
    return ScoreAuditEvidenceValueSnapshot(
      value: value.value,
      provenance: value.provenance.name,
      verification: value.verification.name,
    );
  }

  ScoreAuditEvidenceValueSnapshot? _optionalEvidence(
    EvidenceValue<Object?>? value,
  ) => value == null ? null : _evidence(value);

  Map<CanonicalIngredientAssessment, double> _itemPenalties(
    AdditiveQualityResult result,
  ) {
    final penalties = <CanonicalIngredientAssessment, double>{};
    for (final tier in result.contributions) {
      final items = result.canonicalAssessment.canonicalAdditives.where(
        (item) =>
            item.eligibleForFutureAdditiveScore &&
            item.riskLevel == tier.riskLevel &&
            item.nutritionMethodologyOverlap ==
                NutritionMethodologyOverlap.none,
      );
      var index = 0;
      for (final item in items) {
        penalties[item] =
            tier.firstItemImpact * math.pow(tier.additionalItemDecay, index);
        index += 1;
      }
    }
    return penalties;
  }

  ScoreAuditCanonicalAdditiveSnapshot _canonicalAdditive(
    CanonicalIngredientAssessment item,
    double? penalty,
  ) {
    final exclusionReason = switch ((item, penalty)) {
      (
        CanonicalIngredientAssessment(
          nutritionMethodologyOverlap: NutritionMethodologyOverlap
              .beverageNnsAlreadyRepresented,
        ),
        _,
      ) =>
        'beverageNnsAlreadyRepresented',
      (
        CanonicalIngredientAssessment(eligibleForFutureAdditiveScore: false),
        _,
      ) =>
        'notEligibleForAdditiveQuality',
      (
        CanonicalIngredientAssessment(riskLevel: CanonicalRiskLevel.unknown),
        _,
      ) =>
        'unknownRisk',
      (_, null) => 'notPenalized',
      _ => null,
    };
    return ScoreAuditCanonicalAdditiveSnapshot(
      ingredientId: _clean(item.ingredientId),
      canonicalKey: item.canonicalKey,
      canonicalName: item.canonicalName,
      eCode: _clean(item.eCode),
      additiveGroup: _clean(item.additiveGroup),
      riskLevelAtCalculationTime: item.riskLevel.name,
      riskSource: item.riskSource.name,
      matchType: item.matchType.name,
      matchConfidence: item.matchConfidence,
      matchAuthority: item.matchAuthority.name,
      eligibleForAdditiveQuality: item.eligibleForFutureAdditiveScore,
      nutritionOverlap: item.nutritionMethodologyOverlap.name,
      penaltyContribution: penalty ?? 0,
      exclusionReason: exclusionReason,
      sourceTokens: item.sourceTokens,
    );
  }

  ScoreAuditNutritionResultSnapshot _nutritionResult(
    NutritionRawScoreResult raw,
    double nutritionQuality,
  ) {
    final negative = raw.negativePoints;
    final positive = raw.positivePoints;
    return ScoreAuditNutritionResultSnapshot(
      resolvedCategory: raw.resolvedCategory.name,
      rawScore: raw.rawScore,
      isPlainWaterSpecialCase: raw.isPlainWaterSpecialCase,
      negativePoints: negative == null
          ? const {}
          : {
              'energy': negative.energyPoints,
              'sugars': negative.sugarsPoints,
              'saturated_fat': negative.saturatedFatPoints,
              'salt': negative.saltPoints,
              'nns': negative.nnsPoints,
              'saturated_energy': negative.saturatedEnergyPoints,
              'saturated_fat_ratio': negative.saturatedFatRatioPoints,
              'total': negative.total,
              if (negative.saturatedEnergyKj != null)
                'saturated_energy_kj': negative.saturatedEnergyKj,
              if (negative.saturatedFatRatioPercent != null)
                'saturated_fat_ratio_percent':
                    negative.saturatedFatRatioPercent,
            },
      positivePoints: positive == null
          ? const {}
          : {
              'protein_calculated': positive.proteinPointsCalculated,
              'protein_applied': positive.proteinPointsApplied,
              'fiber': positive.fiberPoints,
              'fvl': positive.fvlPoints,
              'calculated_total': positive.calculatedTotal,
              'applied_total': positive.appliedTotal,
            },
      specialRules: raw.specialRules.map((rule) => rule.name).toList()..sort(),
      nutritionQuality: nutritionQuality,
    );
  }

  ScoreAuditAdditiveResultSnapshot _additiveResult(
    AdditiveQualityResult result,
  ) {
    return ScoreAuditAdditiveResultSnapshot(
      additiveQuality: result.qualityScore,
      unclampedAdditiveQuality: result.unclampedQualityScore,
      totalPenalty: result.totalPenalty,
      counts: {
        'eligible_unique': result.eligibleUniqueAdditiveCount,
        'low': result.lowCount,
        'medium': result.mediumCount,
        'high': result.highCount,
        'penalized_low': result.penalizedLowCount,
        'penalized_medium': result.penalizedMediumCount,
        'penalized_high': result.penalizedHighCount,
        'unknown_or_ineligible': result.unknownOrIneligibleCount,
        'ordinary_ingredients': result.ordinaryIngredientCount,
        'nutrition_overlap_excluded': result.excludedForNutritionOverlapCount,
      },
      tierContributions: result.contributions
          .map(
            (tier) => <String, Object?>{
              'risk_level': tier.riskLevel.name,
              'penalized_count': tier.penalizedCount,
              'first_item_impact': tier.firstItemImpact,
              'additional_item_decay': tier.additionalItemDecay,
              'penalty': tier.penalty,
              'asymptotic_penalty_cap': tier.asymptoticPenaltyCap,
            },
          )
          .toList(growable: false),
    );
  }

  String? _clean(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
