import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/validated_nutrition_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_raw_score_calculator.dart';

import 'scoring_test_fixtures.dart';

void main() {
  const calculator = NutritionRawScoreCalculator();

  NutritionRawScoreResult score({
    required ScoringCategory category,
    double energyKj = 0,
    double totalFat = 100,
    double saturatedFat = 0,
    double sugars = 0,
    double salt = 0,
    double protein = 0,
    double fiber = 0,
    double fvl = 0,
    bool nnsPresent = false,
    bool plainWater = false,
  }) {
    final input = completeInput(
      category: category,
      nutrition: completeNutrition(
        energyKj: verifiedValue(energyKj),
        totalFat: verifiedValue(totalFat),
        saturatedFat: verifiedValue(saturatedFat),
        sugars: verifiedValue(sugars),
        salt: verifiedValue(salt),
        protein: verifiedValue(protein),
        fiber: verifiedValue(fiber),
      ),
      fvlEvidence: CompositionPercentageEvidence.known(
        fvl,
        provenance: EvidenceProvenance.adminVerified,
        verification: EvidenceVerification.verified,
      ),
      nnsEvidence: nnsPresent
          ? const PresenceEvidence.present(
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            )
          : const PresenceEvidence.absent(
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            ),
      classificationFacts: ScoringClassificationFacts(
        isPlainWater: plainWater ? verifiedValue(true) : null,
      ),
    );
    return calculator.calculate(ValidatedNutritionScoringInput.validate(input));
  }

  group('validated calculation boundary', () {
    test('ready input produces a closed validated model', () {
      final validated = ValidatedNutritionScoringInput.validate(
        completeInput(),
      );

      expect(validated.category, ScoringCategory.generalFood);
      expect(validated.nutritionBasis, NutritionBasis.per100g);
      expect(validated.salt, 0.4);
    });

    test('missing mandatory evidence is rejected before calculation', () {
      expect(
        () => ValidatedNutritionScoringInput.validate(
          completeInput(nutrition: completeNutrition(includeEnergyKj: false)),
        ),
        throwsA(isA<NutritionScoringInputValidationException>()),
      );
    });

    test('wrong nutrition basis is rejected', () {
      expect(
        () => ValidatedNutritionScoringInput.validate(
          completeInput(
            category: ScoringCategory.beverage,
            basis: NutritionBasis.per100g,
          ),
        ),
        throwsA(isA<NutritionScoringInputValidationException>()),
      );
    });

    test('unknown and out-of-scope categories are rejected', () {
      for (final evidence in [
        ScoringCategoryEvidence.unknown(),
        explicitCategory(ScoringCategory.outOfScope),
      ]) {
        expect(
          () => ValidatedNutritionScoringInput.validate(
            completeInput(categoryEvidence: evidence),
          ),
          throwsA(isA<NutritionScoringInputValidationException>()),
        );
      }
    });

    test('negative, NaN, and infinite nutrients are rejected', () {
      for (final invalid in [-0.1, double.nan, double.infinity]) {
        expect(
          () => ValidatedNutritionScoringInput.validate(
            completeInput(
              nutrition: completeNutrition(sugars: verifiedValue(invalid)),
            ),
          ),
          throwsA(isA<NutritionScoringInputValidationException>()),
        );
      }
    });

    test('FVL model rejects values outside zero through one hundred', () {
      expect(
        () => CompositionPercentageEvidence.known(
          100.1,
          provenance: EvidenceProvenance.adminVerified,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('unknown beverage NNS is rejected', () {
      expect(
        () => ValidatedNutritionScoringInput.validate(
          completeInput(
            category: ScoringCategory.beverage,
            nnsEvidence: const PresenceEvidence.unknown(),
          ),
        ),
        throwsA(isA<NutritionScoringInputValidationException>()),
      );
    });

    test('fat input rejects zero total fat and impossible fat ratio', () {
      expect(
        () => ValidatedNutritionScoringInput.validate(
          completeInput(
            category: ScoringCategory.fatsOilsNutsSeeds,
            nutrition: completeNutrition(
              totalFat: verifiedValue(0),
              saturatedFat: verifiedValue(0),
            ),
          ),
        ),
        throwsA(
          isA<NutritionScoringInputValidationException>().having(
            (error) => error.issues,
            'issues',
            contains(NutritionScoringInputIssue.nonPositiveTotalFat),
          ),
        ),
      );
      expect(
        () => ValidatedNutritionScoringInput.validate(
          completeInput(
            category: ScoringCategory.fatsOilsNutsSeeds,
            nutrition: completeNutrition(
              totalFat: verifiedValue(10),
              saturatedFat: verifiedValue(11),
            ),
          ),
        ),
        throwsA(
          isA<NutritionScoringInputValidationException>().having(
            (error) => error.issues,
            'issues',
            contains(NutritionScoringInputIssue.saturatedFatExceedsTotalFat),
          ),
        ),
      );
    });

    test('trusted plain-water fact cannot target a food category', () {
      expect(
        () => ValidatedNutritionScoringInput.validate(
          completeInput(
            classificationFacts: ScoringClassificationFacts(
              isPlainWater: verifiedValue(true),
            ),
          ),
        ),
        throwsA(
          isA<NutritionScoringInputValidationException>().having(
            (error) => error.issues,
            'issues',
            contains(NutritionScoringInputIssue.plainWaterCategoryMismatch),
          ),
        ),
      );
    });

    test('accepted sodium-derived salt is consumed without conversion', () {
      final input = completeInput(
        nutrition: completeNutrition(
          salt: verifiedValue(
            0.4,
            provenance: EvidenceProvenance.derivedFromSodium,
          ),
        ),
      );
      final result = calculator.calculate(
        ValidatedNutritionScoringInput.validate(input),
      );

      expect(result.saltPoints, 1);
    });

    test('kcal-derived energy is not converted inside the boundary', () {
      final input = completeInput(
        nutrition: completeNutrition(
          energyKj: verifiedValue(
            418.4,
            provenance: EvidenceProvenance.derivedFromKcal,
          ),
        ),
      );

      expect(
        () => ValidatedNutritionScoringInput.validate(input),
        throwsA(isA<NutritionScoringInputValidationException>()),
      );
    });
  });

  group('category formulas', () {
    test('same validated input always produces the same raw result', () {
      final input = ValidatedNutritionScoringInput.validate(completeInput());
      final first = calculator.calculate(input);
      final second = calculator.calculate(input);

      expect(second.resolvedCategory, first.resolvedCategory);
      expect(second.negativePointsTotal, first.negativePointsTotal);
      expect(second.positivePointsCalculated, first.positivePointsCalculated);
      expect(second.positivePointsApplied, first.positivePointsApplied);
      expect(second.rawScore, first.rawScore);
      expect(second.specialRules, first.specialRules);
    });

    test('general protein applies at N=10 and is suppressed at N=11', () {
      final before = score(
        category: ScoringCategory.generalFood,
        energyKj: 3350,
        salt: 0.4,
        protein: 18,
      );
      final suppressed = score(
        category: ScoringCategory.generalFood,
        energyKj: 3350,
        salt: 0.6,
        protein: 18,
      );

      expect(before.negativePointsTotal, 10);
      expect(before.proteinPointsCalculated, 7);
      expect(before.proteinPointsApplied, 7);
      expect(before.rawScore, 3);
      expect(suppressed.negativePointsTotal, 11);
      expect(suppressed.proteinPointsCalculated, 7);
      expect(suppressed.proteinPointsApplied, 0);
      expect(suppressed.rawScore, 11);
    });

    test('cheese keeps calculated protein applied at high N', () {
      final result = score(
        category: ScoringCategory.cheese,
        energyKj: 3350,
        salt: 0.6,
        protein: 18,
      );

      expect(result.negativePointsTotal, 11);
      expect(result.proteinPointsCalculated, 7);
      expect(result.proteinPointsApplied, 7);
      expect(result.rawScore, 4);
    });

    test('red meat preserves low, two-point, and capped protein states', () {
      final onePoint = score(
        category: ScoringCategory.redMeat,
        energyKj: 1000,
        saturatedFat: 2,
        protein: 4.8,
      );
      final twoPoints = score(
        category: ScoringCategory.redMeat,
        energyKj: 1000,
        saturatedFat: 2,
        protein: 7.2,
      );
      final capped = score(
        category: ScoringCategory.redMeat,
        energyKj: 1000,
        saturatedFat: 2,
        protein: 18,
      );

      expect(onePoint.proteinPointsApplied, 1);
      expect(twoPoints.proteinPointsApplied, 2);
      expect(capped.proteinPointsCalculated, 7);
      expect(capped.proteinPointsApplied, 2);
      expect(
        capped.specialRules,
        contains(NutritionSpecialRule.redMeatProteinCapped),
      );
    });

    test('red-meat protein is suppressed at high N after cap is recorded', () {
      final result = score(
        category: ScoringCategory.redMeat,
        energyKj: 3350,
        salt: 0.6,
        protein: 18,
      );

      expect(result.negativePointsTotal, 11);
      expect(result.proteinPointsCalculated, 7);
      expect(result.proteinPointsApplied, 0);
      expect(result.rawScore, 11);
    });

    test('fat protein applies at N=6 and is suppressed at N=7', () {
      final before = score(
        category: ScoringCategory.fatsOilsNutsSeeds,
        totalFat: 10,
        saturatedFat: 1,
        sugars: 20,
        protein: 18,
      );
      final suppressed = score(
        category: ScoringCategory.fatsOilsNutsSeeds,
        totalFat: 10,
        saturatedFat: 1,
        sugars: 24,
        protein: 18,
      );

      expect(before.negativePointsTotal, 6);
      expect(before.proteinPointsApplied, 7);
      expect(before.rawScore, -1);
      expect(suppressed.negativePointsTotal, 7);
      expect(suppressed.proteinPointsCalculated, 7);
      expect(suppressed.proteinPointsApplied, 0);
      expect(suppressed.rawScore, 7);
    });

    test('fat category records derived saturated energy and ratio', () {
      final result = score(
        category: ScoringCategory.fatsOilsNutsSeeds,
        totalFat: 100,
        saturatedFat: 14,
      );

      expect(result.negativePoints?.saturatedEnergyKj, 518);
      expect(result.negativePoints?.saturatedFatRatioPercent, 14);
      expect(result.saturatedEnergyPoints, 4);
      expect(result.saturatedFatRatioPoints, 1);
    });

    test('beverage NNS contributes exactly four negative points', () {
      final absent = score(category: ScoringCategory.beverage);
      final present = score(
        category: ScoringCategory.beverage,
        nnsPresent: true,
      );

      expect(absent.nnsPoints, 0);
      expect(present.nnsPoints, 4);
      expect(present.rawScore! - absent.rawScore!, 4);
    });

    test('beverage protein remains applied at high negative points', () {
      final result = score(
        category: ScoringCategory.beverage,
        energyKj: 400,
        sugars: 12,
        protein: 3.1,
      );

      expect(result.negativePointsTotal, 20);
      expect(result.proteinPointsCalculated, 7);
      expect(result.proteinPointsApplied, 7);
      expect(result.rawScore, 13);
    });

    test('beverage salt follows local textual rule at exact 3.2', () {
      final below = score(category: ScoringCategory.beverage, salt: 3.1999);
      final exact = score(category: ScoringCategory.beverage, salt: 3.2);
      final above = score(category: ScoringCategory.beverage, salt: 3.2001);

      expect(below.saltPoints, 15);
      expect(exact.saltPoints, 15);
      expect(above.saltPoints, 16);
    });

    test('plain water returns a typed result with no fake numeric score', () {
      final result = score(
        category: ScoringCategory.beverage,
        plainWater: true,
      );

      expect(result, isA<PlainWaterNutritionRawScoreResult>());
      expect(result.isPlainWaterSpecialCase, isTrue);
      expect(result.rawScore, isNull);
      expect(result.negativePointsTotal, isNull);
      expect(result.positivePointsApplied, isNull);
    });
  });

  group('OFFICIAL CALCULATOR VERIFIED CONTROL FIXTURE', () {
    test('general food fixture returns N=7 P=5 raw=2', () {
      final result = score(
        category: ScoringCategory.generalFood,
        energyKj: 1000,
        saturatedFat: 2,
        sugars: 8,
        salt: 0.6,
        protein: 8,
        fiber: 4,
        fvl: 50,
      );

      expect(result.negativePointsTotal, 7);
      expect(result.positivePointsCalculated, 5);
      expect(result.positivePointsApplied, 5);
      expect(result.rawScore, 2);
    });

    test('cheese fixture returns N=20 P=7 raw=13', () {
      final result = score(
        category: ScoringCategory.cheese,
        energyKj: 1400,
        saturatedFat: 6,
        sugars: 18,
        salt: 1.4,
        protein: 18,
      );

      expect(result.negativePointsTotal, 20);
      expect(result.positivePointsCalculated, 7);
      expect(result.positivePointsApplied, 7);
      expect(result.rawScore, 13);
    });

    test('red-meat fixture returns N=3 applied P=2 raw=1', () {
      final result = score(
        category: ScoringCategory.redMeat,
        energyKj: 1000,
        saturatedFat: 2,
        protein: 18,
      );

      expect(result.negativePointsTotal, 3);
      expect(result.proteinPointsCalculated, 7);
      expect(result.proteinPointsApplied, 2);
      expect(result.positivePointsApplied, 2);
      expect(result.rawScore, 1);
    });

    test('fats fixture returns N=9 applied P=2 raw=7', () {
      final result = score(
        category: ScoringCategory.fatsOilsNutsSeeds,
        totalFat: 80,
        saturatedFat: 16,
        sugars: 8,
        salt: 0.4,
        protein: 8,
        fiber: 4.1,
        fvl: 50,
      );

      expect(result.negativePointsTotal, 9);
      expect(result.positivePointsCalculated, 5);
      expect(result.positivePointsApplied, 2);
      expect(result.rawScore, 7);
    });

    test('beverage fixture returns N=6 P=3 raw=3', () {
      final result = score(
        category: ScoringCategory.beverage,
        energyKj: 90,
        saturatedFat: 1,
        sugars: 2,
        salt: 0.2,
        protein: 1.5,
        fiber: 3,
        fvl: 60,
        nnsPresent: true,
      );

      expect(result.negativePointsTotal, 6);
      expect(result.positivePointsCalculated, 3);
      expect(result.positivePointsApplied, 3);
      expect(result.rawScore, 3);
    });

    test('plain-water fixture remains a non-numeric special case', () {
      final result = score(
        category: ScoringCategory.beverage,
        plainWater: true,
      );

      expect(result, isA<PlainWaterNutritionRawScoreResult>());
      expect(result.methodologyVersion, nutritionRawMethodologyVersion);
      expect(result.rawScore, isNull);
    });

    test('known workbook 3.2 defect does not override textual fixture', () {
      final result = score(category: ScoringCategory.beverage, salt: 3.2);

      expect(result.saltPoints, 15);
    });
  });

  test('INTERNAL ARITHMETIC FIXTURE archetypes remain directional', () {
    final oats = score(
      category: ScoringCategory.generalFood,
      energyKj: 1500,
      saturatedFat: 1.2,
      sugars: 1,
      salt: 0.01,
      protein: 13,
      fiber: 10,
    );
    final highSugarCereal = score(
      category: ScoringCategory.generalFood,
      energyKj: 1600,
      saturatedFat: 2,
      sugars: 35,
      salt: 0.5,
      protein: 8,
      fiber: 3,
    );
    final plainYogurt = score(
      category: ScoringCategory.generalFood,
      energyKj: 250,
      saturatedFat: 2,
      sugars: 5,
      salt: 0.1,
      protein: 4.5,
    );
    final chocolateBiscuit = score(
      category: ScoringCategory.generalFood,
      energyKj: 2100,
      totalFat: 25,
      saturatedFat: 15,
      sugars: 35,
      salt: 0.8,
      protein: 5,
      fiber: 2,
    );
    final regularCola = score(
      category: ScoringCategory.beverage,
      energyKj: 180,
      sugars: 10.6,
    );
    final zeroSugarCola = score(
      category: ScoringCategory.beverage,
      energyKj: 2,
      nnsPresent: true,
    );
    final oliveOilLike = score(
      category: ScoringCategory.fatsOilsNutsSeeds,
      totalFat: 100,
      saturatedFat: 14,
    );
    final butterLike = score(
      category: ScoringCategory.fatsOilsNutsSeeds,
      totalFat: 82,
      saturatedFat: 51,
    );
    final plainCheese = score(
      category: ScoringCategory.cheese,
      energyKj: 1500,
      totalFat: 30,
      saturatedFat: 20,
      salt: 1.5,
      protein: 25,
    );
    final saltyProcessedCheese = score(
      category: ScoringCategory.cheese,
      energyKj: 1500,
      totalFat: 30,
      saturatedFat: 20,
      salt: 3,
      protein: 25,
    );

    expect(oats.rawScore!, lessThan(highSugarCereal.rawScore!));
    expect(plainYogurt.rawScore!, lessThan(chocolateBiscuit.rawScore!));
    expect(zeroSugarCola.rawScore!, lessThan(regularCola.rawScore!));
    expect(oliveOilLike.rawScore!, lessThan(butterLike.rawScore!));
    expect(plainCheese.rawScore!, lessThan(saltyProcessedCheese.rawScore!));
  });
}
