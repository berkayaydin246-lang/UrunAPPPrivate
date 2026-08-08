import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';

class AdditiveQualityTransformer {
  const AdditiveQualityTransformer();

  static const double lowFirstItemImpact = 2;
  static const double mediumFirstItemImpact = 9;
  static const double highFirstItemImpact = 24;
  static const double additionalItemDecay = 0.75;

  AdditiveQualityResult transform(CanonicalAdditiveAssessment assessment) {
    final canonicalAdditives = assessment.canonicalAdditives;
    final eligible = canonicalAdditives
        .where(_isNumericallyEligible)
        .toList(growable: false);
    final overlapExcluded = eligible
        .where(
          (item) =>
              item.nutritionMethodologyOverlap ==
              NutritionMethodologyOverlap.beverageNnsAlreadyRepresented,
        )
        .toList(growable: false);
    final penalized = eligible
        .where(
          (item) =>
              item.nutritionMethodologyOverlap !=
              NutritionMethodologyOverlap.beverageNnsAlreadyRepresented,
        )
        .toList(growable: false);

    int eligibleCount(CanonicalRiskLevel level) =>
        eligible.where((item) => item.riskLevel == level).length;
    int penalizedCount(CanonicalRiskLevel level) =>
        penalized.where((item) => item.riskLevel == level).length;

    final penalizedLowCount = penalizedCount(CanonicalRiskLevel.low);
    final penalizedMediumCount = penalizedCount(CanonicalRiskLevel.medium);
    final penalizedHighCount = penalizedCount(CanonicalRiskLevel.high);
    final contributions = <AdditiveQualityTierContribution>[
      _contribution(
        CanonicalRiskLevel.low,
        penalizedLowCount,
        lowFirstItemImpact,
      ),
      _contribution(
        CanonicalRiskLevel.medium,
        penalizedMediumCount,
        mediumFirstItemImpact,
      ),
      _contribution(
        CanonicalRiskLevel.high,
        penalizedHighCount,
        highFirstItemImpact,
      ),
    ];
    final totalPenalty = contributions.fold<double>(
      0,
      (sum, contribution) => sum + contribution.penalty,
    );
    final unclampedQualityScore = 100 - totalPenalty;
    final qualityScore = unclampedQualityScore.clamp(0, 100).toDouble();
    final unknownOrIneligibleCount =
        canonicalAdditives
            .where((item) => !_isNumericallyEligible(item))
            .length +
        assessment.unresolvedIngredients.length;

    return AdditiveQualityResult(
      qualityScore: qualityScore,
      unclampedQualityScore: unclampedQualityScore,
      totalPenalty: totalPenalty,
      canonicalAssessment: assessment,
      eligibleUniqueAdditiveCount: eligible.length,
      lowCount: eligibleCount(CanonicalRiskLevel.low),
      mediumCount: eligibleCount(CanonicalRiskLevel.medium),
      highCount: eligibleCount(CanonicalRiskLevel.high),
      penalizedLowCount: penalizedLowCount,
      penalizedMediumCount: penalizedMediumCount,
      penalizedHighCount: penalizedHighCount,
      unknownOrIneligibleCount: unknownOrIneligibleCount,
      ordinaryIngredientCount: assessment.ordinaryIngredients.length,
      contributions: contributions,
      overlapExclusions: overlapExcluded.map(
        (item) => AdditiveQualityExcludedItem(
          item: item,
          reason: AdditiveQualityExclusionReason.beverageNnsAlreadyRepresented,
        ),
      ),
    );
  }

  bool _isNumericallyEligible(CanonicalIngredientAssessment item) =>
      item.eligibleForFutureAdditiveScore &&
      item.riskLevel != CanonicalRiskLevel.unknown;

  AdditiveQualityTierContribution _contribution(
    CanonicalRiskLevel riskLevel,
    int count,
    double firstItemImpact,
  ) {
    var nextImpact = firstItemImpact;
    var penalty = 0.0;
    for (var index = 0; index < count; index += 1) {
      penalty += nextImpact;
      nextImpact *= additionalItemDecay;
    }
    return AdditiveQualityTierContribution(
      riskLevel: riskLevel,
      penalizedCount: count,
      firstItemImpact: firstItemImpact,
      additionalItemDecay: additionalItemDecay,
      penalty: penalty,
    );
  }
}
