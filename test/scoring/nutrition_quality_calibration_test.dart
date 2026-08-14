import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/validated_nutrition_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_raw_score_calculator.dart';

import 'scoring_test_fixtures.dart';

enum _ExpectedNutritionDirection { veryHigh, high, mid, low, veryLow }

class _CalibrationFixture {
  final String name;
  final ScoringCategory category;
  final _ExpectedNutritionDirection expected;
  final double energyKj;
  final double totalFat;
  final double saturatedFat;
  final double sugars;
  final double salt;
  final double protein;
  final double fiber;
  final double fvl;
  final bool nnsPresent;
  final bool plainWater;

  const _CalibrationFixture({
    required this.name,
    required this.category,
    required this.expected,
    this.energyKj = 0,
    this.totalFat = 100,
    this.saturatedFat = 0,
    this.sugars = 0,
    this.salt = 0,
    this.protein = 0,
    this.fiber = 0,
    this.fvl = 0,
    this.nnsPresent = false,
    this.plainWater = false,
  });
}

const _fixtures = <_CalibrationFixture>[
  _CalibrationFixture(
    name: 'plain still water',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.veryHigh,
    plainWater: true,
  ),
  _CalibrationFixture(
    name: 'plain sparkling mineral water',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.veryHigh,
    plainWater: true,
  ),
  _CalibrationFixture(
    name: 'low-sugar beverage',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.high,
    energyKj: 20,
    sugars: 0.3,
    salt: 0.05,
  ),
  _CalibrationFixture(
    name: 'regular cola',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.veryLow,
    energyKj: 180,
    sugars: 10.6,
  ),
  _CalibrationFixture(
    name: 'zero-sugar cola with NNS',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.mid,
    energyKj: 2,
    nnsPresent: true,
  ),
  _CalibrationFixture(
    name: 'energy drink',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.veryLow,
    energyKj: 190,
    sugars: 11,
    nnsPresent: true,
  ),
  _CalibrationFixture(
    name: '100 percent fruit juice',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.mid,
    energyKj: 190,
    sugars: 9,
    fvl: 100,
  ),
  _CalibrationFixture(
    name: 'sweetened fruit drink',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.veryLow,
    energyKj: 210,
    sugars: 12,
    fvl: 20,
  ),
  _CalibrationFixture(
    name: 'plain milk',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.high,
    energyKj: 260,
    saturatedFat: 2,
    sugars: 4.8,
    salt: 0.1,
    protein: 3.4,
  ),
  _CalibrationFixture(
    name: 'sweetened milk drink',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.low,
    energyKj: 330,
    saturatedFat: 2,
    sugars: 9,
    salt: 0.2,
    protein: 3,
  ),
  _CalibrationFixture(
    name: 'plant-based drink',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.mid,
    energyKj: 180,
    saturatedFat: 0.5,
    sugars: 4,
    salt: 0.15,
    protein: 1,
    fiber: 1,
  ),
  _CalibrationFixture(
    name: 'unsweetened plant-based drink',
    category: ScoringCategory.beverage,
    expected: _ExpectedNutritionDirection.high,
    energyKj: 80,
    saturatedFat: 0.3,
    sugars: 0.3,
    salt: 0.1,
    protein: 1,
    fiber: 0.5,
  ),
  _CalibrationFixture(
    name: 'plain oats',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryHigh,
    energyKj: 1500,
    saturatedFat: 1.2,
    sugars: 1,
    salt: 0.01,
    protein: 13,
    fiber: 10,
  ),
  _CalibrationFixture(
    name: 'whole-grain high-fiber bread',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryHigh,
    energyKj: 1000,
    saturatedFat: 0.5,
    sugars: 3,
    salt: 1,
    protein: 9,
    fiber: 7,
  ),
  _CalibrationFixture(
    name: 'white bread',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.mid,
    energyKj: 1100,
    saturatedFat: 0.5,
    sugars: 4,
    salt: 1.2,
    protein: 8,
    fiber: 2,
  ),
  _CalibrationFixture(
    name: 'plain yogurt',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.high,
    energyKj: 250,
    saturatedFat: 2,
    sugars: 5,
    salt: 0.1,
    protein: 4.5,
  ),
  _CalibrationFixture(
    name: 'sweetened yogurt',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.mid,
    energyKj: 450,
    saturatedFat: 2,
    sugars: 13,
    salt: 0.1,
    protein: 4.5,
  ),
  _CalibrationFixture(
    name: 'low-salt legumes',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryHigh,
    energyKj: 500,
    saturatedFat: 0.2,
    sugars: 2,
    salt: 0.1,
    protein: 8,
    fiber: 6,
    fvl: 80,
  ),
  _CalibrationFixture(
    name: 'salty canned legumes',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.mid,
    energyKj: 500,
    saturatedFat: 0.2,
    sugars: 2,
    salt: 2.2,
    protein: 8,
    fiber: 6,
    fvl: 80,
  ),
  _CalibrationFixture(
    name: 'high-fiber cereal',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryHigh,
    energyKj: 1500,
    saturatedFat: 1,
    sugars: 8,
    salt: 0.3,
    protein: 10,
    fiber: 9,
  ),
  _CalibrationFixture(
    name: 'high-sugar cereal',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.low,
    energyKj: 1600,
    saturatedFat: 2,
    sugars: 35,
    salt: 0.5,
    protein: 8,
    fiber: 3,
  ),
  _CalibrationFixture(
    name: 'chocolate biscuit',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryLow,
    energyKj: 2100,
    totalFat: 25,
    saturatedFat: 15,
    sugars: 35,
    salt: 0.8,
    protein: 5,
    fiber: 2,
  ),
  _CalibrationFixture(
    name: 'chips',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryLow,
    energyKj: 2200,
    totalFat: 35,
    saturatedFat: 10,
    sugars: 2,
    salt: 2,
    protein: 6,
    fiber: 3.5,
  ),
  _CalibrationFixture(
    name: 'tomato vegetable product',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryHigh,
    energyKj: 120,
    sugars: 4,
    salt: 0.6,
    protein: 1,
    fiber: 2,
    fvl: 90,
  ),
  _CalibrationFixture(
    name: 'low-salt vegetable soup',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryHigh,
    energyKj: 150,
    saturatedFat: 0.5,
    sugars: 3,
    salt: 0.5,
    protein: 2,
    fiber: 2,
    fvl: 70,
  ),
  _CalibrationFixture(
    name: 'sweet chocolate spread',
    category: ScoringCategory.generalFood,
    expected: _ExpectedNutritionDirection.veryLow,
    energyKj: 2200,
    totalFat: 35,
    saturatedFat: 10,
    sugars: 55,
    salt: 0.2,
  ),
  _CalibrationFixture(
    name: 'fresh lower-salt cheese',
    category: ScoringCategory.cheese,
    expected: _ExpectedNutritionDirection.high,
    energyKj: 700,
    totalFat: 10,
    saturatedFat: 4,
    sugars: 3,
    salt: 0.4,
    protein: 12,
  ),
  _CalibrationFixture(
    name: 'hard cheese',
    category: ScoringCategory.cheese,
    expected: _ExpectedNutritionDirection.low,
    energyKj: 1700,
    totalFat: 30,
    saturatedFat: 20,
    salt: 1.8,
    protein: 25,
  ),
  _CalibrationFixture(
    name: 'processed salty cheese',
    category: ScoringCategory.cheese,
    expected: _ExpectedNutritionDirection.veryLow,
    energyKj: 1300,
    totalFat: 25,
    saturatedFat: 15,
    sugars: 4,
    salt: 3,
    protein: 12,
  ),
  _CalibrationFixture(
    name: 'lean fresh red meat',
    category: ScoringCategory.redMeat,
    expected: _ExpectedNutritionDirection.veryHigh,
    energyKj: 600,
    totalFat: 6,
    saturatedFat: 2,
    salt: 0.2,
    protein: 25,
  ),
  _CalibrationFixture(
    name: 'salted processed red meat',
    category: ScoringCategory.redMeat,
    expected: _ExpectedNutritionDirection.low,
    energyKj: 1100,
    totalFat: 15,
    saturatedFat: 7,
    salt: 2,
    protein: 20,
  ),
  _CalibrationFixture(
    name: 'high-salt high-saturated processed meat',
    category: ScoringCategory.redMeat,
    expected: _ExpectedNutritionDirection.veryLow,
    energyKj: 1600,
    totalFat: 25,
    saturatedFat: 12,
    salt: 3,
    protein: 18,
  ),
  _CalibrationFixture(
    name: 'olive oil',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.high,
    totalFat: 100,
    saturatedFat: 14,
    fvl: 100,
  ),
  _CalibrationFixture(
    name: 'rapeseed canola-like oil',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.high,
    totalFat: 100,
    saturatedFat: 7,
  ),
  _CalibrationFixture(
    name: 'lower-saturated spread',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.mid,
    totalFat: 60,
    saturatedFat: 12,
    salt: 0.5,
  ),
  _CalibrationFixture(
    name: 'butter',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.veryLow,
    totalFat: 82,
    saturatedFat: 51,
    salt: 0.1,
  ),
  _CalibrationFixture(
    name: 'coconut oil',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.veryLow,
    totalFat: 100,
    saturatedFat: 87,
  ),
  _CalibrationFixture(
    name: 'unsalted nuts',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.veryHigh,
    totalFat: 50,
    saturatedFat: 5,
    sugars: 4,
    protein: 20,
    fiber: 8,
  ),
  _CalibrationFixture(
    name: 'salted nuts',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.mid,
    totalFat: 50,
    saturatedFat: 5,
    sugars: 4,
    salt: 1.2,
    protein: 20,
    fiber: 8,
  ),
  _CalibrationFixture(
    name: 'tahini nut-seed product',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.veryHigh,
    totalFat: 55,
    saturatedFat: 8,
    sugars: 1,
    salt: 0.1,
    protein: 17,
    fiber: 9,
  ),
  _CalibrationFixture(
    name: 'salted tahini nut-seed product',
    category: ScoringCategory.fatsOilsNutsSeeds,
    expected: _ExpectedNutritionDirection.mid,
    totalFat: 55,
    saturatedFat: 8,
    sugars: 1,
    salt: 1.5,
    protein: 17,
    fiber: 9,
  ),
];

void main() {
  const rawCalculator = NutritionRawScoreCalculator();
  const transformer = NutritionQualityTransformer.v1();

  NutritionRawScoreResult rawFor(_CalibrationFixture fixture) {
    final input = completeInput(
      category: fixture.category,
      nutrition: completeNutrition(
        energyKj: verifiedValue(fixture.energyKj),
        totalFat: verifiedValue(fixture.totalFat),
        saturatedFat: verifiedValue(fixture.saturatedFat),
        sugars: verifiedValue(fixture.sugars),
        salt: verifiedValue(fixture.salt),
        protein: verifiedValue(fixture.protein),
        fiber: verifiedValue(fixture.fiber),
      ),
      fvlEvidence: CompositionPercentageEvidence.known(
        fixture.fvl,
        provenance: EvidenceProvenance.adminVerified,
        verification: EvidenceVerification.verified,
      ),
      nnsEvidence: fixture.nnsPresent
          ? const PresenceEvidence.present(
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            )
          : const PresenceEvidence.absent(
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            ),
      classificationFacts: ScoringClassificationFacts(
        isPlainWater: fixture.plainWater ? verifiedValue(true) : null,
      ),
    );
    return rawCalculator.calculate(
      ValidatedNutritionScoringInput.validate(input),
    );
  }

  test('INTERNAL CALIBRATION FIXTURE selected set has 41 cases', () {
    expect(_fixtures.length, 41);
  });

  test('INTERNAL CALIBRATION FIXTURE v1 mapping stays preserved', () {
    for (final fixture in _fixtures) {
      final raw = rawFor(fixture);
      final quality = transformer.transform(raw).qualityScore;
      expect(
        _directionFor(quality),
        fixture.expected,
        reason:
            '${fixture.name}: raw=${raw.rawScore}, quality=$quality, '
            'category=${fixture.category.name}',
      );
    }
  });

  test('production cross-category ordering remains intelligible', () {
    double quality(String name) => transformer
        .transform(
          rawFor(_fixtures.singleWhere((fixture) => fixture.name == name)),
        )
        .qualityScore;

    expect(quality('plain still water'), greaterThan(quality('regular cola')));
    expect(quality('olive oil'), greaterThan(quality('butter')));
    expect(quality('plain oats'), greaterThan(quality('high-sugar cereal')));
    expect(
      quality('fresh lower-salt cheese'),
      greaterThan(quality('processed salty cheese')),
    );
  });

  test('one-factor sensitivity follows raw methodology direction', () {
    ({int raw, double quality}) evaluate(_CalibrationFixture fixture) {
      final rawResult = rawFor(fixture);
      return (
        raw: rawResult.rawScore!,
        quality: transformer.transform(rawResult).qualityScore,
      );
    }

    void expectAdverseChange(
      _CalibrationFixture baseline,
      _CalibrationFixture changed,
    ) {
      final before = evaluate(baseline);
      final after = evaluate(changed);
      expect(after.raw, greaterThan(before.raw));
      expect(after.quality, lessThan(before.quality));
    }

    void expectFavorableChange(
      _CalibrationFixture baseline,
      _CalibrationFixture changed,
    ) {
      final before = evaluate(baseline);
      final after = evaluate(changed);
      expect(after.raw, lessThan(before.raw));
      expect(after.quality, greaterThan(before.quality));
    }

    expectAdverseChange(
      const _CalibrationFixture(
        name: 'sugar baseline',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.high,
        energyKj: 500,
        sugars: 3,
      ),
      const _CalibrationFixture(
        name: 'sugar increased',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.mid,
        energyKj: 500,
        sugars: 10.1,
      ),
    );
    expectAdverseChange(
      const _CalibrationFixture(
        name: 'salt baseline',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.high,
        salt: 0.2,
      ),
      const _CalibrationFixture(
        name: 'salt increased',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.high,
        salt: 0.6,
      ),
    );
    expectAdverseChange(
      const _CalibrationFixture(
        name: 'saturated fat baseline',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.high,
        saturatedFat: 1,
      ),
      const _CalibrationFixture(
        name: 'saturated fat increased',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.high,
        saturatedFat: 3,
      ),
    );
    expectFavorableChange(
      const _CalibrationFixture(
        name: 'fiber baseline',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.high,
        energyKj: 500,
        fiber: 3,
      ),
      const _CalibrationFixture(
        name: 'fiber increased',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.veryHigh,
        energyKj: 500,
        fiber: 5.3,
      ),
    );
    expectFavorableChange(
      const _CalibrationFixture(
        name: 'protein baseline',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.high,
        energyKj: 500,
        protein: 2.4,
      ),
      const _CalibrationFixture(
        name: 'protein increased',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.veryHigh,
        energyKj: 500,
        protein: 9.7,
      ),
    );
    expectFavorableChange(
      const _CalibrationFixture(
        name: 'FVL baseline',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.high,
        energyKj: 500,
        fvl: 40,
      ),
      const _CalibrationFixture(
        name: 'FVL increased',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.veryHigh,
        energyKj: 500,
        fvl: 81,
      ),
    );
    expectAdverseChange(
      const _CalibrationFixture(
        name: 'NNS absent',
        category: ScoringCategory.beverage,
        expected: _ExpectedNutritionDirection.high,
      ),
      const _CalibrationFixture(
        name: 'NNS present',
        category: ScoringCategory.beverage,
        expected: _ExpectedNutritionDirection.mid,
        nnsPresent: true,
      ),
    );
  });

  test('official component plateaus retain identical nutrition quality', () {
    final lowerSugar = rawFor(
      const _CalibrationFixture(
        name: 'plateau lower sugar',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.veryHigh,
        sugars: 1,
      ),
    );
    final upperSugar = rawFor(
      const _CalibrationFixture(
        name: 'plateau upper sugar',
        category: ScoringCategory.generalFood,
        expected: _ExpectedNutritionDirection.veryHigh,
        sugars: 3.4,
      ),
    );

    expect(upperSugar.rawScore, lowerSugar.rawScore);
    expect(
      transformer.transform(upperSugar).qualityScore,
      transformer.transform(lowerSugar).qualityScore,
    );
  });
}

_ExpectedNutritionDirection _directionFor(double quality) {
  if (quality > 85) return _ExpectedNutritionDirection.veryHigh;
  if (quality >= 70) return _ExpectedNutritionDirection.high;
  if (quality >= 45) return _ExpectedNutritionDirection.mid;
  if (quality >= 20) return _ExpectedNutritionDirection.low;
  return _ExpectedNutritionDirection.veryLow;
}
