import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

import 'scoring_test_fixtures.dart';

void main() {
  const evaluator = ScoringReadinessEvaluator();
  const resolver = ScoringCategoryResolver();

  void expectBlocked(ScoringReadinessBlocker blocker, dynamic input) {
    final result = evaluator.evaluate(input);
    expect(result.isScorable, isFalse);
    expect(result.blockingReasons, contains(blocker));
  }

  group('nutrition basis', () {
    test('unknown basis is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.unknownNutritionBasis,
        completeInput(basis: NutritionBasis.unknown),
      );
    });

    test('per-serving-only basis is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.unsupportedPerServingOnly,
        completeInput(basis: NutritionBasis.perServing),
      );
    });

    test('per100g general food with complete evidence is scorable', () {
      final result = evaluator.evaluate(completeInput());

      expect(result.isScorable, isTrue);
      expect(result.blockingReasons, isEmpty);
    });

    test('per100g beverage is rejected', () {
      expectBlocked(
        ScoringReadinessBlocker.nutritionBasisDoesNotMatchCategory,
        completeInput(
          category: ScoringCategory.beverage,
          basis: NutritionBasis.per100g,
        ),
      );
    });

    test('per100ml beverage with complete evidence is scorable', () {
      final result = evaluator.evaluate(
        completeInput(category: ScoringCategory.beverage),
      );

      expect(result.isScorable, isTrue);
    });

    test('unknown product state is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.unknownProductState,
        completeInput(productState: NutritionProductState.unknown),
      );
    });
  });

  group('required nutrition', () {
    test('missing energy is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.missingEnergyKj,
        completeInput(nutrition: completeNutrition(includeEnergyKj: false)),
      );
    });

    test('missing saturated fat is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.missingSaturatedFat,
        completeInput(nutrition: completeNutrition(includeSaturatedFat: false)),
      );
    });

    test('missing sugars are blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.missingSugars,
        completeInput(nutrition: completeNutrition(includeSugars: false)),
      );
    });

    test('missing salt is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.missingSalt,
        completeInput(nutrition: completeNutrition(includeSalt: false)),
      );
    });

    test('missing protein is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.missingProtein,
        completeInput(nutrition: completeNutrition(includeProtein: false)),
      );
    });

    test('missing fiber is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.missingFiber,
        completeInput(nutrition: completeNutrition(includeFiber: false)),
      );
    });

    test('zero nutrient values remain present values', () {
      final result = evaluator.evaluate(
        completeInput(
          nutrition: completeNutrition(
            saturatedFat: verifiedValue(0),
            sugars: verifiedValue(0),
            salt: verifiedValue(0),
            protein: verifiedValue(0),
            fiber: verifiedValue(0),
          ),
        ),
      );

      expect(result.isScorable, isTrue);
    });

    test('fat category requires total fat', () {
      expectBlocked(
        ScoringReadinessBlocker.missingTotalFatForFatCategory,
        completeInput(
          category: ScoringCategory.fatsOilsNutsSeeds,
          nutrition: completeNutrition(includeTotalFat: false),
        ),
      );
    });

    test('fat category does not require declared total energy', () {
      final result = evaluator.evaluate(
        completeInput(
          category: ScoringCategory.fatsOilsNutsSeeds,
          nutrition: completeNutrition(includeEnergyKj: false),
        ),
      );

      expect(result.isScorable, isTrue);
      expect(
        result.blockingReasons,
        isNot(contains(ScoringReadinessBlocker.missingEnergyKj)),
      );
    });
  });

  group('cross-field nutrition invariants', () {
    test(
      'saturated fat greater than total fat is blocked (both individually valid)',
      () {
        expectBlocked(
          ScoringReadinessBlocker.saturatedFatExceedsTotalFat,
          completeInput(
            nutrition: completeNutrition(
              totalFat: verifiedValue(5),
              saturatedFat: verifiedValue(9),
            ),
          ),
        );
      },
    );

    test('saturated fat equal to total fat is not blocked', () {
      final result = evaluator.evaluate(
        completeInput(
          nutrition: completeNutrition(
            totalFat: verifiedValue(5),
            saturatedFat: verifiedValue(5),
          ),
        ),
      );
      expect(result.isScorable, isTrue);
      expect(
        result.blockingReasons,
        isNot(contains(ScoringReadinessBlocker.saturatedFatExceedsTotalFat)),
      );
    });

    test('fats/oils/nuts/seeds category with zero total fat is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.nonPositiveTotalFatForFatCategory,
        completeInput(
          category: ScoringCategory.fatsOilsNutsSeeds,
          nutrition: completeNutrition(totalFat: verifiedValue(0)),
        ),
      );
    });

    test(
      'zero total fat is not blocked for a category where total fat is not required',
      () {
        final result = evaluator.evaluate(
          completeInput(
            nutrition: completeNutrition(
              totalFat: verifiedValue(0),
              saturatedFat: verifiedValue(0),
            ),
          ),
        );
        expect(result.isScorable, isTrue);
        expect(
          result.blockingReasons,
          isNot(
            contains(ScoringReadinessBlocker.nonPositiveTotalFatForFatCategory),
          ),
        );
      },
    );

    test(
      'positive total fat for fats/oils/nuts/seeds category is not blocked',
      () {
        final result = evaluator.evaluate(
          completeInput(
            category: ScoringCategory.fatsOilsNutsSeeds,
            nutrition: completeNutrition(totalFat: verifiedValue(60)),
          ),
        );
        expect(result.isScorable, isTrue);
        expect(
          result.blockingReasons,
          isNot(
            contains(ScoringReadinessBlocker.nonPositiveTotalFatForFatCategory),
          ),
        );
      },
    );

    test(
      'trusted plain-water fact outside the beverage category is blocked',
      () {
        expectBlocked(
          ScoringReadinessBlocker.plainWaterCategoryMismatch,
          completeInput(
            classificationFacts: ScoringClassificationFacts(
              isPlainWater: verifiedValue(true),
            ),
          ),
        );
      },
    );

    test(
      'trusted plain-water fact inside the beverage category is not blocked',
      () {
        final result = evaluator.evaluate(
          completeInput(
            category: ScoringCategory.beverage,
            classificationFacts: ScoringClassificationFacts(
              isPlainWater: verifiedValue(true),
            ),
          ),
        );
        expect(result.isScorable, isTrue);
        expect(
          result.blockingReasons,
          isNot(contains(ScoringReadinessBlocker.plainWaterCategoryMismatch)),
        );
      },
    );

    test(
      'plain-water fact with unknown provenance does not block (not trusted)',
      () {
        final result = evaluator.evaluate(
          completeInput(
            classificationFacts: ScoringClassificationFacts(
              isPlainWater: const EvidenceValue<bool>(
                value: true,
                provenance: EvidenceProvenance.unknown,
                verification: EvidenceVerification.verified,
              ),
            ),
          ),
        );
        expect(
          result.blockingReasons,
          isNot(contains(ScoringReadinessBlocker.plainWaterCategoryMismatch)),
        );
      },
    );

    test('rejected plain-water fact does not block (not trusted)', () {
      final result = evaluator.evaluate(
        completeInput(
          classificationFacts: ScoringClassificationFacts(
            isPlainWater: const EvidenceValue<bool>(
              value: true,
              provenance: EvidenceProvenance.declaredLabel,
              verification: EvidenceVerification.rejected,
            ),
          ),
        ),
      );
      expect(
        result.blockingReasons,
        isNot(contains(ScoringReadinessBlocker.plainWaterCategoryMismatch)),
      );
    });
  });

  group('FVL evidence', () {
    test('unknown FVL is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.unknownFvlPercentage,
        completeInput(
          fvlEvidence: const CompositionPercentageEvidence.unknown(),
        ),
      );
    });

    test('proven zero is accepted with complete ingredient evidence', () {
      final result = evaluator.evaluate(completeInput());

      expect(result.isScorable, isTrue);
    });

    test('known 20 percent is accepted', () {
      final result = evaluator.evaluate(
        completeInput(
          fvlEvidence: const CompositionPercentageEvidence.known(
            20,
            provenance: EvidenceProvenance.declaredLabel,
            verification: EvidenceVerification.verified,
          ),
          ingredientCompleteness: IngredientEvidenceCompleteness.unknown,
        ),
      );

      expect(result.isScorable, isTrue);
    });

    test('proven zero is blocked when ingredient evidence is incomplete', () {
      expectBlocked(
        ScoringReadinessBlocker.incompleteIngredientEvidence,
        completeInput(
          ingredientCompleteness: IngredientEvidenceCompleteness.incomplete,
        ),
      );
    });
  });

  group('beverage NNS evidence', () {
    test('unknown NNS presence is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.unknownNnsPresence,
        completeInput(
          category: ScoringCategory.beverage,
          nnsEvidence: const PresenceEvidence.unknown(),
        ),
      );
    });

    test('NNS absence is accepted with complete ingredient evidence', () {
      final result = evaluator.evaluate(
        completeInput(category: ScoringCategory.beverage),
      );

      expect(result.isScorable, isTrue);
    });

    test('NNS presence is accepted without complete ingredient list', () {
      final result = evaluator.evaluate(
        completeInput(
          category: ScoringCategory.beverage,
          nnsEvidence: const PresenceEvidence.present(
            provenance: EvidenceProvenance.declaredLabel,
            verification: EvidenceVerification.verified,
          ),
          ingredientCompleteness: IngredientEvidenceCompleteness.unknown,
          fvlEvidence: const CompositionPercentageEvidence.known(
            0,
            provenance: EvidenceProvenance.adminVerified,
            verification: EvidenceVerification.verified,
          ),
        ),
      );

      expect(result.isScorable, isTrue);
    });

    test('NNS absence is blocked with incomplete ingredient evidence', () {
      expectBlocked(
        ScoringReadinessBlocker.incompleteIngredientEvidence,
        completeInput(
          category: ScoringCategory.beverage,
          ingredientCompleteness: IngredientEvidenceCompleteness.incomplete,
          fvlEvidence: const CompositionPercentageEvidence.known(
            0,
            provenance: EvidenceProvenance.adminVerified,
            verification: EvidenceVerification.verified,
          ),
        ),
      );
    });
  });

  group('category blockers', () {
    test('unknown category is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.unknownScoringCategory,
        completeInput(categoryEvidence: ScoringCategoryEvidence.unknown()),
      );
    });

    test('incomplete red-meat evidence keeps a specific blocker', () {
      final categoryEvidence = resolver.resolve(
        ScoringCategoryResolverInput(
          categoryTags: const ['kirmizi_et'],
          taxonomyProvenance: EvidenceProvenance.databaseImport,
        ),
      );

      expectBlocked(
        ScoringReadinessBlocker.redMeatEvidenceIncomplete,
        completeInput(categoryEvidence: categoryEvidence),
      );
    });

    test('unknown nut percentage keeps a specific blocker', () {
      final categoryEvidence = resolver.resolve(
        ScoringCategoryResolverInput(
          categoryTags: const ['kuruyemis'],
          taxonomyProvenance: EvidenceProvenance.databaseImport,
        ),
      );

      expectBlocked(
        ScoringReadinessBlocker.nutSeedPercentageUnknown,
        completeInput(categoryEvidence: categoryEvidence),
      );
    });
  });

  group('out-of-scope facts', () {
    ScoringCategoryEvidence resolveOutOfScope(
      ScoringClassificationFacts facts,
    ) {
      return resolver.resolve(ScoringCategoryResolverInput(facts: facts));
    }

    test('food supplement is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.outOfScopeProduct,
        completeInput(
          categoryEvidence: resolveOutOfScope(
            ScoringClassificationFacts(isFoodSupplement: verifiedValue(true)),
          ),
        ),
      );
    });

    test('infant food is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.outOfScopeProduct,
        completeInput(
          categoryEvidence: resolveOutOfScope(
            ScoringClassificationFacts(isInfantFood: verifiedValue(true)),
          ),
        ),
      );
    });

    test('medical food is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.outOfScopeProduct,
        completeInput(
          categoryEvidence: resolveOutOfScope(
            ScoringClassificationFacts(isMedicalFood: verifiedValue(true)),
          ),
        ),
      );
    });
  });

  group('provenance', () {
    test('sodium-derived salt is accepted and reported as warning', () {
      final result = evaluator.evaluate(
        completeInput(
          nutrition: completeNutrition(
            salt: verifiedValue(
              0.75,
              provenance: EvidenceProvenance.derivedFromSodium,
            ),
          ),
        ),
      );

      expect(result.isScorable, isTrue);
      expect(
        result.warningReasons,
        contains(ScoringReadinessWarning.saltDerivedFromSodium),
      );
    });

    test('kcal-derived energy is not treated as declared kJ', () {
      expectBlocked(
        ScoringReadinessBlocker.energyKjNotDeclared,
        completeInput(
          nutrition: completeNutrition(
            energyKj: verifiedValue(
              418.4,
              provenance: EvidenceProvenance.derivedFromKcal,
            ),
          ),
        ),
      );
    });

    test('unknown provenance is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.unknownNutritionProvenance,
        completeInput(
          nutrition: completeNutrition(
            sugars: const EvidenceValue<double>(
              value: 4,
              provenance: EvidenceProvenance.unknown,
              verification: EvidenceVerification.unknown,
            ),
          ),
        ),
      );
    });

    test('rejected evidence is blocked', () {
      expectBlocked(
        ScoringReadinessBlocker.rejectedEvidence,
        completeInput(
          nutrition: completeNutrition(
            fiber: const EvidenceValue<double>(
              value: 3,
              provenance: EvidenceProvenance.declaredLabel,
              verification: EvidenceVerification.rejected,
            ),
          ),
        ),
      );
    });
  });
}
