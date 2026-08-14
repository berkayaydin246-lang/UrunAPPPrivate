import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

import 'support/etiketly_score_test_support.dart';

class _EndToEndFixture {
  const _EndToEndFixture({
    required this.name,
    required this.category,
    this.additiveCodes = const [],
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

  final String name;
  final ScoringCategory category;
  final List<String> additiveCodes;
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
}

const _fixtures = <_EndToEndFixture>[
  _EndToEndFixture(
    name: 'plain water',
    category: ScoringCategory.beverage,
    plainWater: true,
  ),
  _EndToEndFixture(
    name: 'plain oats',
    category: ScoringCategory.generalFood,
    energyKj: 1500,
    saturatedFat: 1.2,
    sugars: 1,
    salt: 0.01,
    protein: 13,
    fiber: 10,
  ),
  _EndToEndFixture(
    name: 'whole-grain bread',
    category: ScoringCategory.generalFood,
    energyKj: 1000,
    saturatedFat: 0.5,
    sugars: 3,
    salt: 1,
    protein: 9,
    fiber: 7,
  ),
  _EndToEndFixture(
    name: 'white bread',
    category: ScoringCategory.generalFood,
    energyKj: 1100,
    saturatedFat: 0.5,
    sugars: 4,
    salt: 1.2,
    protein: 8,
    fiber: 2,
  ),
  _EndToEndFixture(
    name: 'plain yogurt',
    category: ScoringCategory.generalFood,
    energyKj: 250,
    totalFat: 4,
    saturatedFat: 2,
    sugars: 5,
    salt: 0.1,
    protein: 4.5,
  ),
  _EndToEndFixture(
    name: 'sweetened yogurt',
    category: ScoringCategory.generalFood,
    energyKj: 450,
    totalFat: 4,
    saturatedFat: 2,
    sugars: 13,
    salt: 0.1,
    protein: 4.5,
    additiveCodes: ['E202'],
  ),
  _EndToEndFixture(
    name: 'high-sugar cereal',
    category: ScoringCategory.generalFood,
    energyKj: 1600,
    totalFat: 8,
    saturatedFat: 2,
    sugars: 35,
    salt: 0.5,
    protein: 8,
    fiber: 3,
  ),
  _EndToEndFixture(
    name: 'chocolate biscuit',
    category: ScoringCategory.generalFood,
    energyKj: 2100,
    totalFat: 25,
    saturatedFat: 15,
    sugars: 35,
    salt: 0.8,
    protein: 5,
    fiber: 2,
    additiveCodes: ['E322', 'E471'],
  ),
  _EndToEndFixture(
    name: 'chips',
    category: ScoringCategory.generalFood,
    energyKj: 2200,
    totalFat: 35,
    saturatedFat: 10,
    sugars: 2,
    salt: 2,
    protein: 6,
    fiber: 3.5,
    additiveCodes: ['E621'],
  ),
  _EndToEndFixture(
    name: 'regular cola',
    category: ScoringCategory.beverage,
    energyKj: 180,
    sugars: 10.6,
  ),
  _EndToEndFixture(
    name: 'zero-sugar cola with NNS',
    category: ScoringCategory.beverage,
    energyKj: 2,
    nnsPresent: true,
    additiveCodes: ['E955'],
  ),
  _EndToEndFixture(
    name: 'fruit juice',
    category: ScoringCategory.beverage,
    energyKj: 190,
    sugars: 9,
    fvl: 100,
  ),
  _EndToEndFixture(
    name: 'fresh lower-salt cheese',
    category: ScoringCategory.cheese,
    energyKj: 700,
    totalFat: 10,
    saturatedFat: 4,
    sugars: 3,
    salt: 0.4,
    protein: 12,
  ),
  _EndToEndFixture(
    name: 'processed salty cheese',
    category: ScoringCategory.cheese,
    energyKj: 1300,
    totalFat: 25,
    saturatedFat: 15,
    sugars: 4,
    salt: 3,
    protein: 12,
    additiveCodes: ['E202', 'E471'],
  ),
  _EndToEndFixture(
    name: 'lean red meat',
    category: ScoringCategory.redMeat,
    energyKj: 600,
    totalFat: 6,
    saturatedFat: 2,
    salt: 0.2,
    protein: 25,
  ),
  _EndToEndFixture(
    name: 'processed salty red meat',
    category: ScoringCategory.redMeat,
    energyKj: 1100,
    totalFat: 15,
    saturatedFat: 7,
    salt: 2,
    protein: 20,
    additiveCodes: ['E250'],
  ),
  _EndToEndFixture(
    name: 'olive oil',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 100,
    saturatedFat: 14,
    fvl: 100,
  ),
  _EndToEndFixture(
    name: 'butter',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 82,
    saturatedFat: 52,
  ),
  _EndToEndFixture(
    name: 'plain nuts',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 50,
    saturatedFat: 5,
    sugars: 5,
    protein: 20,
    fiber: 10,
    fvl: 100,
  ),
  _EndToEndFixture(
    name: 'one preservative',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 1,
    sugars: 5,
    salt: 0.5,
    protein: 5,
    fiber: 3,
    additiveCodes: ['E202'],
  ),
  _EndToEndFixture(
    name: 'one reviewed color',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 1,
    sugars: 5,
    salt: 0.5,
    protein: 5,
    fiber: 3,
    additiveCodes: ['E102'],
  ),
  _EndToEndFixture(
    name: 'one antioxidant',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 1,
    sugars: 5,
    salt: 0.5,
    protein: 5,
    fiber: 3,
    additiveCodes: ['E321'],
  ),
  _EndToEndFixture(
    name: 'one reviewed low additive',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 1,
    sugars: 5,
    salt: 0.5,
    protein: 5,
    fiber: 3,
    additiveCodes: ['E322'],
  ),
  _EndToEndFixture(
    name: 'two medium additives',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 1,
    sugars: 5,
    salt: 0.5,
    protein: 5,
    fiber: 3,
    additiveCodes: ['E211', 'E321'],
  ),
  _EndToEndFixture(
    name: 'two high additives',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 1,
    sugars: 5,
    salt: 0.5,
    protein: 5,
    fiber: 3,
    additiveCodes: ['E102', 'E110'],
  ),
  _EndToEndFixture(
    name: 'mixed additive profile',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 1,
    sugars: 5,
    salt: 0.5,
    protein: 5,
    fiber: 3,
    additiveCodes: ['E322', 'E211', 'E102'],
  ),
  _EndToEndFixture(
    name: 'simple additive-free food',
    category: ScoringCategory.generalFood,
    energyKj: 650,
    saturatedFat: 1,
    sugars: 4,
    salt: 0.4,
    protein: 7,
    fiber: 4,
  ),
  _EndToEndFixture(
    name: 'low-salt legumes',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 0.2,
    sugars: 2,
    salt: 0.1,
    protein: 8,
    fiber: 6,
    fvl: 80,
  ),
  _EndToEndFixture(
    name: 'salty canned legumes',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    saturatedFat: 0.2,
    sugars: 2,
    salt: 2.2,
    protein: 8,
    fiber: 6,
    fvl: 80,
    additiveCodes: ['E202'],
  ),
  _EndToEndFixture(
    name: 'high-fiber cereal',
    category: ScoringCategory.generalFood,
    energyKj: 1500,
    saturatedFat: 1,
    sugars: 8,
    salt: 0.3,
    protein: 10,
    fiber: 9,
  ),
  _EndToEndFixture(
    name: 'tomato vegetable product',
    category: ScoringCategory.generalFood,
    energyKj: 120,
    sugars: 4,
    salt: 0.6,
    protein: 1,
    fiber: 2,
    fvl: 90,
  ),
  _EndToEndFixture(
    name: 'low-salt vegetable soup',
    category: ScoringCategory.generalFood,
    energyKj: 150,
    saturatedFat: 0.5,
    sugars: 3,
    salt: 0.5,
    protein: 2,
    fiber: 2,
    fvl: 70,
  ),
  _EndToEndFixture(
    name: 'sweet chocolate spread',
    category: ScoringCategory.generalFood,
    energyKj: 2200,
    totalFat: 35,
    saturatedFat: 10,
    sugars: 55,
    salt: 0.2,
    additiveCodes: ['E322', 'E471'],
  ),
  _EndToEndFixture(
    name: 'hard cheese',
    category: ScoringCategory.cheese,
    energyKj: 1700,
    totalFat: 30,
    saturatedFat: 20,
    salt: 1.8,
    protein: 25,
  ),
  _EndToEndFixture(
    name: 'high-salt processed meat',
    category: ScoringCategory.redMeat,
    energyKj: 1600,
    totalFat: 25,
    saturatedFat: 12,
    salt: 3,
    protein: 18,
    additiveCodes: ['E250', 'E251'],
  ),
  _EndToEndFixture(
    name: 'canola-like oil',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 100,
    saturatedFat: 7,
  ),
  _EndToEndFixture(
    name: 'coconut-oil-like fat',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 100,
    saturatedFat: 85,
  ),
  _EndToEndFixture(
    name: 'sweetened milk drink',
    category: ScoringCategory.beverage,
    energyKj: 330,
    totalFat: 4,
    saturatedFat: 2,
    sugars: 9,
    salt: 0.2,
    protein: 3,
    additiveCodes: ['E407'],
  ),
  _EndToEndFixture(
    name: 'low-sugar beverage',
    category: ScoringCategory.beverage,
    energyKj: 20,
    sugars: 0.3,
    salt: 0.05,
  ),
  _EndToEndFixture(
    name: 'energy drink with NNS and preservative',
    category: ScoringCategory.beverage,
    energyKj: 190,
    sugars: 11,
    nnsPresent: true,
    additiveCodes: ['E955', 'E202'],
  ),
];

EtiketlyScorePipelineResult _run(_EndToEndFixture fixture) {
  return runEtiketlyScorePipeline(
    nutritionFixtureInput(
      category: fixture.category,
      energyKj: fixture.energyKj,
      totalFat: fixture.totalFat,
      saturatedFat: fixture.saturatedFat,
      sugars: fixture.sugars,
      salt: fixture.salt,
      protein: fixture.protein,
      fiber: fixture.fiber,
      fvl: fixture.fvl,
      nnsPresent: fixture.nnsPresent,
      plainWater: fixture.plainWater,
    ),
    additiveCodes: fixture.additiveCodes,
  );
}

void main() {
  test('END-TO-END FINAL-SCORE fixture set contains exactly 40 cases', () {
    expect(_fixtures, hasLength(40));
  });

  for (final fixture in _fixtures) {
    test('END-TO-END FINAL-SCORE ${fixture.name}', () {
      final result = _run(fixture);

      expect(result.readiness.isCalculable, isTrue);
      expect(result.scoreResult.status, EtiketlyScoreStatus.calculated);
      expect(result.scoreResult.score, inInclusiveRange(0, 100));
      expect(
        result.scoreResult.score,
        closeTo(
          result.scoreResult.nutritionContribution! +
              result.scoreResult.additiveContribution!,
          0.0000001,
        ),
      );
    });
  }

  test(
    'archetype directions remain intelligible through the full pipeline',
    () {
      final results = {
        for (final fixture in _fixtures) fixture.name: _run(fixture),
      };

      double score(String name) => results[name]!.scoreResult.score!;

      expect(score('plain water'), greaterThan(score('regular cola')));
      expect(score('plain oats'), greaterThan(score('high-sugar cereal')));
      expect(score('olive oil'), greaterThan(score('butter')));
      expect(
        score('fresh lower-salt cheese'),
        greaterThan(score('processed salty cheese')),
      );
      expect(
        score('simple additive-free food'),
        greaterThan(score('one preservative')),
      );
      expect(
        score('one preservative'),
        greaterThan(score('one reviewed color')),
      );
    },
  );

  test('same nutrition worsens from no concern to medium to high', () {
    final input = nutritionFixtureInput(
      category: ScoringCategory.generalFood,
      energyKj: 500,
      saturatedFat: 1,
      sugars: 5,
      salt: 0.5,
      protein: 5,
      fiber: 3,
    );
    final none = runEtiketlyScorePipeline(input).scoreResult.score!;
    final medium = runEtiketlyScorePipeline(
      input,
      additiveCodes: const ['E202'],
    ).scoreResult.score!;
    final high = runEtiketlyScorePipeline(
      input,
      additiveCodes: const ['E102'],
    ).scoreResult.score!;

    expect(none, greaterThan(medium));
    expect(medium, greaterThan(high));
  });

  test('same additive profile preserves better nutrition direction', () {
    final better = runEtiketlyScorePipeline(
      nutritionFixtureInput(
        category: ScoringCategory.generalFood,
        energyKj: 500,
        saturatedFat: 1,
        sugars: 4,
        salt: 0.3,
        protein: 8,
        fiber: 6,
      ),
      additiveCodes: const ['E202'],
    );
    final worse = runEtiketlyScorePipeline(
      nutritionFixtureInput(
        category: ScoringCategory.generalFood,
        energyKj: 2000,
        totalFat: 30,
        saturatedFat: 15,
        sugars: 35,
        salt: 2,
        protein: 4,
        fiber: 1,
      ),
      additiveCodes: const ['E202'],
    );

    expect(better.scoreResult.score, greaterThan(worse.scoreResult.score!));
  });

  test('beverage NNS overlap does not add a second final penalty', () {
    final zeroCola = _run(
      _fixtures.singleWhere(
        (fixture) => fixture.name == 'zero-sugar cola with NNS',
      ),
    );

    expect(zeroCola.additiveQuality.qualityScore, 100);
    expect(zeroCola.additiveQuality.excludedForNutritionOverlapCount, 1);
    expect(
      zeroCola.scoreResult.explanationCodes,
      contains(EtiketlyScoreExplanationCode.beverageNnsHandledInNutrition),
    );
  });
}
