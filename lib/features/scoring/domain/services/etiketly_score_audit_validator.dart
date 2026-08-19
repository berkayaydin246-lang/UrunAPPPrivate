import 'dart:math' as math;

import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/score_audit_fingerprint.dart';

enum ScoreAuditValidationIssue {
  unsupportedSchema,
  unsupportedVersion,
  malformedFingerprint,
  fingerprintMismatch,
  nonFiniteValue,
  valueOutOfRange,
  invalidResolvedInput,
  invalidCanonicalAdditive,
  nutritionBreakdownMismatch,
  additiveBreakdownMismatch,
  contributionMismatch,
  finalScoreMismatch,
}

class ScoreAuditValidationResult {
  ScoreAuditValidationResult(Iterable<ScoreAuditValidationIssue> issues)
    : issues = Set.unmodifiable(issues);

  final Set<ScoreAuditValidationIssue> issues;

  bool get isValid => issues.isEmpty;
}

class EtiketlyScoreAuditValidator {
  const EtiketlyScoreAuditValidator();

  static const double tolerance = 1e-9;

  ScoreAuditValidationResult validate(EtiketlyScoreAuditSnapshot snapshot) {
    final issues = <ScoreAuditValidationIssue>{};
    if (snapshot.schemaVersion !=
        EtiketlyScoreAuditSnapshot.currentSchemaVersion) {
      issues.add(ScoreAuditValidationIssue.unsupportedSchema);
    }
    if (!_isSupportedVersionSet(snapshot)) {
      issues.add(ScoreAuditValidationIssue.unsupportedVersion);
    }

    if (!ScoreAuditFingerprint.isValid(snapshot.inputFingerprint)) {
      issues.add(ScoreAuditValidationIssue.malformedFingerprint);
    } else {
      try {
        final expected = ScoreAuditFingerprint.create(
          snapshot.fingerprintPayload(),
        );
        if (expected != snapshot.inputFingerprint) {
          issues.add(ScoreAuditValidationIssue.fingerprintMismatch);
        }
      } on ArgumentError {
        issues.add(ScoreAuditValidationIssue.nonFiniteValue);
      }
    }

    final scoreValues = [
      snapshot.nutritionResult.nutritionQuality,
      snapshot.additiveResult.additiveQuality,
      snapshot.finalScore,
    ];
    final calculatedValues = [
      ...scoreValues,
      snapshot.additiveResult.unclampedAdditiveQuality,
      snapshot.additiveResult.totalPenalty,
      snapshot.nutritionContribution,
      snapshot.additiveContribution,
      ...snapshot.canonicalAdditives.expand(
        (item) => [item.matchConfidence, item.penaltyContribution],
      ),
    ];
    if (calculatedValues.any((value) => !value.isFinite)) {
      issues.add(ScoreAuditValidationIssue.nonFiniteValue);
    }
    final nestedNumbers = <num>[
      ...snapshot.resolvedInput.nutrition.values
          .map((evidence) => evidence.value)
          .whereType<num>(),
      ...snapshot.resolvedInput.classificationFacts.values
          .map((evidence) => evidence?.value)
          .whereType<num>(),
      ...snapshot.nutritionResult.negativePoints.values.whereType<num>(),
      ...snapshot.nutritionResult.positivePoints.values.whereType<num>(),
      ...snapshot.additiveResult.tierContributions
          .expand((tier) => tier.values)
          .whereType<num>(),
      if (snapshot.resolvedInput.fvlEvidence.percentage != null)
        snapshot.resolvedInput.fvlEvidence.percentage!,
    ];
    if (nestedNumbers.any((value) => !value.isFinite)) {
      issues.add(ScoreAuditValidationIssue.nonFiniteValue);
    }
    if (scoreValues.any((value) => value < 0 || value > 100) ||
        snapshot.additiveResult.totalPenalty < 0 ||
        snapshot.canonicalAdditives.any(
          (item) =>
              item.matchConfidence < 0 ||
              item.matchConfidence > 1 ||
              item.penaltyContribution < 0,
        )) {
      issues.add(ScoreAuditValidationIssue.valueOutOfRange);
    }

    _validateResolvedInput(snapshot, issues);
    _validateCanonicalAdditives(snapshot, issues);
    _validateNutrition(snapshot, issues);
    _validateAdditive(snapshot, issues);
    _validateFinalScore(snapshot, issues);
    return ScoreAuditValidationResult(issues);
  }

  void _validateResolvedInput(
    EtiketlyScoreAuditSnapshot snapshot,
    Set<ScoreAuditValidationIssue> issues,
  ) {
    const nutritionKeys = {
      'energy_kj',
      'energy_kcal',
      'total_fat',
      'saturated_fat',
      'sugars',
      'protein',
      'fiber',
      'salt',
      'sodium',
    };
    const classificationBooleanKeys = {
      'is_plain_water',
      'red_meat_is_primary_ingredient',
      'is_plant_based_cheese_alternative',
      'is_compound_product',
      'is_drinkable_dairy',
      'is_beverage',
      'is_food_supplement',
      'is_infant_food',
      'is_medical_food',
      'is_sports_nutrition',
      'is_meal_replacement',
    };
    const classificationNumberKeys = {
      'red_meat_percentage',
      'nut_seed_percentage',
    };
    final input = snapshot.resolvedInput;
    final classificationKeys = {
      ...classificationBooleanKeys,
      ...classificationNumberKeys,
    };
    var invalid =
        input.nutrition.keys.toSet().difference(nutritionKeys).isNotEmpty ||
        nutritionKeys.difference(input.nutrition.keys.toSet()).isNotEmpty ||
        input.classificationFacts.keys
            .toSet()
            .difference(classificationKeys)
            .isNotEmpty ||
        classificationKeys
            .difference(input.classificationFacts.keys.toSet())
            .isNotEmpty ||
        !NutritionBasis.values.any(
          (value) => value.name == input.nutritionBasis,
        ) ||
        !NutritionProductState.values.any(
          (value) => value.name == input.productState,
        ) ||
        !ScoringCategory.values.any(
          (value) => value.name == input.resolvedCategory,
        ) ||
        !CategoryEvidenceSource.values.any(
          (value) => value.name == input.categorySource,
        ) ||
        !IngredientEvidenceCompleteness.values.any(
          (value) => value.name == input.ingredientEvidenceCompleteness,
        ) ||
        input.categoryReasons.any(
          (reason) => !CategoryResolutionReason.values.any(
            (value) => value.name == reason,
          ),
        ) ||
        input.nutrition.values.any(
          (evidence) => !_validEvidence(evidence, expectedType: num),
        );

    for (final key in classificationBooleanKeys) {
      final evidence = input.classificationFacts[key];
      if (evidence != null && !_validEvidence(evidence, expectedType: bool)) {
        invalid = true;
      }
    }
    for (final key in classificationNumberKeys) {
      final evidence = input.classificationFacts[key];
      if (evidence != null &&
          (!_validEvidence(evidence, expectedType: num) ||
              (evidence.value is num &&
                  ((evidence.value! as num) < 0 ||
                      (evidence.value! as num) > 100)))) {
        invalid = true;
      }
    }

    final fvl = input.fvlEvidence;
    invalid =
        invalid ||
        !CompositionPercentageState.values.any(
          (value) => value.name == fvl.state,
        ) ||
        !_validProvenance(fvl.provenance) ||
        !_validVerification(fvl.verification) ||
        !EvidenceDependency.values.any(
          (value) => value.name == fvl.dependency,
        ) ||
        (fvl.state == CompositionPercentageState.known.name &&
            (fvl.percentage == null ||
                fvl.percentage! < 0 ||
                fvl.percentage! > 100)) ||
        (fvl.state == CompositionPercentageState.provenAbsent.name &&
            fvl.percentage != 0) ||
        (fvl.state == CompositionPercentageState.unknown.name &&
            fvl.percentage != null);

    final nns = input.nnsEvidence;
    invalid =
        invalid ||
        !PresenceEvidenceState.values.any((value) => value.name == nns.state) ||
        !_validProvenance(nns.provenance) ||
        !_validVerification(nns.verification) ||
        !EvidenceDependency.values.any((value) => value.name == nns.dependency);

    if (invalid) {
      issues.add(ScoreAuditValidationIssue.invalidResolvedInput);
    }
  }

  bool _validEvidence(
    ScoreAuditEvidenceValueSnapshot evidence, {
    required Type expectedType,
  }) {
    final value = evidence.value;
    final validType =
        value == null ||
        (expectedType == num && value is num) ||
        (expectedType == bool && value is bool);
    return validType &&
        _validProvenance(evidence.provenance) &&
        _validVerification(evidence.verification);
  }

  bool _validProvenance(String value) =>
      EvidenceProvenance.values.any((item) => item.name == value);

  bool _validVerification(String value) =>
      EvidenceVerification.values.any((item) => item.name == value);

  void _validateCanonicalAdditives(
    EtiketlyScoreAuditSnapshot snapshot,
    Set<ScoreAuditValidationIssue> issues,
  ) {
    const risks = {'low', 'medium', 'high', 'unknown'};
    const riskSources = {
      'ingredientCatalogue',
      'reviewedExplanationCatalogue',
      'consistentCatalogues',
      'unresolvedConflict',
      'unknown',
    };
    const matchTypes = {
      'exactMatch',
      'eCodeMatch',
      'aliasMatch',
      'highConfidenceFuzzy',
      'lowConfidencePossible',
      'unmatched',
    };
    const authorities = {'authoritative', 'reviewRequired', 'unresolved'};
    const overlaps = {'none', 'beverageNnsAlreadyRepresented'};
    final keys = <String>{};
    for (final item in snapshot.canonicalAdditives) {
      final malformed =
          !keys.add(item.canonicalKey) ||
          !risks.contains(item.riskLevelAtCalculationTime) ||
          !riskSources.contains(item.riskSource) ||
          !matchTypes.contains(item.matchType) ||
          !authorities.contains(item.matchAuthority) ||
          !overlaps.contains(item.nutritionOverlap) ||
          (item.eligibleForAdditiveQuality &&
              item.riskLevelAtCalculationTime == 'unknown') ||
          (item.nutritionOverlap != 'none' &&
              !_close(item.penaltyContribution, 0));
      if (malformed) {
        issues.add(ScoreAuditValidationIssue.invalidCanonicalAdditive);
      }
    }
  }

  void _validateNutrition(
    EtiketlyScoreAuditSnapshot snapshot,
    Set<ScoreAuditValidationIssue> issues,
  ) {
    final nutrition = snapshot.nutritionResult;
    final category = ScoringCategory.values
        .where((value) => value.name == nutrition.resolvedCategory)
        .firstOrNull;
    final specialRules = <NutritionSpecialRule>{};
    for (final name in nutrition.specialRules) {
      final rule = NutritionSpecialRule.values
          .where((value) => value.name == name)
          .firstOrNull;
      if (rule == null) {
        issues.add(ScoreAuditValidationIssue.nutritionBreakdownMismatch);
        return;
      }
      specialRules.add(rule);
    }
    if (category == null ||
        nutrition.resolvedCategory != snapshot.resolvedInput.resolvedCategory) {
      issues.add(ScoreAuditValidationIssue.nutritionBreakdownMismatch);
      return;
    }

    NutritionRawScoreResult raw;
    if (nutrition.isPlainWaterSpecialCase) {
      if (nutrition.rawScore != null ||
          nutrition.negativePoints.isNotEmpty ||
          nutrition.positivePoints.isNotEmpty ||
          !specialRules.contains(NutritionSpecialRule.plainWater)) {
        issues.add(ScoreAuditValidationIssue.nutritionBreakdownMismatch);
        return;
      }
      raw = PlainWaterNutritionRawScoreResult();
    } else {
      final negative = nutrition.negativePoints;
      final positive = nutrition.positivePoints;
      final requiredNegative = [
        'energy',
        'sugars',
        'saturated_fat',
        'salt',
        'nns',
        'saturated_energy',
        'saturated_fat_ratio',
        'total',
      ];
      final requiredPositive = [
        'protein_calculated',
        'protein_applied',
        'fiber',
        'fvl',
        'calculated_total',
        'applied_total',
      ];
      if (nutrition.rawScore == null ||
          requiredNegative.any((key) => negative[key] is! int) ||
          requiredPositive.any((key) => positive[key] is! int)) {
        issues.add(ScoreAuditValidationIssue.nutritionBreakdownMismatch);
        return;
      }
      final negativeResult = NutritionNegativePointBreakdown(
        energyPoints: negative['energy']! as int,
        sugarsPoints: negative['sugars']! as int,
        saturatedFatPoints: negative['saturated_fat']! as int,
        saltPoints: negative['salt']! as int,
        nnsPoints: negative['nns']! as int,
        saturatedEnergyPoints: negative['saturated_energy']! as int,
        saturatedFatRatioPoints: negative['saturated_fat_ratio']! as int,
        saturatedEnergyKj: (negative['saturated_energy_kj'] as num?)
            ?.toDouble(),
        saturatedFatRatioPercent:
            (negative['saturated_fat_ratio_percent'] as num?)?.toDouble(),
      );
      final positiveResult = NutritionPositivePointBreakdown(
        proteinPointsCalculated: positive['protein_calculated']! as int,
        proteinPointsApplied: positive['protein_applied']! as int,
        fiberPoints: positive['fiber']! as int,
        fvlPoints: positive['fvl']! as int,
      );
      if (negativeResult.total != negative['total'] ||
          positiveResult.calculatedTotal != positive['calculated_total'] ||
          positiveResult.appliedTotal != positive['applied_total'] ||
          negativeResult.total - positiveResult.appliedTotal !=
              nutrition.rawScore) {
        issues.add(ScoreAuditValidationIssue.nutritionBreakdownMismatch);
        return;
      }
      raw = CalculatedNutritionRawScoreResult(
        resolvedCategory: category,
        negativePoints: negativeResult,
        positivePoints: positiveResult,
        rawScore: nutrition.rawScore!,
        specialRules: specialRules,
      );
    }

    final transformer = switch (snapshot.nutritionTransformVersion) {
      nutritionQualityTransformV1Version =>
        const NutritionQualityTransformer.v1(),
      nutritionQualityTransformV2Version =>
        const NutritionQualityTransformer.v2(),
      nutritionQualityTransformV3Version =>
        const NutritionQualityTransformer.v3(),
      _ => null,
    };
    if (transformer == null) return;
    final expected = transformer.transform(raw);
    if (!_close(expected.qualityScore, nutrition.nutritionQuality)) {
      issues.add(ScoreAuditValidationIssue.nutritionBreakdownMismatch);
    }
  }

  void _validateAdditive(
    EtiketlyScoreAuditSnapshot snapshot,
    Set<ScoreAuditValidationIssue> issues,
  ) {
    final additive = snapshot.additiveResult;
    final expectedTierPenalties = <String, double>{};
    var totalPenalty = 0.0;
    for (final tier in additive.tierContributions) {
      final risk = tier['risk_level'];
      final count = tier['penalized_count'];
      final firstImpact = tier['first_item_impact'];
      final decay = tier['additional_item_decay'];
      final penalty = tier['penalty'];
      if (risk is! String ||
          count is! int ||
          count < 0 ||
          firstImpact is! num ||
          decay is! num ||
          penalty is! num ||
          !{'low', 'medium', 'high'}.contains(risk)) {
        issues.add(ScoreAuditValidationIssue.additiveBreakdownMismatch);
        return;
      }
      final expectedFirst = switch (risk) {
        'low' => AdditiveQualityTransformer.lowFirstItemImpact,
        'medium' => AdditiveQualityTransformer.mediumFirstItemImpact,
        _ => AdditiveQualityTransformer.highFirstItemImpact,
      };
      var expectedPenalty = 0.0;
      for (var index = 0; index < count; index += 1) {
        expectedPenalty +=
            expectedFirst *
            math.pow(AdditiveQualityTransformer.additionalItemDecay, index);
      }
      if (!_close(firstImpact.toDouble(), expectedFirst) ||
          !_close(
            decay.toDouble(),
            AdditiveQualityTransformer.additionalItemDecay,
          ) ||
          !_close(penalty.toDouble(), expectedPenalty)) {
        issues.add(ScoreAuditValidationIssue.additiveBreakdownMismatch);
      }
      expectedTierPenalties[risk] = expectedPenalty;
      totalPenalty += expectedPenalty;
    }

    final itemPenalty = snapshot.canonicalAdditives.fold<double>(
      0,
      (sum, item) => sum + item.penaltyContribution,
    );
    final expectedUnclamped = 100 - totalPenalty;
    final expectedQuality = expectedUnclamped.clamp(0, 100).toDouble();
    if (expectedTierPenalties.length != 3 ||
        !_close(totalPenalty, additive.totalPenalty) ||
        !_close(itemPenalty, additive.totalPenalty) ||
        !_close(expectedUnclamped, additive.unclampedAdditiveQuality) ||
        !_close(expectedQuality, additive.additiveQuality)) {
      issues.add(ScoreAuditValidationIssue.additiveBreakdownMismatch);
    }
  }

  void _validateFinalScore(
    EtiketlyScoreAuditSnapshot snapshot,
    Set<ScoreAuditValidationIssue> issues,
  ) {
    final expectedNutritionContribution =
        snapshot.nutritionResult.nutritionQuality *
        EtiketlyScoreCalculator.nutritionWeight;
    final expectedAdditiveContribution =
        snapshot.additiveResult.additiveQuality *
        EtiketlyScoreCalculator.additiveWeight;
    if (!_close(
          expectedNutritionContribution,
          snapshot.nutritionContribution,
        ) ||
        !_close(expectedAdditiveContribution, snapshot.additiveContribution)) {
      issues.add(ScoreAuditValidationIssue.contributionMismatch);
    }
    if (!_close(
      expectedNutritionContribution + expectedAdditiveContribution,
      snapshot.finalScore,
    )) {
      issues.add(ScoreAuditValidationIssue.finalScoreMismatch);
    }
  }

  static bool _close(double left, double right) =>
      (left - right).abs() <= tolerance;

  bool _isSupportedVersionSet(EtiketlyScoreAuditSnapshot snapshot) {
    // etiketlyScoreVersion was deliberately NOT bumped for V3 (see PART A
    // of the V3 rollout design — nutrition_transform_version is its own
    // independent axis in the version tuple, already enforced separately
    // by get_current_product_score_audit_snapshot/
    // record_product_score_audit_snapshot), so v3 pairs with the SAME
    // etiketlyScoreV2Version as v2, not a new score version.
    final scoreAndNutritionVersionsMatch =
        (snapshot.scoreVersion == etiketlyScoreV1Version &&
            snapshot.nutritionTransformVersion ==
                nutritionQualityTransformV1Version) ||
        (snapshot.scoreVersion == etiketlyScoreV2Version &&
            (snapshot.nutritionTransformVersion ==
                    nutritionQualityTransformV2Version ||
                snapshot.nutritionTransformVersion ==
                    nutritionQualityTransformV3Version));
    return scoreAndNutritionVersionsMatch &&
        snapshot.nutritionMethodologyVersion ==
            nutritionRawMethodologyVersion &&
        snapshot.additiveTransformVersion == additiveQualityTransformVersion;
  }
}
