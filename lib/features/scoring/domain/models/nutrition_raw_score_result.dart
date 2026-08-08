import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

const nutritionRawMethodologyVersion = 'updated_nutrition_profile_2023_v1';

enum NutritionSpecialRule {
  plainWater,
  generalProteinSuppressed,
  cheeseProteinAppliedAtHighNegativePoints,
  redMeatProteinCapped,
  redMeatProteinSuppressed,
  fatSaturatedEnergyAndRatio,
  fatProteinSuppressed,
  beverageNnsApplied,
}

class NutritionNegativePointBreakdown {
  final int energyPoints;
  final int sugarsPoints;
  final int saturatedFatPoints;
  final int saltPoints;
  final int nnsPoints;
  final int saturatedEnergyPoints;
  final int saturatedFatRatioPoints;
  final double? saturatedEnergyKj;
  final double? saturatedFatRatioPercent;

  const NutritionNegativePointBreakdown({
    this.energyPoints = 0,
    this.sugarsPoints = 0,
    this.saturatedFatPoints = 0,
    this.saltPoints = 0,
    this.nnsPoints = 0,
    this.saturatedEnergyPoints = 0,
    this.saturatedFatRatioPoints = 0,
    this.saturatedEnergyKj,
    this.saturatedFatRatioPercent,
  });

  int get total =>
      energyPoints +
      sugarsPoints +
      saturatedFatPoints +
      saltPoints +
      nnsPoints +
      saturatedEnergyPoints +
      saturatedFatRatioPoints;
}

class NutritionPositivePointBreakdown {
  final int proteinPointsCalculated;
  final int proteinPointsApplied;
  final int fiberPoints;
  final int fvlPoints;

  const NutritionPositivePointBreakdown({
    required this.proteinPointsCalculated,
    required this.proteinPointsApplied,
    required this.fiberPoints,
    required this.fvlPoints,
  });

  int get calculatedTotal => proteinPointsCalculated + fiberPoints + fvlPoints;

  int get appliedTotal => proteinPointsApplied + fiberPoints + fvlPoints;
}

sealed class NutritionRawScoreResult {
  final ScoringCategory resolvedCategory;
  final String methodologyVersion;
  final Set<NutritionSpecialRule> specialRules;

  NutritionRawScoreResult({
    required this.resolvedCategory,
    required Iterable<NutritionSpecialRule> specialRules,
  }) : methodologyVersion = nutritionRawMethodologyVersion,
       specialRules = Set.unmodifiable(specialRules);

  NutritionNegativePointBreakdown? get negativePoints;

  NutritionPositivePointBreakdown? get positivePoints;

  int? get negativePointsTotal => negativePoints?.total;

  int? get positivePointsCalculated => positivePoints?.calculatedTotal;

  int? get positivePointsApplied => positivePoints?.appliedTotal;

  int? get rawScore;

  bool get isPlainWaterSpecialCase;

  int? get energyPoints => negativePoints?.energyPoints;

  int? get sugarsPoints => negativePoints?.sugarsPoints;

  int? get saturatedFatPoints => negativePoints?.saturatedFatPoints;

  int? get saltPoints => negativePoints?.saltPoints;

  int? get nnsPoints => negativePoints?.nnsPoints;

  int? get saturatedEnergyPoints => negativePoints?.saturatedEnergyPoints;

  int? get saturatedFatRatioPoints => negativePoints?.saturatedFatRatioPoints;

  int? get proteinPointsCalculated => positivePoints?.proteinPointsCalculated;

  int? get proteinPointsApplied => positivePoints?.proteinPointsApplied;

  int? get fiberPoints => positivePoints?.fiberPoints;

  int? get fvlPoints => positivePoints?.fvlPoints;
}

final class CalculatedNutritionRawScoreResult extends NutritionRawScoreResult {
  @override
  final NutritionNegativePointBreakdown negativePoints;

  @override
  final NutritionPositivePointBreakdown positivePoints;

  @override
  final int rawScore;

  CalculatedNutritionRawScoreResult({
    required super.resolvedCategory,
    required this.negativePoints,
    required this.positivePoints,
    required this.rawScore,
    super.specialRules = const [],
  });

  @override
  bool get isPlainWaterSpecialCase => false;
}

final class PlainWaterNutritionRawScoreResult extends NutritionRawScoreResult {
  PlainWaterNutritionRawScoreResult()
    : super(
        resolvedCategory: ScoringCategory.beverage,
        specialRules: const [NutritionSpecialRule.plainWater],
      );

  @override
  NutritionNegativePointBreakdown? get negativePoints => null;

  @override
  NutritionPositivePointBreakdown? get positivePoints => null;

  @override
  int? get rawScore => null;

  @override
  bool get isPlainWaterSpecialCase => true;
}
