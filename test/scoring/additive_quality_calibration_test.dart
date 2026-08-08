import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';

import 'support/additive_quality_test_support.dart';

enum _CalibrationBand { veryHigh, high, mid, low, veryLow }

class _CalibrationFixture {
  const _CalibrationFixture({
    required this.name,
    required this.assessment,
    required this.expectedBand,
  });

  final String name;
  final CanonicalAdditiveAssessment assessment;
  final _CalibrationBand expectedBand;
}

_CalibrationBand _bandFor(double quality) {
  if (quality >= 95) return _CalibrationBand.veryHigh;
  if (quality >= 80) return _CalibrationBand.high;
  if (quality >= 55) return _CalibrationBand.mid;
  if (quality >= 25) return _CalibrationBand.low;
  return _CalibrationBand.veryLow;
}

void main() {
  const transformer = AdditiveQualityTransformer();

  _CalibrationFixture fixture(
    String name,
    List<String> codes,
    _CalibrationBand band, {
    ScoringCategory category = ScoringCategory.generalFood,
  }) => _CalibrationFixture(
    name: name,
    assessment: assessmentForCodes(codes, category: category),
    expectedBand: band,
  );

  final fixtures = <_CalibrationFixture>[
    fixture('no additives', const [], _CalibrationBand.veryHigh),
    fixture('one low lecithin', const ['E322'], _CalibrationBand.veryHigh),
    fixture('one low guar gum', const ['E412'], _CalibrationBand.veryHigh),
    fixture('one low xanthan gum', const ['E415'], _CalibrationBand.veryHigh),
    fixture('one medium preservative', const ['E200'], _CalibrationBand.high),
    fixture('one medium antioxidant', const ['E321'], _CalibrationBand.high),
    fixture('one medium non-beverage sweetener', const [
      'E955',
    ], _CalibrationBand.high),
    fixture('one high color', const ['E102'], _CalibrationBand.mid),
    fixture('one high nitrite', const ['E250'], _CalibrationBand.mid),
    fixture('one high sweetener', const ['E951'], _CalibrationBand.mid),
    fixture('two distinct low additives', const [
      'E412',
      'E415',
    ], _CalibrationBand.veryHigh),
    fixture('three distinct low additives', const [
      'E322',
      'E412',
      'E415',
    ], _CalibrationBand.veryHigh),
    fixture('two medium preservatives', const [
      'E200',
      'E202',
    ], _CalibrationBand.high),
    fixture('two medium antioxidants', const [
      'E319',
      'E320',
    ], _CalibrationBand.high),
    fixture('three medium preservatives', const [
      'E200',
      'E202',
      'E210',
    ], _CalibrationBand.mid),
    fixture('five medium additives', const [
      'E200',
      'E202',
      'E210',
      'E211',
      'E321',
    ], _CalibrationBand.mid),
    fixture('ten medium additives', const [
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
    ], _CalibrationBand.mid),
    fixture('two high colors', const ['E102', 'E129'], _CalibrationBand.mid),
    fixture('reviewed nitrite and nitrate pair', const [
      'E250',
      'E251',
    ], _CalibrationBand.mid),
    fixture('three high colors', const [
      'E102',
      'E110',
      'E129',
    ], _CalibrationBand.low),
    fixture('four high colors', const [
      'E102',
      'E110',
      'E129',
      'E133',
    ], _CalibrationBand.low),
    fixture('seven reviewed high additives', const [
      'E951',
      'E133',
      'E102',
      'E129',
      'E110',
      'E250',
      'E251',
    ], _CalibrationBand.veryLow),
    fixture('low and medium', const ['E322', 'E200'], _CalibrationBand.high),
    fixture('low and high', const ['E322', 'E102'], _CalibrationBand.mid),
    fixture('medium and high', const ['E200', 'E102'], _CalibrationBand.mid),
    fixture('low medium and high', const [
      'E322',
      'E200',
      'E102',
    ], _CalibrationBand.mid),
    fixture('many mixed reviewed additives', const [
      'E322',
      'E412',
      'E415',
      'E200',
      'E202',
      'E210',
      'E211',
      'E321',
      'E102',
      'E110',
      'E129',
    ], _CalibrationBand.veryLow),
    _CalibrationFixture(
      name: 'duplicate E-code name and alias',
      assessment: duplicateAssessment('E250'),
      expectedBand: _CalibrationBand.mid,
    ),
    fixture('different preservatives in same group', const [
      'E200',
      'E202',
    ], _CalibrationBand.high),
    fixture('unknown E249 only', const ['E249'], _CalibrationBand.veryHigh),
    fixture('unknown E252 only', const ['E252'], _CalibrationBand.veryHigh),
    _CalibrationFixture(
      name: 'review-required fuzzy only',
      assessment: fuzzyAssessment('E202'),
      expectedBand: _CalibrationBand.veryHigh,
    ),
    _CalibrationFixture(
      name: 'conflicted canonical item only',
      assessment: conflictingAssessment(),
      expectedBand: _CalibrationBand.veryHigh,
    ),
    fixture('eligible medium plus unknown gap', const [
      'E202',
      'E249',
    ], _CalibrationBand.high),
    fixture(
      'beverage NNS overlap only',
      const ['E955'],
      _CalibrationBand.veryHigh,
      category: ScoringCategory.beverage,
    ),
    fixture(
      'beverage NNS overlap and unrelated medium',
      const ['E955', 'E202'],
      _CalibrationBand.high,
      category: ScoringCategory.beverage,
    ),
    fixture(
      'beverage NNS overlap and unrelated high',
      const ['E955', 'E102'],
      _CalibrationBand.mid,
      category: ScoringCategory.beverage,
    ),
    fixture('same sweetener outside beverage', const [
      'E955',
    ], _CalibrationBand.high),
    fixture(
      'beverage polyol remains penalized',
      const ['E965'],
      _CalibrationBand.high,
      category: ScoringCategory.beverage,
    ),
    fixture('four reviewed preservatives', const [
      'E200',
      'E202',
      'E210',
      'E211',
    ], _CalibrationBand.mid),
    fixture('three reviewed antioxidants', const [
      'E319',
      'E320',
      'E321',
    ], _CalibrationBand.mid),
    fixture('three non-beverage sweeteners', const [
      'E950',
      'E954',
      'E955',
    ], _CalibrationBand.mid),
    _CalibrationFixture(
      name: 'ordinary ingredient only',
      assessment: ordinaryAssessment(),
      expectedBand: _CalibrationBand.veryHigh,
    ),
    _CalibrationFixture(
      name: 'unresolved token only',
      assessment: unresolvedAssessment(),
      expectedBand: _CalibrationBand.veryHigh,
    ),
    fixture('unknown NNS gap E957', const ['E957'], _CalibrationBand.veryHigh),
    fixture('unknown NNS gap E959', const ['E959'], _CalibrationBand.veryHigh),
    fixture('unknown NNS gap E960', const ['E960'], _CalibrationBand.veryHigh),
    fixture('unknown NNS gap E961', const ['E961'], _CalibrationBand.veryHigh),
    fixture('unknown NNS gap E962', const ['E962'], _CalibrationBand.veryHigh),
    fixture('unknown NNS gap E969', const ['E969'], _CalibrationBand.veryHigh),
  ];

  test('INTERNAL CALIBRATION FIXTURE set contains exactly 50 cases', () {
    expect(fixtures, hasLength(50));
  });

  for (final calibration in fixtures) {
    test('INTERNAL CALIBRATION FIXTURE ${calibration.name}', () {
      final result = transformer.transform(calibration.assessment);

      expect(result.qualityScore, inInclusiveRange(0, 100));
      expect(
        _bandFor(result.qualityScore),
        calibration.expectedBand,
        reason:
            '${calibration.name}: quality=${result.qualityScore}, '
            'penalty=${result.totalPenalty}',
      );
    });
  }
}
