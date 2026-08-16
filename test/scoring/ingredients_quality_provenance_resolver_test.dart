import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';

/// Reopened Section G finding: a missing top-level
/// `raw_source_payload.ingredients_quality` is NOT sufficient evidence that
/// the scraper's quality judgment was never captured. Confirmed against a
/// real saved production probe (tmp/legacy_recovery_root_cause_probe_output.txt)
/// showing an actual row's raw_source_payload:
///   {"meta": {...}, "debug": {"ingredient_quality": "ingredients_ok", ...},
///    "jsonld": null, ..., "ingredients_raw": "..."}
/// — with NO top-level "ingredients_quality" key at all. The historical
/// scraper contract wrote the classification only to
/// `debug.ingredient_quality` for these rows. resolveEffectiveIngredientsQuality
/// must check both locations before concluding the judgment is absent.
void main() {
  group('resolveEffectiveIngredientsQuality', () {
    test('top-level ingredients_quality = ingredients_ok is trusted', () {
      expect(
        resolveEffectiveIngredientsQuality({
          'ingredients_quality': 'ingredients_ok',
        }),
        'ingredients_ok',
      );
    });

    test(
      'debug.ingredient_quality = ingredients_ok is trusted when the '
      'top-level key is entirely absent — the exact confirmed production '
      'shape (7 Days Çilekli Kruvasan 60 G)',
      () {
        expect(
          resolveEffectiveIngredientsQuality({
            'meta': {'title': 'irrelevant'},
            'debug': {
              'image_front_role': 'unknown',
              'ingredient_quality': 'ingredients_ok',
              'brand_source_method': 'api_metadata',
            },
            'jsonld': null,
            'ingredients_raw': 'İçindekiler: ...',
          }),
          'ingredients_ok',
        );
      },
    );

    test(
      'missing top-level quality + valid nested raw quality proves '
      'completeness end-to-end via hasSourceCompleteIngredients',
      () {
        final resolved = resolveEffectiveIngredientsQuality({
          'debug': {'ingredient_quality': 'ingredients_ok'},
          'ingredients_raw': 'İçindekiler: un, tuz, maya',
        });
        final staging = LegacyStagingScoringEvidence(
          id: 's1',
          sourceUrl: 'https://www.migros.com.tr/product-1',
          nutritionBasis: 'per_100',
          source: 'web_scraper:migros',
          ingredientsSource: 'web_scraper:migros',
          ingredientsRaw: 'İçindekiler: un, tuz, maya',
          ingredientsText: 'un, tuz, maya',
          ingredientsQuality: resolved,
        );

        expect(
          staging.hasSourceCompleteIngredients('un, tuz, maya'),
          isTrue,
        );
      },
    );

    test('missing all quality evidence resolves to null (stays incomplete)', () {
      expect(
        resolveEffectiveIngredientsQuality({'ingredients_raw': 'un, tuz'}),
        isNull,
      );
      expect(resolveEffectiveIngredientsQuality(null), isNull);
      expect(resolveEffectiveIngredientsQuality({'debug': {}}), isNull);
    });

    test(
      'explicit rejected/junk quality (either location) remains untrusted '
      'for completeness, never upgraded by the other location being empty',
      () {
        expect(
          resolveEffectiveIngredientsQuality({
            'ingredients_quality': 'ingredients_rejected_as_junk',
          }),
          'ingredients_rejected_as_junk',
        );
        expect(
          resolveEffectiveIngredientsQuality({
            'debug': {'ingredient_quality': 'ingredients_suspicious'},
          }),
          'ingredients_suspicious',
        );
        // Neither value ever equals 'ingredients_ok', so
        // hasSourceCompleteIngredients stays false regardless — verified
        // directly rather than re-deriving the equality here.
        final rejected = LegacyStagingScoringEvidence(
          id: 's1',
          sourceUrl: 'https://www.migros.com.tr/product-1',
          nutritionBasis: 'per_100',
          source: 'web_scraper:migros',
          ingredientsRaw: 'x',
          ingredientsText: 'x',
          ingredientsQuality: 'ingredients_rejected_as_junk',
        );
        expect(rejected.hasSourceCompleteIngredients('x'), isFalse);
      },
    );

    test(
      'conflicting quality evidence between the two trusted locations '
      'fails closed — never silently picks either value',
      () {
        final resolved = resolveEffectiveIngredientsQuality({
          'ingredients_quality': 'ingredients_ok',
          'debug': {'ingredient_quality': 'ingredients_suspicious'},
        });

        expect(resolved, ingredientsQualityProvenanceConflict);
        expect(
          resolved,
          isNot('ingredients_ok'),
          reason: 'must never pick the more permissive value',
        );

        final staging = LegacyStagingScoringEvidence(
          id: 's1',
          sourceUrl: 'https://www.migros.com.tr/product-1',
          nutritionBasis: 'per_100',
          source: 'web_scraper:migros',
          ingredientsRaw: 'x',
          ingredientsText: 'x',
          ingredientsQuality: resolved,
        );
        expect(
          staging.hasSourceCompleteIngredients('x'),
          isFalse,
          reason:
              'a provenance conflict must still fail the completeness '
              'check via the existing equality check, without any special '
              'case inside hasSourceCompleteIngredients itself',
        );
      },
    );

    test(
      'agreeing values at both locations resolve to that shared value, not '
      'a conflict',
      () {
        expect(
          resolveEffectiveIngredientsQuality({
            'ingredients_quality': 'ingredients_ok',
            'debug': {'ingredient_quality': 'ingredients_ok'},
          }),
          'ingredients_ok',
        );
      },
    );

    test(
      'an untrusted/unknown string in either location is never aliased to '
      'a real quality state',
      () {
        expect(
          resolveEffectiveIngredientsQuality({
            'ingredients_quality': 'some_unexpected_value',
          }),
          isNull,
        );
        expect(
          resolveEffectiveIngredientsQuality({
            'debug': {'ingredient_quality': 'ok'},
          }),
          isNull,
          reason:
              'only the exact scraper-produced constant strings are ever '
              'trusted, never a loosely-similar alias',
        );
      },
    );
  });

  // Reopened Section 3 of the coverage/readiness closure pass: when NO
  // trusted scraper-declared quality value exists anywhere (neither raw
  // location), deterministically recompute it from the retained raw
  // source — a direct Dart port of ingredient_parser.py's
  // is_junk()/is_suspicious(), applied to the text the scraper ALREADY
  // extracted. This is re-processing retained primary evidence, not a
  // guess: it makes the identical judgment the scraper itself would have
  // made, for rows where that judgment was simply never persisted.
  group('recomputeIngredientsQualityFromRetainedSource', () {
    test(
      'a real, well-formed ingredient list recomputes to OK — mirrors '
      'ingredient_parser.py test_valid_ingredients_ok',
      () {
        final result = recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: 'İçindekiler: Dana eti, tuz, baharat karışımı, su, patates nişastası',
          ingredientsText: 'Dana eti, tuz, baharat karışımı, su, patates nişastası',
        );

        expect(result, recomputedIngredientsQualityOkV1);
      },
    );

    test(
      'İade Koşulları policy text recomputes to rejected-as-junk — mirrors '
      'ingredient_parser.py test_iade_kosullari_is_junk',
      () {
        const junk =
            'İade Koşulları: Satın aldığınız ürünü 14 gün içinde iade edebilirsiniz.';
        final result = recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: junk,
          ingredientsText: junk,
        );

        expect(result, 'ingredients_rejected_as_junk');
      },
    );

    test(
      'Sepete Ekle UI text recomputes to rejected-as-junk — mirrors '
      'ingredient_parser.py test_sepete_ekle_is_junk',
      () {
        const junk = 'Sepete Ekle butonuna tıklayarak alışverişinizi tamamlayın.';
        final result = recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: junk,
          ingredientsText: junk,
        );

        expect(result, 'ingredients_rejected_as_junk');
      },
    );

    test(
      'text under 20 characters recomputes to suspicious, never OK — '
      'mirrors ingredient_parser.py test_too_short_is_suspicious',
      () {
        final result = recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: 'Hindi eti',
          ingredientsText: 'Hindi eti',
        );

        expect(result, 'ingredients_suspicious');
      },
    );

    test(
      'net-amount-only text recomputes to suspicious, never junk — mirrors '
      'ingredient_parser.py test_net_amount_only_is_suspicious',
      () {
        final result = recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: 'Net Miktar 300 g paket',
          ingredientsText: 'Net Miktar 300 g paket',
        );

        expect(result, 'ingredients_suspicious');
      },
    );

    test(
      'nutrition-table text leaked into ingredients recomputes to '
      'suspicious — mirrors ingredient_parser.py '
      'test_nutrition_labels_mixed_is_suspicious',
      () {
        final result = recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: 'Besin Değerleri Enerji 248 kcal Yağ 20 g Protein 11 g',
          ingredientsText: 'Besin Değerleri Enerji 248 kcal Yağ 20 g Protein 11 g',
        );

        expect(result, 'ingredients_suspicious');
      },
    );

    test(
      'no separators and few tokens recomputes to suspicious — mirrors '
      'ingredient_parser.py test_no_separator_few_tokens_is_suspicious',
      () {
        final result = recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: 'Piliç But Baget Izgara',
          ingredientsText: 'Piliç But Baget Izgara',
        );

        expect(result, 'ingredients_suspicious');
      },
    );

    test('missing raw source (empty) cannot be recomputed — stays unknown', () {
      expect(
        recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: '',
          ingredientsText: 'Dana eti, tuz, baharat karışımı, su, patates nişastası',
        ),
        isNull,
      );
      expect(
        recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: null,
          ingredientsText: 'Dana eti, tuz, baharat karışımı, su, patates nişastası',
        ),
        isNull,
      );
    });

    test('missing extracted text cannot be recomputed — stays unknown', () {
      expect(
        recomputeIngredientsQualityFromRetainedSource(
          ingredientsRaw: 'İçindekiler: bir şeyler',
          ingredientsText: null,
        ),
        isNull,
      );
    });

    test(
      'end-to-end via resolveEffectiveIngredientsQuality: no direct '
      'location has any value, so tier 2 recomputation runs and produces '
      'a source-complete result',
      () {
        final resolved = resolveEffectiveIngredientsQuality(
          {'jsonld': null},
          ingredientsRaw: 'İçindekiler: pastörize inek sütü, tuz, peynir mayası',
          ingredientsText: 'pastörize inek sütü, tuz, peynir mayası',
        );

        expect(resolved, recomputedIngredientsQualityOkV1);

        final staging = LegacyStagingScoringEvidence(
          id: 's1',
          sourceUrl: 'https://www.migros.com.tr/product-1',
          nutritionBasis: 'per_100',
          source: 'web_scraper:migros',
          ingredientsRaw: 'İçindekiler: pastörize inek sütü, tuz, peynir mayası',
          ingredientsText: 'pastörize inek sütü, tuz, peynir mayası',
          ingredientsQuality: resolved,
        );
        expect(
          staging.hasSourceCompleteIngredients(
            'pastörize inek sütü, tuz, peynir mayası',
          ),
          isTrue,
        );
      },
    );

    test(
      'a genuine provenance conflict at tier 1 is NEVER overridden by tier '
      '2 recomputation — the conflict is already a definite result',
      () {
        final resolved = resolveEffectiveIngredientsQuality(
          {
            'ingredients_quality': 'ingredients_ok',
            'debug': {'ingredient_quality': 'ingredients_suspicious'},
          },
          ingredientsRaw: 'İçindekiler: dana eti, tuz, baharat karışımı, su',
          ingredientsText: 'dana eti, tuz, baharat karışımı, su',
        );

        expect(resolved, ingredientsQualityProvenanceConflict);
      },
    );
  });
}
