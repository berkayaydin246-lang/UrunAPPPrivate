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
    String? canonicalCategory,
    String? canonicalSubcategory,
    ScoringClassificationFacts facts = const ScoringClassificationFacts(),
    bool allowLegacyCompatibility = false,
  }) {
    return ScoringCategoryResolverInput(
      categoryTags: tags,
      canonicalCategory: canonicalCategory,
      canonicalSubcategory: canonicalSubcategory,
      taxonomyProvenance: EvidenceProvenance.databaseImport,
      taxonomyVerification: EvidenceVerification.unverified,
      facts: facts,
      allowLegacyCompatibility: allowLegacyCompatibility,
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

    test('ordinary tags need the opt-in legacy compatibility policy', () {
      final strict = resolver.resolve(trustedInput(tags: ['cips_kraker']));
      final legacy = resolver.resolve(
        trustedInput(tags: ['cips_kraker'], allowLegacyCompatibility: true),
      );

      expect(strict.resolvedCategory, ScoringCategory.unknown);
      expect(legacy.resolvedCategory, ScoringCategory.generalFood);
      expect(
        legacy.reasons,
        contains(CategoryResolutionReason.resolvedFromLegacyTaxonomy),
      );
    });

    test('legacy broad ordinary canonical category resolves general food', () {
      final result = resolver.resolve(
        trustedInput(
          canonicalCategory: 'Atıştırmalık',
          allowLegacyCompatibility: true,
        ),
      );

      expect(result.resolvedCategory, ScoringCategory.generalFood);
      expect(result.source, CategoryEvidenceSource.trustedCanonicalCategory);
    });

    test('legacy canonical fallback does not override an unknown tag', () {
      final result = resolver.resolve(
        trustedInput(
          tags: ['unrecognized_special_category'],
          canonicalCategory: 'Atıştırmalık',
          allowLegacyCompatibility: true,
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

  // Section B/H of the methodology/readiness correction: the legacy-tag
  // bypass is live in production (allowLegacyCompatibility: true is
  // hardcoded in legacy_scoring_evidence_recovery.dart), so its exact
  // per-tag behavior — which tags bypass the fact-gated resolution and
  // which don't — must be locked in by a real test, not just re-derived
  // from reading the resolver source each time.
  group('dry tea/coffee eligibility correction (Section 1/7)', () {
    test(
      'dry tea (cay) and coffee (kahve) tags resolve generalFood under '
      'legacy compatibility — exemption from mandatory declaration must '
      'never by itself mean ineligible',
      () {
        for (final tag in ['cay', 'kahve']) {
          final result = resolver.resolve(
            trustedInput(tags: [tag], allowLegacyCompatibility: true),
          );

          expect(
            result.resolvedCategory,
            ScoringCategory.generalFood,
            reason: tag,
          );
        }
      },
    );

    test(
      'cay/kahve never resolve to beverage — dry tea/coffee must not be '
      'confused with prepared, ready-to-drink beverages',
      () {
        for (final tag in ['cay', 'kahve']) {
          final result = resolver.resolve(
            trustedInput(tags: [tag], allowLegacyCompatibility: true),
          );

          expect(result.resolvedCategory, isNot(ScoringCategory.beverage));
        }
      },
    );

    test(
      'without legacy compatibility, cay/kahve still remain unknown, '
      'exactly like every other ordinary tag',
      () {
        for (final tag in ['cay', 'kahve']) {
          final result = resolver.resolve(trustedInput(tags: [tag]));

          expect(result.resolvedCategory, ScoringCategory.unknown, reason: tag);
        }
      },
    );
  });

  group('legacy tag bypass (production allowLegacyCompatibility behavior)', () {
    test(
      'peynir tag alone resolves cheese under legacy compatibility, with '
      'no classification facts needed',
      () {
        final result = resolver.resolve(
          trustedInput(tags: ['peynir'], allowLegacyCompatibility: true),
        );

        expect(result.resolvedCategory, ScoringCategory.cheese);
        expect(
          result.reasons,
          contains(CategoryResolutionReason.resolvedFromLegacyTaxonomy),
        );
      },
    );

    test(
      'kirmizi_et tag alone resolves redMeat under legacy compatibility, '
      'with no classification facts needed',
      () {
        final result = resolver.resolve(
          trustedInput(tags: ['kirmizi_et'], allowLegacyCompatibility: true),
        );

        expect(result.resolvedCategory, ScoringCategory.redMeat);
        expect(
          result.reasons,
          contains(CategoryResolutionReason.resolvedFromLegacyTaxonomy),
        );
      },
    );

    test(
      'sucuk/sosis/salam/pastirma/kavurma tags do NOT get the same '
      'unconditional bypass as kirmizi_et — this asymmetry is a '
      'deliberately preserved, documented genuine blocker (not fixed in '
      'this correction), so it must stay locked in by this test rather '
      'than silently drifting',
      () {
        for (final tag in [
          'sucuk',
          'sosis',
          'salam',
          'pastirma',
          'kavurma',
        ]) {
          final result = resolver.resolve(
            trustedInput(tags: [tag], allowLegacyCompatibility: true),
          );

          expect(
            result.resolvedCategory,
            ScoringCategory.unknown,
            reason:
                '$tag requires redMeatPercentage>=20 and '
                'redMeatIsPrimaryIngredient facts, which legacy bulk '
                'recovery never populates',
          );
          expect(
            result.reasons,
            contains(CategoryResolutionReason.redMeatEvidenceIncomplete),
          );
        }
      },
    );
  });

  group(
    'taxonomy closure pass: newly-added zeytin / misir_ve_pirinc_patlagi '
    'safe mappings',
    () {
      test(
        'zeytin resolves generalFood deterministically under legacy '
        'compatibility, exactly like its sibling conserve-style tags',
        () {
          final result = resolver.resolve(
            trustedInput(tags: ['zeytin'], allowLegacyCompatibility: true),
          );

          expect(result.resolvedCategory, ScoringCategory.generalFood);
          expect(
            result.reasons,
            contains(CategoryResolutionReason.resolvedFromLegacyTaxonomy),
          );
        },
      );

      test(
        'misir_ve_pirinc_patlagi resolves identically to its differently '
        'spelled sibling misir_pirinc_patlagi — same real product family, '
        'two production tag spellings',
        () {
          final withVe = resolver.resolve(
            trustedInput(
              tags: ['misir_ve_pirinc_patlagi'],
              allowLegacyCompatibility: true,
            ),
          );
          final original = resolver.resolve(
            trustedInput(
              tags: ['misir_pirinc_patlagi'],
              allowLegacyCompatibility: true,
            ),
          );

          expect(withVe.resolvedCategory, ScoringCategory.generalFood);
          expect(original.resolvedCategory, ScoringCategory.generalFood);
        },
      );

      test('without legacy compatibility, both new tags remain unknown', () {
        for (final tag in ['zeytin', 'misir_ve_pirinc_patlagi']) {
          final result = resolver.resolve(trustedInput(tags: [tag]));
          expect(result.resolvedCategory, ScoringCategory.unknown, reason: tag);
        }
      });

      test(
        'ordering of multiple category_tags does not change the resolved '
        'category',
        () {
          final forward = resolver.resolve(
            trustedInput(
              tags: ['zeytin', 'konserve'],
              allowLegacyCompatibility: true,
            ),
          );
          final reversed = resolver.resolve(
            trustedInput(
              tags: ['konserve', 'zeytin'],
              allowLegacyCompatibility: true,
            ),
          );

          expect(forward.resolvedCategory, ScoringCategory.generalFood);
          expect(reversed.resolvedCategory, forward.resolvedCategory);
        },
      );

      test('duplicate tags do not change the resolved category', () {
        final single = resolver.resolve(
          trustedInput(tags: ['zeytin'], allowLegacyCompatibility: true),
        );
        final duplicated = resolver.resolve(
          trustedInput(
            tags: ['zeytin', 'zeytin'],
            allowLegacyCompatibility: true,
          ),
        );

        expect(duplicated.resolvedCategory, single.resolvedCategory);
      });

      test(
        'zeytin never overrides an unrelated special-category conflict — '
        'a genuine beverage vs fats/oils/nuts/seeds conflict still fails '
        'closed to unknown, exactly as it does without zeytin present',
        () {
          final result = resolver.resolve(
            trustedInput(
              tags: ['zeytin', 'gazli_icecek', 'sivi_yag'],
              allowLegacyCompatibility: true,
            ),
          );

          expect(result.resolvedCategory, ScoringCategory.unknown);
          expect(
            result.reasons,
            contains(CategoryResolutionReason.conflictingEvidence),
          );
        },
      );

      test(
        'category mapping never synthesizes nutrition basis — an '
        'arbitrary, unrecognized canonicalSubcategory string never '
        'influences the resolved category, and ScoringCategoryEvidence '
        'itself carries no basis field at all',
        () {
          final withoutSubcategory = resolver.resolve(
            trustedInput(tags: ['zeytin'], allowLegacyCompatibility: true),
          );
          final withUnrelatedSubcategory = resolver.resolve(
            trustedInput(
              tags: ['zeytin'],
              canonicalSubcategory: 'per_100g',
              allowLegacyCompatibility: true,
            ),
          );

          expect(
            withUnrelatedSubcategory.resolvedCategory,
            withoutSubcategory.resolvedCategory,
          );
          expect(
            withUnrelatedSubcategory.resolvedCategory,
            ScoringCategory.generalFood,
          );
        },
      );

      test(
        'category mapping never flips eligibility by itself — a trusted '
        'out-of-scope fact still wins over the newly-added tags exactly '
        'as it does for every other tag',
        () {
          for (final tag in ['zeytin', 'misir_ve_pirinc_patlagi']) {
            final result = resolver.resolve(
              trustedInput(
                tags: [tag],
                allowLegacyCompatibility: true,
                facts: ScoringClassificationFacts(
                  isFoodSupplement: verifiedValue(true),
                ),
              ),
            );

            expect(
              result.resolvedCategory,
              ScoringCategory.outOfScope,
              reason: tag,
            );
          }
        },
      );

      test(
        'source-neutral: the resolver accepts no source/retailer signal at '
        'all, so the same tag resolves identically regardless of which '
        'adapter/source it originated from',
        () {
          // ScoringCategoryResolverInput has no source/retailer field —
          // this is a structural guarantee, not a per-source branch to
          // test. Demonstrated here by resolving from two independently
          // constructed inputs (modeling two different retailer adapters)
          // that differ in nothing but object identity.
          final fromAdapterA = resolver.resolve(
            trustedInput(tags: ['zeytin'], allowLegacyCompatibility: true),
          );
          final fromAdapterB = resolver.resolve(
            ScoringCategoryResolverInput(
              categoryTags: const ['zeytin'],
              taxonomyProvenance: EvidenceProvenance.databaseImport,
              taxonomyVerification: EvidenceVerification.unverified,
              allowLegacyCompatibility: true,
            ),
          );

          expect(fromAdapterA.resolvedCategory, fromAdapterB.resolvedCategory);
        },
      );
    },
  );

  group('out-of-scope routing (Section A eligibility)', () {
    test(
      'a trusted food-supplement fact resolves outOfScope, distinct from '
      'unknown',
      () {
        final result = resolver.resolve(
          trustedInput(
            tags: ['cips_kraker'],
            allowLegacyCompatibility: true,
            facts: ScoringClassificationFacts(
              isFoodSupplement: verifiedValue(true),
            ),
          ),
        );

        expect(result.resolvedCategory, ScoringCategory.outOfScope);
      },
    );

    test(
      'default empty classification facts (as used throughout legacy bulk '
      'recovery) can never produce outOfScope — this is the exact reason '
      'notScoreEligible is currently unreachable for legacy-recovered '
      'products, not a bug in this test',
      () {
        final result = resolver.resolve(
          trustedInput(tags: ['cips_kraker'], allowLegacyCompatibility: true),
        );

        expect(result.resolvedCategory, isNot(ScoringCategory.outOfScope));
      },
    );
  });
}
