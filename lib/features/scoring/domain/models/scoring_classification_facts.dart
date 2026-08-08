import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';

class ScoringClassificationFacts {
  final EvidenceValue<bool>? isPlainWater;
  final EvidenceValue<double>? redMeatPercentage;
  final EvidenceValue<bool>? redMeatIsPrimaryIngredient;
  final EvidenceValue<double>? nutSeedPercentage;
  final EvidenceValue<bool>? isPlantBasedCheeseAlternative;
  final EvidenceValue<bool>? isCompoundProduct;
  final EvidenceValue<bool>? isDrinkableDairy;
  final EvidenceValue<bool>? isBeverage;
  final EvidenceValue<bool>? isFoodSupplement;
  final EvidenceValue<bool>? isInfantFood;
  final EvidenceValue<bool>? isMedicalFood;
  final EvidenceValue<bool>? isSportsNutrition;
  final EvidenceValue<bool>? isMealReplacement;

  const ScoringClassificationFacts({
    this.isPlainWater,
    this.redMeatPercentage,
    this.redMeatIsPrimaryIngredient,
    this.nutSeedPercentage,
    this.isPlantBasedCheeseAlternative,
    this.isCompoundProduct,
    this.isDrinkableDairy,
    this.isBeverage,
    this.isFoodSupplement,
    this.isInfantFood,
    this.isMedicalFood,
    this.isSportsNutrition,
    this.isMealReplacement,
  });

  bool get hasTrustedOutOfScopeFact => [
    isFoodSupplement,
    isInfantFood,
    isMedicalFood,
    isSportsNutrition,
    isMealReplacement,
  ].any((fact) => fact?.trustedValue == true);
}
