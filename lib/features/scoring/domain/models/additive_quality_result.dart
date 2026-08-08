import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';

const additiveQualityTransformVersion = 'additive_quality_transform_v1';

enum AdditiveQualityExclusionReason { beverageNnsAlreadyRepresented }

class AdditiveQualityExcludedItem {
  const AdditiveQualityExcludedItem({required this.item, required this.reason});

  final CanonicalIngredientAssessment item;
  final AdditiveQualityExclusionReason reason;
}

class AdditiveQualityTierContribution {
  const AdditiveQualityTierContribution({
    required this.riskLevel,
    required this.penalizedCount,
    required this.firstItemImpact,
    required this.additionalItemDecay,
    required this.penalty,
  });

  final CanonicalRiskLevel riskLevel;
  final int penalizedCount;
  final double firstItemImpact;
  final double additionalItemDecay;
  final double penalty;

  double get asymptoticPenaltyCap =>
      firstItemImpact / (1 - additionalItemDecay);
}

class AdditiveQualityResult {
  AdditiveQualityResult({
    required this.qualityScore,
    required this.unclampedQualityScore,
    required this.totalPenalty,
    required this.canonicalAssessment,
    required this.eligibleUniqueAdditiveCount,
    required this.lowCount,
    required this.mediumCount,
    required this.highCount,
    required this.penalizedLowCount,
    required this.penalizedMediumCount,
    required this.penalizedHighCount,
    required this.unknownOrIneligibleCount,
    required this.ordinaryIngredientCount,
    required Iterable<AdditiveQualityTierContribution> contributions,
    required Iterable<AdditiveQualityExcludedItem> overlapExclusions,
  }) : assert(qualityScore >= 0 && qualityScore <= 100),
       assert(totalPenalty >= 0),
       assert(
         eligibleUniqueAdditiveCount == lowCount + mediumCount + highCount,
       ),
       assert(
         penalizedLowCount +
                 penalizedMediumCount +
                 penalizedHighCount +
                 overlapExclusions.length ==
             eligibleUniqueAdditiveCount,
       ),
       transformVersion = additiveQualityTransformVersion,
       contributions = List.unmodifiable(contributions),
       overlapExclusions = List.unmodifiable(overlapExclusions);

  final double qualityScore;
  final double unclampedQualityScore;
  final double totalPenalty;
  final String transformVersion;
  final CanonicalAdditiveAssessment canonicalAssessment;
  final int eligibleUniqueAdditiveCount;
  final int lowCount;
  final int mediumCount;
  final int highCount;
  final int penalizedLowCount;
  final int penalizedMediumCount;
  final int penalizedHighCount;
  final int unknownOrIneligibleCount;
  final int ordinaryIngredientCount;
  final List<AdditiveQualityTierContribution> contributions;
  final List<AdditiveQualityExcludedItem> overlapExclusions;

  int get excludedForNutritionOverlapCount => overlapExclusions.length;
  bool get floorApplied => unclampedQualityScore < 0;

  double penaltyFor(CanonicalRiskLevel riskLevel) => contributions
      .where((contribution) => contribution.riskLevel == riskLevel)
      .fold(0, (sum, contribution) => sum + contribution.penalty);
}
