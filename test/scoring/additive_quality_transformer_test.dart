import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';

import 'support/additive_quality_test_support.dart';

void main() {
  const transformer = AdditiveQualityTransformer();
  const lowCodes = ['E322', 'E412', 'E415'];
  const mediumCodes = [
    'E200',
    'E202',
    'E210',
    'E211',
    'E319',
    'E320',
    'E321',
    'E950',
    'E954',
    'E955',
    'E407',
    'E471',
    'E120',
    'E621',
    'E965',
    'E952',
  ];
  const highCodes = ['E951', 'E133', 'E102', 'E129', 'E110', 'E250', 'E251'];

  AdditiveQualityResult resultFor(
    Iterable<String> codes, {
    ScoringCategory category = ScoringCategory.generalFood,
  }) => transformer.transform(assessmentForCodes(codes, category: category));

  double qualityFor(
    Iterable<String> codes, {
    ScoringCategory category = ScoringCategory.generalFood,
  }) => resultFor(codes, category: category).qualityScore;

  group('v1 formula and result diagnostics', () {
    test('no additives produce maximum additive quality', () {
      final result = resultFor(const []);

      expect(result.qualityScore, 100);
      expect(result.totalPenalty, 0);
      expect(result.eligibleUniqueAdditiveCount, 0);
    });

    test('one reviewed low additive has a small impact', () {
      final result = resultFor(const ['E322']);

      expect(result.qualityScore, 98);
      expect(result.lowCount, 1);
      expect(result.penalizedLowCount, 1);
    });

    test('one reviewed medium additive has a visible limited impact', () {
      final result = resultFor(const ['E202']);

      expect(result.qualityScore, 91);
      expect(result.mediumCount, 1);
      expect(result.penalizedMediumCount, 1);
    });

    test('one reviewed high additive has a clearly stronger impact', () {
      final result = resultFor(const ['E102']);

      expect(result.qualityScore, 76);
      expect(result.highCount, 1);
      expect(result.penalizedHighCount, 1);
    });

    test('high impact is greater than medium and medium than low', () {
      final low = resultFor(const ['E322']);
      final medium = resultFor(const ['E202']);
      final high = resultFor(const ['E102']);

      expect(high.totalPenalty, greaterThan(medium.totalPenalty));
      expect(medium.totalPenalty, greaterThan(low.totalPenalty));
      expect(high.qualityScore, lessThan(medium.qualityScore));
      expect(medium.qualityScore, lessThan(low.qualityScore));
    });

    test('geometric tier contributions preserve unrounded precision', () {
      final result = resultFor(const ['E200', 'E202', 'E210']);

      expect(result.totalPenalty, closeTo(20.8125, 0.0000001));
      expect(result.qualityScore, closeTo(79.1875, 0.0000001));
      expect(result.transformVersion, additiveQualityTransformVersion);
    });

    test('tier contribution metadata exposes exact v1 constants and caps', () {
      final result = resultFor(const ['E322', 'E202', 'E102']);
      final low = result.contributions.singleWhere(
        (item) => item.riskLevel == CanonicalRiskLevel.low,
      );
      final medium = result.contributions.singleWhere(
        (item) => item.riskLevel == CanonicalRiskLevel.medium,
      );
      final high = result.contributions.singleWhere(
        (item) => item.riskLevel == CanonicalRiskLevel.high,
      );

      expect(low.firstItemImpact, 2);
      expect(medium.firstItemImpact, 9);
      expect(high.firstItemImpact, 24);
      expect(low.additionalItemDecay, 0.75);
      expect(low.asymptoticPenaltyCap, 8);
      expect(medium.asymptoticPenaltyCap, 36);
      expect(high.asymptoticPenaltyCap, 96);
    });

    test('same canonical assessment is deterministic', () {
      final assessment = assessmentForCodes(const ['E322', 'E202', 'E102']);
      final first = transformer.transform(assessment);
      final second = transformer.transform(assessment);

      expect(second.qualityScore, first.qualityScore);
      expect(second.totalPenalty, first.totalPenalty);
      expect(second.transformVersion, first.transformVersion);
      expect(second.canonicalAssessment, same(assessment));
    });

    test('risk counts and penalized counts retain canonical summaries', () {
      final result = resultFor(const ['E322', 'E412', 'E200', 'E202', 'E102']);

      expect(result.lowCount, 2);
      expect(result.mediumCount, 2);
      expect(result.highCount, 1);
      expect(result.penalizedLowCount, 2);
      expect(result.penalizedMediumCount, 2);
      expect(result.penalizedHighCount, 1);
      expect(result.eligibleUniqueAdditiveCount, 5);
    });

    test('many reviewed additives clamp safely at the zero floor', () {
      final result = resultFor([...lowCodes, ...mediumCodes, ...highCodes]);

      expect(result.qualityScore, 0);
      expect(result.unclampedQualityScore, lessThan(0));
      expect(result.floorApplied, isTrue);
      expect(result.totalPenalty, greaterThan(100));
    });

    test(
      'quality always remains finite and within zero through one hundred',
      () {
        for (var lowCount = 0; lowCount <= lowCodes.length; lowCount += 1) {
          for (
            var mediumCount = 0;
            mediumCount <= mediumCodes.length;
            mediumCount += 1
          ) {
            for (
              var highCount = 0;
              highCount <= highCodes.length;
              highCount += 1
            ) {
              final quality = qualityFor([
                ...lowCodes.take(lowCount),
                ...mediumCodes.take(mediumCount),
                ...highCodes.take(highCount),
              ]);
              expect(quality, inInclusiveRange(0, 100));
              expect(quality.isFinite, isTrue);
            }
          }
        }
      },
    );
  });

  group('canonical identity and eligibility gates', () {
    test('E-code, canonical name, and alias occurrences have one impact', () {
      final duplicated = duplicateAssessment('E250');
      final duplicateResult = transformer.transform(duplicated);
      final singleResult = resultFor(const ['E250']);

      expect(duplicated.canonicalAdditives, hasLength(1));
      expect(duplicated.canonicalAdditives.single.occurrenceCount, 3);
      expect(duplicateResult.qualityScore, singleResult.qualityScore);
      expect(duplicateResult.highCount, 1);
    });

    test('different additives in the same group contribute separately', () {
      final one = resultFor(const ['E250']);
      final two = resultFor(const ['E250', 'E251']);

      expect(two.highCount, 2);
      expect(two.qualityScore, lessThan(one.qualityScore));
      expect(two.qualityScore, 58);
    });

    test('unknown catalogue gaps receive no invented penalty', () {
      const gaps = [
        'E249',
        'E252',
        'E957',
        'E959',
        'E960',
        'E961',
        'E962',
        'E969',
      ];
      final assessment = assessmentForCodes(gaps);
      final result = transformer.transform(assessment);

      expect(assessment.canonicalAdditives, hasLength(gaps.length));
      expect(
        assessment.canonicalAdditives.map((item) => item.riskLevel).toSet(),
        {CanonicalRiskLevel.unknown},
      );
      expect(result.qualityScore, 100);
      expect(result.eligibleUniqueAdditiveCount, 0);
      expect(result.unknownOrIneligibleCount, gaps.length);
    });

    test('review-required fuzzy match receives no trusted penalty', () {
      final assessment = fuzzyAssessment('E202');
      final result = transformer.transform(assessment);

      expect(
        assessment.canonicalAdditives.single.matchAuthority,
        CanonicalMatchAuthority.reviewRequired,
      );
      expect(result.qualityScore, 100);
      expect(result.unknownOrIneligibleCount, 1);
    });

    test('conflicted canonical item receives no trusted penalty', () {
      final assessment = conflictingAssessment();
      final result = transformer.transform(assessment);

      expect(assessment.conflicts, isNotEmpty);
      expect(
        assessment.canonicalAdditives.single.riskLevel,
        CanonicalRiskLevel.unknown,
      );
      expect(result.qualityScore, 100);
      expect(result.unknownOrIneligibleCount, 1);
    });

    test('ordinary ingredient receives no additive penalty', () {
      final result = transformer.transform(ordinaryAssessment());

      expect(result.qualityScore, 100);
      expect(result.ordinaryIngredientCount, 1);
      expect(result.eligibleUniqueAdditiveCount, 0);
    });

    test('unresolved token receives no invented penalty', () {
      final result = transformer.transform(unresolvedAssessment());

      expect(result.qualityScore, 100);
      expect(result.unknownOrIneligibleCount, 1);
    });

    test(
      'eligible item contributes while mixed unknown remains diagnostic',
      () {
        final result = resultFor(const ['E202', 'E249']);

        expect(result.qualityScore, 91);
        expect(result.mediumCount, 1);
        expect(result.unknownOrIneligibleCount, 1);
      },
    );
  });

  group('beverage NNS nutrition overlap', () {
    test('qualifying beverage NNS remains visible but contributes nothing', () {
      final assessment = assessmentForCodes(const [
        'E955',
      ], category: ScoringCategory.beverage);
      final result = transformer.transform(assessment);
      final item = assessment.canonicalAdditives.single;

      expect(item.riskLevel, CanonicalRiskLevel.medium);
      expect(item.eligibleForFutureAdditiveScore, isTrue);
      expect(
        item.nutritionMethodologyOverlap,
        NutritionMethodologyOverlap.beverageNnsAlreadyRepresented,
      );
      expect(result.qualityScore, 100);
      expect(result.mediumCount, 1);
      expect(result.penalizedMediumCount, 0);
      expect(result.excludedForNutritionOverlapCount, 1);
      expect(result.overlapExclusions.single.item, same(item));
      expect(
        result.overlapExclusions.single.reason,
        AdditiveQualityExclusionReason.beverageNnsAlreadyRepresented,
      );
    });

    test('overlap-excluded NNS is an explicit monotonicity exception', () {
      final none = resultFor(const []);
      final overlapOnly = resultFor(const [
        'E955',
      ], category: ScoringCategory.beverage);

      expect(overlapOnly.qualityScore, none.qualityScore);
      expect(overlapOnly.excludedForNutritionOverlapCount, 1);
    });

    test('same non-beverage sweetener is not automatically excluded', () {
      final result = resultFor(const ['E955']);

      expect(result.qualityScore, 91);
      expect(result.penalizedMediumCount, 1);
      expect(result.excludedForNutritionOverlapCount, 0);
    });

    test('beverage NNS plus unrelated medium penalizes only the medium', () {
      final result = resultFor(const [
        'E955',
        'E202',
      ], category: ScoringCategory.beverage);

      expect(result.qualityScore, 91);
      expect(result.mediumCount, 2);
      expect(result.penalizedMediumCount, 1);
      expect(result.excludedForNutritionOverlapCount, 1);
    });

    test('beverage NNS plus unrelated high penalizes only the high', () {
      final result = resultFor(const [
        'E955',
        'E102',
      ], category: ScoringCategory.beverage);

      expect(result.qualityScore, 76);
      expect(result.penalizedMediumCount, 0);
      expect(result.penalizedHighCount, 1);
      expect(result.excludedForNutritionOverlapCount, 1);
    });

    test('polyol is not overlap-excluded merely for being a sweetener', () {
      final result = resultFor(const [
        'E965',
      ], category: ScoringCategory.beverage);

      expect(result.qualityScore, 91);
      expect(result.penalizedMediumCount, 1);
      expect(result.excludedForNutritionOverlapCount, 0);
    });
  });

  group('table-driven monotonicity', () {
    test('adding items within every risk tier never improves quality', () {
      for (final codes in [lowCodes, mediumCodes, highCodes]) {
        var previous = qualityFor(const []);
        for (var count = 1; count <= codes.length; count += 1) {
          final current = qualityFor(codes.take(count));
          expect(
            current,
            lessThanOrEqualTo(previous),
            reason: '${codes.first}: count $count',
          );
          previous = current;
        }
      }
    });

    test(
      'adding low, medium, or high to mixed bases never improves quality',
      () {
        const bases = <List<String>>[
          [],
          ['E322'],
          ['E200'],
          ['E102'],
          ['E322', 'E200', 'E102'],
          ['E200', 'E202'],
        ];
        for (final base in bases) {
          final baseQuality = qualityFor(base);
          for (final additional in const ['E412', 'E210', 'E110']) {
            if (base.contains(additional)) continue;
            expect(
              qualityFor([...base, additional]),
              lessThanOrEqualTo(baseQuality),
              reason: '$base + $additional',
            );
          }
        }
      },
    );

    test('replacing low with medium or medium with high never improves', () {
      expect(qualityFor(const ['E202']), lessThan(qualityFor(const ['E322'])));
      expect(qualityFor(const ['E102']), lessThan(qualityFor(const ['E202'])));
      expect(
        qualityFor(const ['E202', 'E210']),
        lessThan(qualityFor(const ['E322', 'E412'])),
      );
      expect(
        qualityFor(const ['E102', 'E110']),
        lessThan(qualityFor(const ['E202', 'E210'])),
      );
    });

    test('removing an eligible penalty item never worsens quality', () {
      const codes = ['E322', 'E412', 'E200', 'E202', 'E102', 'E110'];
      final full = qualityFor(codes);
      for (var index = 0; index < codes.length; index += 1) {
        final reduced = [...codes]..removeAt(index);
        expect(qualityFor(reduced), greaterThanOrEqualTo(full));
      }
    });
  });

  test('nutrition quality transformation remains unchanged', () {
    final rawResult = CalculatedNutritionRawScoreResult(
      resolvedCategory: ScoringCategory.beverage,
      negativePoints: const NutritionNegativePointBreakdown(),
      positivePoints: const NutritionPositivePointBreakdown(
        proteinPointsCalculated: 0,
        proteinPointsApplied: 0,
        fiberPoints: 0,
        fvlPoints: 0,
      ),
      rawScore: 3,
    );

    expect(
      const NutritionQualityTransformer.v1().transform(rawResult).qualityScore,
      closeTo(66.875, 0.0000001),
    );
  });
}
