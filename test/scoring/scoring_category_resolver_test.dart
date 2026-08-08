import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';

import 'scoring_test_fixtures.dart';

void main() {
  const resolver = ScoringCategoryResolver();

  ScoringCategoryResolverInput trustedInput({
    List<String> tags = const [],
    String? canonicalSubcategory,
    ScoringClassificationFacts facts = const ScoringClassificationFacts(),
  }) {
    return ScoringCategoryResolverInput(
      categoryTags: tags,
      canonicalSubcategory: canonicalSubcategory,
      taxonomyProvenance: EvidenceProvenance.databaseImport,
      taxonomyVerification: EvidenceVerification.unverified,
      facts: facts,
    );
  }

  group('explicit and general category evidence', () {
    test('trusted explicit metadata resolves general food', () {
      final result = resolver.resolve(
        ScoringCategoryResolverInput(
          explicitCategory: verifiedValue(ScoringCategory.generalFood),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.generalFood);
      expect(result.isSufficient, isTrue);
    });

    test('unknown-provenance explicit metadata is not trusted', () {
      final result = resolver.resolve(
        ScoringCategoryResolverInput(
          explicitCategory: const EvidenceValue<ScoringCategory>(
            value: ScoringCategory.generalFood,
            provenance: EvidenceProvenance.unknown,
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.unknown);
    });
  });

  group('beverage evidence', () {
    test('specific trusted beverage tag resolves beverage', () {
      final result = resolver.resolve(trustedInput(tags: ['gazli_icecek']));

      expect(result.resolvedCategory, ScoringCategory.beverage);
      expect(result.source, CategoryEvidenceSource.trustedCategoryTag);
    });

    test('broad tea tag does not resolve beverage', () {
      final result = resolver.resolve(trustedInput(tags: ['cay']));

      expect(result.resolvedCategory, ScoringCategory.unknown);
    });

    test('plain-water fact resolves beverage and retains reason', () {
      final result = resolver.resolve(
        trustedInput(
          facts: ScoringClassificationFacts(isPlainWater: verifiedValue(true)),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.beverage);
      expect(
        result.reasons,
        contains(CategoryResolutionReason.plainWaterConfirmed),
      );
    });

    test('maden suyu tag proves beverage but not plain water', () {
      final result = resolver.resolve(trustedInput(tags: ['maden_suyu']));

      expect(result.resolvedCategory, ScoringCategory.beverage);
      expect(
        result.reasons,
        isNot(contains(CategoryResolutionReason.plainWaterConfirmed)),
      );
    });

    test('drinkable dairy fact resolves beverage', () {
      final result = resolver.resolve(
        trustedInput(
          facts: ScoringClassificationFacts(
            isDrinkableDairy: verifiedValue(true),
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.beverage);
    });
  });

  group('cheese evidence', () {
    test('trusted cheese evidence with exclusions resolves cheese', () {
      final result = resolver.resolve(
        trustedInput(
          tags: ['peynir'],
          facts: ScoringClassificationFacts(
            isPlantBasedCheeseAlternative: verifiedValue(false),
            isCompoundProduct: verifiedValue(false),
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.cheese);
    });

    test('loose cheese tag remains unknown without exclusion facts', () {
      final result = resolver.resolve(trustedInput(tags: ['peynir']));

      expect(result.resolvedCategory, ScoringCategory.unknown);
      expect(
        result.reasons,
        contains(CategoryResolutionReason.cheeseEvidenceIncomplete),
      );
    });

    test('plant-based alternative does not resolve cheese', () {
      final result = resolver.resolve(
        trustedInput(
          tags: ['peynir'],
          facts: ScoringClassificationFacts(
            isPlantBasedCheeseAlternative: verifiedValue(true),
            isCompoundProduct: verifiedValue(false),
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.unknown);
    });
  });

  group('red-meat evidence', () {
    test('loose red-meat tag does not resolve special category', () {
      final result = resolver.resolve(trustedInput(tags: ['kirmizi_et']));

      expect(result.resolvedCategory, ScoringCategory.unknown);
      expect(
        result.reasons,
        contains(CategoryResolutionReason.redMeatEvidenceIncomplete),
      );
    });

    test('20 percent and primary ingredient resolve red meat', () {
      final result = resolver.resolve(
        trustedInput(
          tags: ['kirmizi_et'],
          facts: ScoringClassificationFacts(
            redMeatPercentage: verifiedValue(20),
            redMeatIsPrimaryIngredient: verifiedValue(true),
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.redMeat);
    });

    test('red-meat share below 20 percent remains unknown', () {
      final result = resolver.resolve(
        trustedInput(
          tags: ['sucuk'],
          facts: ScoringClassificationFacts(
            redMeatPercentage: verifiedValue(19.99),
            redMeatIsPrimaryIngredient: verifiedValue(true),
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.unknown);
    });

    test('non-primary red meat remains unknown', () {
      final result = resolver.resolve(
        trustedInput(
          tags: ['salam'],
          facts: ScoringClassificationFacts(
            redMeatPercentage: verifiedValue(80),
            redMeatIsPrimaryIngredient: verifiedValue(false),
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.unknown);
    });
  });

  group('fat, oil, nut and seed evidence', () {
    test('loose nut tag remains unknown', () {
      final result = resolver.resolve(trustedInput(tags: ['kuruyemis']));

      expect(result.resolvedCategory, ScoringCategory.unknown);
      expect(
        result.reasons,
        contains(CategoryResolutionReason.nutSeedPercentageUnknown),
      );
    });

    test('nut share above 50 percent resolves special category', () {
      final result = resolver.resolve(
        trustedInput(
          tags: ['findik_ezmesi'],
          facts: ScoringClassificationFacts(
            nutSeedPercentage: verifiedValue(50.01),
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.fatsOilsNutsSeeds);
    });

    test('nut share exactly 50 percent remains unknown', () {
      final result = resolver.resolve(
        trustedInput(
          tags: ['kuruyemis'],
          facts: ScoringClassificationFacts(
            nutSeedPercentage: verifiedValue(50),
          ),
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.unknown);
    });

    test('specific liquid-oil tag resolves special category', () {
      final result = resolver.resolve(trustedInput(tags: ['sivi_yag']));

      expect(result.resolvedCategory, ScoringCategory.fatsOilsNutsSeeds);
    });
  });

  group('safety and conflicts', () {
    test('untrusted taxonomy values remain unknown', () {
      final result = resolver.resolve(
        ScoringCategoryResolverInput(categoryTags: ['gazli_icecek']),
      );

      expect(result.resolvedCategory, ScoringCategory.unknown);
      expect(
        result.reasons,
        contains(CategoryResolutionReason.untrustedTaxonomyEvidence),
      );
    });

    test('conflicting special-category evidence remains unknown', () {
      final result = resolver.resolve(
        trustedInput(tags: ['gazli_icecek', 'sivi_yag']),
      );

      expect(result.resolvedCategory, ScoringCategory.unknown);
      expect(
        result.reasons,
        contains(CategoryResolutionReason.conflictingEvidence),
      );
    });
  });
}
