import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';

import 'support/additive_quality_test_support.dart';
import 'support/etiketly_score_test_support.dart';

enum _FinalCalibrationBand { veryHigh, high, mid, low, veryLow }

class _AdditiveProfile {
  const _AdditiveProfile({required this.name, required this.codes});

  final String name;
  final List<String> codes;
}

class _NutritionCalibrationRow {
  const _NutritionCalibrationRow({
    required this.quality,
    required this.expectedBands,
  });

  final double quality;
  final List<_FinalCalibrationBand> expectedBands;
}

class _WeightCandidate {
  const _WeightCandidate(this.nutrition, this.additives);

  final double nutrition;
  final double additives;

  double combine(double nutritionQuality, double additiveQuality) =>
      nutritionQuality * nutrition + additiveQuality * additives;
}

const _profiles = <_AdditiveProfile>[
  _AdditiveProfile(name: 'no eligible additives', codes: []),
  _AdditiveProfile(name: 'one reviewed low', codes: ['E322']),
  _AdditiveProfile(name: 'one reviewed medium', codes: ['E202']),
  _AdditiveProfile(name: 'one reviewed high', codes: ['E102']),
  _AdditiveProfile(name: 'two reviewed high', codes: ['E102', 'E110']),
  _AdditiveProfile(
    name: 'three reviewed high',
    codes: ['E102', 'E110', 'E129'],
  ),
];

const _rows = <_NutritionCalibrationRow>[
  _NutritionCalibrationRow(
    quality: 100,
    expectedBands: [
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.veryHigh,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 90,
    expectedBands: [
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.veryHigh,
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 80,
    expectedBands: [
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 70,
    expectedBands: [
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.high,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 60,
    expectedBands: [
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 50,
    expectedBands: [
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.low,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 40,
    expectedBands: [
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.mid,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 30,
    expectedBands: [
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 20,
    expectedBands: [
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.veryLow,
    ],
  ),
  _NutritionCalibrationRow(
    quality: 10,
    expectedBands: [
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.low,
      _FinalCalibrationBand.veryLow,
      _FinalCalibrationBand.veryLow,
      _FinalCalibrationBand.veryLow,
    ],
  ),
];

_FinalCalibrationBand _bandFor(double score) {
  if (score >= 85) return _FinalCalibrationBand.veryHigh;
  if (score >= 70) return _FinalCalibrationBand.high;
  if (score >= 50) return _FinalCalibrationBand.mid;
  if (score >= 25) return _FinalCalibrationBand.low;
  return _FinalCalibrationBand.veryLow;
}

void main() {
  const additiveTransformer = AdditiveQualityTransformer();

  group('weight candidate calibration', () {
    const candidates = [
      _WeightCandidate(0.90, 0.10),
      _WeightCandidate(0.85, 0.15),
      _WeightCandidate(0.80, 0.20),
      _WeightCandidate(0.75, 0.25),
      _WeightCandidate(0.70, 0.30),
      _WeightCandidate(0.60, 0.40),
    ];

    test('evaluates all six required nutrition/additive candidates', () {
      expect(candidates, hasLength(6));
      expect(
        candidates.map((candidate) => candidate.nutrition),
        orderedEquals([0.90, 0.85, 0.80, 0.75, 0.70, 0.60]),
      );
    });

    test('80/20 balances high-additive visibility and nutrition authority', () {
      final selected = candidates[2];
      final noPenalty = selected.combine(90, 100);
      final oneHigh = selected.combine(90, 76);
      final twoHigh = selected.combine(90, 58);

      expect(noPenalty - oneHigh, closeTo(4.8, 0.0000001));
      expect(noPenalty - twoHigh, closeTo(8.4, 0.0000001));
      expect(selected.combine(0, 100), 20);
      expect(EtiketlyScoreCalculator.nutritionWeight, selected.nutrition);
      expect(EtiketlyScoreCalculator.additiveWeight, selected.additives);
    });
  });

  final additiveQualities = _profiles
      .map(
        (profile) => additiveTransformer
            .transform(assessmentForCodes(profile.codes))
            .qualityScore,
      )
      .toList(growable: false);

  test('INTERNAL FINAL-SCORE CALIBRATION set contains exactly 60 cases', () {
    expect(_rows.length * _profiles.length, 60);
    expect(additiveQualities, orderedEquals([100, 98, 91, 76, 58, 44.5]));
  });

  for (var rowIndex = 0; rowIndex < _rows.length; rowIndex += 1) {
    final row = _rows[rowIndex];
    for (
      var profileIndex = 0;
      profileIndex < _profiles.length;
      profileIndex += 1
    ) {
      final profile = _profiles[profileIndex];
      test('INTERNAL FINAL-SCORE CALIBRATION nutrition ${row.quality} / '
          '${profile.name}', () {
        final result = calculateSyntheticScore(
          nutritionQuality: row.quality,
          additiveQuality: additiveQualities[profileIndex],
        );

        expect(result.score, inInclusiveRange(0, 100));
        expect(
          _bandFor(result.score!),
          row.expectedBands[profileIndex],
          reason:
              'nutrition=${row.quality}, '
              'additives=${additiveQualities[profileIndex]}, '
              'score=${result.score}',
        );
      });
    }
  }
}
