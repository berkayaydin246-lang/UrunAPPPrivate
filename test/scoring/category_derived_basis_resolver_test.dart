import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/category_derived_basis_resolver.dart';

/// Focused tests for the controlled category-derived nutrition-basis
/// fallback (product decision — see legacy_scoring_evidence_recovery.dart's
/// basis resolution step). Pure, deterministic, no I/O.
void main() {
  const resolver = CategoryDerivedBasisResolver();

  group('unambiguous PER_100G families', () {
    test('biscuit tag resolves per100g', () {
      expect(resolver.resolve(['biskuvi']), NutritionBasis.per100g);
    });

    test('chocolate/confectionery solid tag resolves per100g', () {
      expect(resolver.resolve(['cikolata']), NutritionBasis.per100g);
    });

    test('cheese tag resolves per100g', () {
      expect(resolver.resolve(['peynir']), NutritionBasis.per100g);
    });

    test('processed solid meat product tag resolves per100g', () {
      expect(resolver.resolve(['sucuk']), NutritionBasis.per100g);
    });

    test('nuts/seeds tag resolves per100g', () {
      expect(resolver.resolve(['kuruyemis']), NutritionBasis.per100g);
    });

    test('pasta and rice/grains tags resolve per100g', () {
      expect(resolver.resolve(['makarna']), NutritionBasis.per100g);
      expect(resolver.resolve(['bakliyat']), NutritionBasis.per100g);
    });

    test('bread/bakery solid tag resolves per100g', () {
      expect(resolver.resolve(['ekmek']), NutritionBasis.per100g);
    });

    test(
      'edible oil resolves per100g — internationally declared by mass, '
      'never per100ml, despite being physically liquid',
      () {
        expect(resolver.resolve(['sivi_yag']), NutritionBasis.per100g);
      },
    );
  });

  group('unambiguous PER_100ML families', () {
    test('carbonated soft drink tag resolves per100ml', () {
      expect(resolver.resolve(['gazli_icecek']), NutritionBasis.per100ml);
    });

    test('water tag resolves per100ml', () {
      expect(resolver.resolve(['maden_suyu']), NutritionBasis.per100ml);
    });

    test('fruit juice tag resolves per100ml', () {
      expect(resolver.resolve(['meyve_suyu']), NutritionBasis.per100ml);
    });

    test('energy drink tag resolves per100ml', () {
      expect(resolver.resolve(['enerji_icecekleri']), NutritionBasis.per100ml);
    });
  });

  group('genuinely ambiguous families remain unknown', () {
    test('sauces/dressings are never auto-resolved', () {
      expect(resolver.resolve(['sos']), NutritionBasis.unknown);
      expect(resolver.resolve(['soslar']), NutritionBasis.unknown);
    });

    test('ready meals (soup/stew-adjacent) are never auto-resolved', () {
      expect(resolver.resolve(['hazir_yemek']), NutritionBasis.unknown);
      expect(resolver.resolve(['pratik_yemek']), NutritionBasis.unknown);
      expect(
        resolver.resolve(['dondurulmus_hazir_yemek']),
        NutritionBasis.unknown,
      );
    });

    test('ice cream / frozen desserts are never auto-resolved', () {
      expect(resolver.resolve(['tek_dondurma']), NutritionBasis.unknown);
      expect(resolver.resolve(['kap_dondurma']), NutritionBasis.unknown);
      expect(resolver.resolve(['dondurulmus_tatli']), NutritionBasis.unknown);
      expect(resolver.resolve(['dondurma_tatli']), NutritionBasis.unknown);
    });

    test('generic desserts are never auto-resolved', () {
      expect(resolver.resolve(['tatli']), NutritionBasis.unknown);
      expect(resolver.resolve(['sutlu_tatli_krema']), NutritionBasis.unknown);
    });

    test('a too-broad "breakfast basket" tag is never auto-resolved', () {
      expect(resolver.resolve(['kahvaltilik']), NutritionBasis.unknown);
      expect(resolver.resolve(['kahvaltiliklar']), NutritionBasis.unknown);
    });

    test('special/meal-replacement nutrition products are never auto-resolved', () {
      expect(
        resolver.resolve(['ozel_beslenme_urunleri']),
        NutritionBasis.unknown,
      );
      expect(resolver.resolve(['saglikli_protein']), NutritionBasis.unknown);
    });

    test('a completely unrecognized tag is never auto-resolved', () {
      expect(resolver.resolve(['tamamen_bilinmeyen_bir_etiket']), NutritionBasis.unknown);
    });

    test('no tags at all resolves unknown', () {
      expect(resolver.resolve(const []), NutritionBasis.unknown);
    });
  });

  group('conflicting tags fail closed', () {
    test(
      'a solid tag and a liquid tag present together resolve unknown, '
      'never guessed',
      () {
        expect(
          resolver.resolve(['biskuvi', 'gazli_icecek']),
          NutritionBasis.unknown,
        );
      },
    );
  });

  group('determinism', () {
    test('the same input always produces the same basis', () {
      final first = resolver.resolve(['biskuvi', 'cikolata']);
      final second = resolver.resolve(['biskuvi', 'cikolata']);
      final third = resolver.resolve(['cikolata', 'biskuvi']);
      expect(first, NutritionBasis.per100g);
      expect(second, first);
      expect(third, first);
    });

    test('tag casing/whitespace never changes the result', () {
      expect(resolver.resolve([' BISKUVI ']), NutritionBasis.per100g);
      expect(resolver.resolve(['Biskuvi']), NutritionBasis.per100g);
    });

    test('duplicate tags do not change the result', () {
      expect(
        resolver.resolve(['biskuvi', 'biskuvi', 'biskuvi']),
        NutritionBasis.per100g,
      );
    });
  });

  test(
    'no product-specific special cases: the resolver has no notion of '
    'product id/name at all — its only input is category tags',
    () {
      // The public API accepts ONLY tags — there is no product-id/name
      // parameter anywhere for this class to special-case against.
      expect(
        resolver.resolve(['biskuvi']),
        resolver.resolve(['biskuvi']),
        reason: 'identical tags always produce identical output regardless '
            'of which product they came from',
      );
    },
  );
}
