import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_backfill.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

void main() {
  const recovery = LegacyScoringEvidenceRecoveryService();

  group('legacy evidence recovery', () {
    test('source-complete legacy snack can become final-score ready', () async {
      final result = await recovery.recover(
        product: _product(),
        stagingMatches: [_staging()],
        ingredientCatalogue: const [],
      );

      expect(result.explicitPer100, isTrue);
      expect(result.basisReady, isTrue);
      expect(result.classificationReady, isTrue);
      expect(result.fvlReady, isTrue);
      expect(result.additiveReady, isTrue);
      expect(result.finalScoreReady, isTrue);
      expect(result.canWrite, isTrue);
      expect(result.evidence!.nutritionBasis, NutritionBasis.per100g);
      expect(
        result.evidence!.categoryEvidence.resolvedCategory,
        ScoringCategory.generalFood,
      );
      expect(
        result.evidence!.nutritionProductState,
        NutritionProductState.asSold,
      );
      expect(
        result.evidence!.ingredientEvidenceCompleteness,
        IngredientEvidenceCompleteness.complete,
      );
      expect(
        result.evidence!.fvlEvidence.state,
        CompositionPercentageState.provenAbsent,
      );
      expect(
        // Basis remediation Section E: proven exact basis (per_100g/
        // per_100ml, as this fixture's staging row declares) is now
        // tagged declaredLabel specifically so it is retroactively
        // distinguishable from the old category-invented databaseImport
        // tagging — see _recoveredBasisFromEvidence.
        result.evidence!.nutritionBasisEvidence!.provenance,
        EvidenceProvenance.declaredLabel,
      );
      expect(
        result.evidence!.nutritionBasisEvidence!.verification,
        EvidenceVerification.verified,
      );
      expect(
        result.evidence!.nutrition.energyKj.provenance,
        EvidenceProvenance.declaredLabel,
      );
      expect(
        result.evidence!.nutrition.energyKj.verification,
        EvidenceVerification.verified,
      );
      expect(result.evidence!.adminVerification, isNull);
      expect(result.blockerReasons, isEmpty);
    });

    test('rejects unknown nutrition basis', () async {
      final result = await _recover(staging: _staging(basis: 'unknown'));

      expect(result.canWrite, isFalse);
      expect(result.blockerReasons, contains('basis_unknown'));
    });

    test('rejects historical assumed-per-100 warning', () async {
      final result = await _recover(
        staging: _staging(
          warnings: const ['nutrition_basis_unknown_assumed_per_100'],
        ),
      );

      expect(result.canWrite, isFalse);
      expect(result.blockerReasons, contains('basis_unknown_assumed_per100'));
    });

    test('rejects per-serving nutrition', () async {
      final result = await _recover(staging: _staging(basis: 'per_serving'));

      expect(result.canWrite, isFalse);
      expect(result.blockerReasons, contains('basis_per_serving'));
    });

    test('missing fiber stays unknown and blocks readiness', () async {
      final result = await _recover(
        product: _product(nutrition: _nutrition()..remove('fiber')),
      );

      expect(result.nutritionComplete, isFalse);
      expect(result.blockerReasons, contains('missing_fiber'));
      expect(result.evidence!.nutrition.fiber.value, isNull);
    });

    // Reopened Section F/G verification: an EXPLICIT, declared fiber value
    // of exactly 0 is a real numeric declaration (the label states zero
    // fibre), not an absence of data — it must be accepted and scored as
    // zero fibre points, and must NOT be conflated with the missing/null
    // case above. The two cases must produce opposite readiness outcomes
    // despite the eventual fiberPoints() contribution numerically
    // coinciding at 0 in both the "declared 0" and "would-be-zero-filled"
    // hypothetical — the ARCHITECTURAL distinction (blocked vs. ready) is
    // what this guards, not the point-table arithmetic.
    test(
      'explicit trusted fiber = 0 is a real declaration, accepted and '
      'scored as zero fibre points — never treated as missing',
      () async {
        final result = await _recover(
          product: _product(nutrition: {..._nutrition(), 'fiber': 0}),
        );

        expect(result.nutritionComplete, isTrue);
        expect(result.blockerReasons, isNot(contains('missing_fiber')));
        expect(result.evidence!.nutrition.fiber.value, 0);
      },
    );

    test(
      'explicit trusted fiber present only in staging is recovered generically',
      () async {
        final product = _product(nutrition: _nutrition()..remove('fiber'));
        // Staging's raw nutrition JSON matches the product on every field
        // the product DOES have, and additionally carries the fiber value
        // the product itself is missing.
        final staging = _staging(product: product, nutritionJson: _nutrition());

        final result = await recovery.recover(
          product: product,
          stagingMatches: [staging],
          ingredientCatalogue: const [],
        );

        expect(result.nutritionComplete, isTrue);
        expect(result.blockerReasons, isNot(contains('missing_fiber')));
        expect(result.evidence!.nutrition.fiber.value, 2);
        expect(
          result.evidence!.nutrition.fiber.provenance,
          EvidenceProvenance.databaseImport,
          reason:
              'recovered from staging, not the product\'s own declared label',
        );
        expect(
          result.evidence!.nutrition.fiber.verification,
          EvidenceVerification.unverified,
        );
      },
    );

    test(
      'staging fiber is never borrowed when another field genuinely disagrees',
      () async {
        final product = _product(nutrition: _nutrition()..remove('fiber'));
        final conflicting = _nutrition()
          ..['fiber'] = 9
          ..['sugars'] = 999; // disagrees with product's declared sugars
        final staging = _staging(product: product, nutritionJson: conflicting);

        final result = await recovery.recover(
          product: product,
          stagingMatches: [staging],
          ingredientCatalogue: const [],
        );

        expect(
          result.blockerReasons,
          contains('missing_fiber'),
          reason:
              'a genuine conflict on another field means staging cannot be '
              'trusted to fill in the gap either',
        );
        expect(result.evidence!.nutrition.fiber.value, isNull);
      },
    );

    test(
      'missing category with proven basis blocks on classification only — '
      'basis and category are independent evidence dimensions',
      () async {
        final product = _product(categoryTags: const []);
        final result = await _recover(
          product: product,
          staging: _staging(product: product, basis: 'per_100g'),
        );

        expect(result.classificationReady, isFalse);
        expect(
          result.basisReady,
          isTrue,
          reason: 'basis was independently proven; category being '
              'unresolved must not retroactively make basis ambiguous',
        );
        expect(result.evidence!.nutritionBasis, NutritionBasis.per100g);
        expect(result.blockerReasons, contains('missing_classification'));
        expect(result.blockerReasons, isNot(contains('basis_unit_ambiguous')));
      },
    );

    // Reopened correctness fix: scoring category and nutrition basis are
    // independent evidence dimensions. A resolved category tells the
    // formula which point tables to use; it must never manufacture proof
    // that the source declaration actually used the basis that formula
    // expects. One data-driven check per resolvable category — each
    // proves category resolves confidently (classificationReady=true)
    // while basis, on its own, independently gates readiness.
    group('basis independence across every resolvable category', () {
      final cases = <String, (List<String> tags, ScoringCategory category, NutritionBasis expectedBasis)>{
        'generalFood (cips_kraker)': (
          ['cips_kraker'],
          ScoringCategory.generalFood,
          NutritionBasis.per100g,
        ),
        'generalFood via dry tea (cay)': (
          ['cay'],
          ScoringCategory.generalFood,
          NutritionBasis.per100g,
        ),
        'beverage (gazli_icecek)': (
          ['gazli_icecek'],
          ScoringCategory.beverage,
          NutritionBasis.per100ml,
        ),
        'cheese (peynir)': (
          ['peynir'],
          ScoringCategory.cheese,
          NutritionBasis.per100g,
        ),
        'redMeat (kirmizi_et)': (
          ['kirmizi_et'],
          ScoringCategory.redMeat,
          NutritionBasis.per100g,
        ),
        'fatsOilsNutsSeeds (sivi_yag)': (
          ['sivi_yag'],
          ScoringCategory.fatsOilsNutsSeeds,
          NutritionBasis.per100g,
        ),
      };

      for (final entry in cases.entries) {
        final (tags, category, expectedBasis) = entry.value;

        test(
          '${entry.key}: category resolves confidently, and a generic '
          '(unit-ambiguous) basis now resolves via the deterministic '
          'category-derived fallback (product decision, taxonomy-tag '
          'allowlist)',
          () async {
            final product = _product(categoryTags: tags);
            final result = await _recover(
              product: product,
              staging: _staging(product: product, basis: 'per_100'),
            );

            expect(
              result.evidence!.categoryEvidence.resolvedCategory,
              category,
              reason: 'category must resolve regardless of basis',
            );
            expect(result.classificationReady, isTrue);
            expect(result.basisReady, isTrue);
            expect(result.evidence!.nutritionBasis, expectedBasis);
            expect(
              result.evidence!.nutritionBasisEvidence?.provenance,
              EvidenceProvenance.categoryDerived,
              reason: 'never silently tagged as declaredLabel — this is a '
                  'distinguishable, real provenance',
            );
            expect(
              result.evidence!.nutritionBasisEvidence?.verification,
              EvidenceVerification.verified,
            );
            expect(
              result.blockerReasons,
              isNot(contains('basis_unit_ambiguous')),
            );
          },
        );

        test(
          '${entry.key}: a generic combined "100 g / ml" declaration (the '
          'corrected scraper contract'
          '\'s per_100_generic value) also resolves via the same fallback',
          () async {
            final product = _product(categoryTags: tags);
            final result = await _recover(
              product: product,
              staging: _staging(product: product, basis: 'per_100_generic'),
            );

            expect(result.basisReady, isTrue);
            expect(result.evidence!.nutritionBasis, expectedBasis);
            expect(
              result.evidence!.nutritionBasisEvidence?.provenance,
              EvidenceProvenance.categoryDerived,
            );
          },
        );

        test(
          '${entry.key}: an explicit, independently proven, compatible '
          'basis lets readiness continue',
          () async {
            final product = _product(categoryTags: tags);
            final basisString = expectedBasis == NutritionBasis.per100ml
                ? 'per_100ml'
                : 'per_100g';
            final result = await _recover(
              product: product,
              staging: _staging(product: product, basis: basisString),
            );

            expect(result.classificationReady, isTrue);
            expect(result.basisReady, isTrue);
            expect(result.evidence!.nutritionBasis, expectedBasis);
            expect(
              result.evidence!.nutritionBasisEvidence?.provenance,
              EvidenceProvenance.declaredLabel,
              reason: 'genuinely explicit source evidence is tagged '
                  'declaredLabel, never categoryDerived, even though the '
                  'category fallback would have agreed here',
            );
            expect(result.blockerReasons, isNot(contains('basis_unit_ambiguous')));
            expect(
              result.blockerReasons,
              isNot(contains('nutrition_basis_does_not_match_category')),
            );
          },
        );
      }

      test(
        'a category tag NOT in the fallback allowlist (e.g. a sauce) '
        'remains genuinely ambiguous — the fallback is a closed allowlist, '
        'never the broad resolved ScoringCategory alone',
        () async {
          final product = _product(categoryTags: const ['sos']);
          final result = await _recover(
            product: product,
            staging: _staging(product: product, basis: 'per_100'),
          );

          expect(
            result.evidence!.categoryEvidence.resolvedCategory,
            ScoringCategory.generalFood,
            reason: 'category itself resolves fine — sauces are ordinary '
                'generalFood — but that is exactly why the broad category '
                'alone must never be trusted for basis',
          );
          expect(result.classificationReady, isTrue);
          expect(result.basisReady, isFalse);
          expect(result.evidence!.nutritionBasis, NutritionBasis.unknown);
          expect(result.blockerReasons, contains('basis_unit_ambiguous'));
        },
      );

      test(
        'beverage with an explicit, proven, but INCOMPATIBLE basis (per100g) '
        'is never silently rewritten to per100ml — it blocks',
        () async {
          final product = _product(categoryTags: const ['gazli_icecek']);
          final result = await _recover(
            product: product,
            staging: _staging(product: product, basis: 'per_100g'),
          );

          expect(result.classificationReady, isTrue);
          expect(
            result.evidence!.nutritionBasis,
            NutritionBasis.per100g,
            reason: 'the proven value itself must never be silently '
                'reinterpreted as per100ml just because category is beverage',
          );
          expect(result.finalScoreReady, isFalse);
          expect(
            result.blockerReasons,
            contains('nutrition_basis_does_not_match_category'),
          );
        },
      );

      test(
        'dry tea (cay) never resolves to beverage merely because it is tea '
        '— even with a fully proven per100ml basis',
        () async {
          final product = _product(categoryTags: const ['cay']);
          final result = await _recover(
            product: product,
            staging: _staging(product: product, basis: 'per_100ml'),
          );

          expect(
            result.evidence!.categoryEvidence.resolvedCategory,
            ScoringCategory.generalFood,
          );
          expect(
            result.evidence!.categoryEvidence.resolvedCategory,
            isNot(ScoringCategory.beverage),
          );
          // generalFood expects per100g; an actually-proven per100ml value
          // is then the INCOMPATIBLE one for this (correctly non-beverage)
          // category — proving the category decision itself, independent
          // of this specific basis mismatch, was never influenced by it.
          expect(
            result.blockerReasons,
            contains('nutrition_basis_does_not_match_category'),
          );
        },
      );
    });

    test(
      'qualifying FVL ingredient without a percentage stays blocked',
      () async {
        final result = await _recover(
          product: _product(ingredientsText: 'yulaf, elma püresi, şeker'),
        );

        expect(result.fvlReady, isFalse);
        expect(
          result.evidence!.fvlEvidence.state,
          CompositionPercentageState.unknown,
        );
        expect(result.blockerReasons, contains('fvl_unknown'));
      },
    );

    test('literal qualifying FVL percentage is recovered', () async {
      final result = await _recover(
        product: _product(ingredientsText: 'yulaf, elma püresi %20, şeker'),
      );

      expect(result.fvlReady, isTrue);
      expect(result.evidence!.fvlEvidence.percentage, 20);
      expect(
        result.evidence!.fvlEvidence.provenance,
        EvidenceProvenance.declaredLabel,
      );
    });

    test(
      'Turkish decimal FVL percentages sum from explicit source text',
      () async {
        const ingredients =
            'un, çilek parçaları (%4), çilek püresi (%1,5), şeker. '
            'YUMURTA, SÜT VE SERT KABUKLU MEYVELER İÇEREBİLİR. Aler';
        final result = await _recover(
          product: _product(ingredientsText: ingredients),
        );

        expect(result.fvlReady, isTrue);
        expect(result.evidence!.fvlEvidence.percentage, 5.5);
        expect(
          result.evidence!.fvlEvidence.provenance,
          EvidenceProvenance.declaredLabel,
        );
        expect(
          result.evidence!.fvlEvidence.verification,
          EvidenceVerification.verified,
        );
        expect(result.blockerReasons, isNot(contains('fvl_unknown')));
      },
    );

    test(
      'factor-dependent dried FVL stays unknown even with a percentage',
      () async {
        final result = await _recover(
          product: _product(ingredientsText: 'yulaf, kuru üzüm %20, şeker'),
        );

        expect(result.fvlReady, isFalse);
        expect(result.blockerReasons, contains('fvl_unknown'));
      },
    );

    test(
      'mismatched staging nutrition is not upgraded to declared label',
      () async {
        final product = _product();
        final mismatchedNutrition = _nutrition()..['energy_kj'] = 999;
        final result = await _recover(
          product: product,
          staging: _staging(
            product: product,
            nutritionJson: mismatchedNutrition,
          ),
        );

        expect(result.finalScoreReady, isFalse);
        expect(
          result.evidence!.nutrition.energyKj.provenance,
          EvidenceProvenance.databaseImport,
        );
        expect(result.blockerReasons, contains('nutrition_source_unverified'));
      },
    );

    test(
      'source-complete beverage resolves per100ml and NNS presence or absence',
      () async {
        final presentProduct = _product(
          categoryTags: const ['gazli_icecek'],
          ingredientsText: 'su, şeker, aspartam',
        );
        final present = await _recover(
          product: presentProduct,
          staging: _staging(product: presentProduct, basis: 'per_100ml'),
        );
        final absentProduct = _product(
          categoryTags: const ['gazli_icecek'],
          ingredientsText: 'su, şeker, doğal aroma',
        );
        final absent = await _recover(
          product: absentProduct,
          staging: _staging(product: absentProduct, basis: 'per_100ml'),
        );

        expect(present.evidence!.nutritionBasis, NutritionBasis.per100ml);
        expect(present.nnsReady, isTrue);
        expect(
          present.evidence!.nnsEvidence.state,
          PresenceEvidenceState.present,
        );
        expect(
          present.evidence!.nnsEvidence.provenance,
          EvidenceProvenance.databaseImport,
        );
        expect(absent.nnsReady, isTrue);
        expect(
          absent.evidence!.nnsEvidence.state,
          PresenceEvidenceState.absent,
        );
        expect(absent.blockerReasons, isNot(contains('nns_unknown')));
      },
    );

    test(
      'unverified ingredient metadata cannot prove FVL or NNS absence',
      () async {
        final product = _product(
          categoryTags: const ['gazli_icecek'],
          ingredientsText: 'su, şeker, doğal aroma',
        );
        final result = await _recover(
          product: product,
          staging: _staging(
            product: product,
            ingredientsQuality: 'ingredients_suspicious',
          ),
        );

        expect(
          result.evidence!.ingredientEvidenceCompleteness,
          IngredientEvidenceCompleteness.unknown,
        );
        expect(result.fvlReady, isFalse);
        expect(result.nnsReady, isFalse);
        expect(result.blockerReasons, contains('ingredients_incomplete'));
      },
    );

    // Section G of the methodology/readiness correction (reopened): a
    // staging row whose EFFECTIVE ingredients_quality (after checking both
    // the top-level raw_source_payload.ingredients_quality field AND the
    // nested raw_source_payload.debug.ingredient_quality field — see
    // resolveEffectiveIngredientsQuality) is genuinely null — i.e. neither
    // location has a trusted value at all — cannot be proven
    // source-complete. This is deliberately NOT the same as "the top-level
    // field alone is absent": a real, confirmed production row (see
    // ingredients_quality_provenance_resolver_test.dart) has an absent
    // top-level field but a trusted value in the nested debug location, and
    // that case IS provable — covered separately there. This test exercises
    // the remaining genuine case: nothing trusted anywhere.
    test(
      'a staging row with no trusted ingredients_quality in either known '
      'location cannot be proven source-complete, same as an explicit '
      'suspicious value',
      () {
        final product = _product(
          categoryTags: const ['peynir'],
          ingredientsText: 'pastörize inek sütü, tuz, peynir mayası',
        );
        final staging = _staging(product: product, ingredientsQuality: null);

        expect(
          staging.hasSourceCompleteIngredients(product.ingredientsText),
          isFalse,
          reason:
              'a genuinely absent quality value (checked at both trusted '
              'locations) must never be treated as an implicit pass',
        );
      },
    );

    // Reopened Section G/5 reassessment: a cheese-shaped product whose
    // staging row's raw_source_payload carries the quality judgment ONLY
    // in the nested debug location — the exact real production shape
    // confirmed for "7 Days Çilekli Kruvasan 60 G" and, by the same
    // scraper contract, plausibly explaining a meaningful share of the
    // 311/319 cheese ingredients_incomplete/fvl_unknown blocks — now
    // recovers ingredient completeness generically, with FVL correctly
    // resolving to proven-absent (plain dairy ingredients contain no
    // qualifying FVL items). This does NOT automatically make the product
    // scoreable: fibre is a separate, genuinely undeclared field on this
    // fixture (mirroring real cheese labels that commonly omit it) and
    // must still block independently, exactly as Section E requires.
    test(
      'a cheese product with quality evidence only in raw_source_payload.'
      'debug.ingredient_quality recovers ingredient completeness and FVL '
      'generically, but a genuinely separate missing-fibre blocker still '
      'blocks the product',
      () async {
        final product = _product(
          categoryTags: const ['peynir'],
          ingredientsText: 'pastörize inek sütü, tuz, peynir mayası',
          nutrition: _nutrition()..remove('fiber'),
        );
        final resolvedQuality = resolveEffectiveIngredientsQuality({
          'meta': {'title': 'irrelevant'},
          'debug': {
            'image_front_role': 'unknown',
            'ingredient_quality': 'ingredients_ok',
            'brand_source_method': 'api_metadata',
          },
          'jsonld': null,
          'ingredients_raw': 'İçindekiler: pastörize inek sütü, tuz, peynir mayası',
        });
        expect(
          resolvedQuality,
          'ingredients_ok',
          reason: 'sanity-check the resolver ran before asserting on it',
        );
        final staging = _staging(
          product: product,
          ingredientsQuality: resolvedQuality,
        );
        expect(staging.hasSourceCompleteIngredients(product.ingredientsText), isTrue);

        final recovered = await recovery.recover(
          product: product,
          stagingMatches: [staging],
          ingredientCatalogue: const [],
        );

        expect(
          recovered.evidence!.ingredientEvidenceCompleteness,
          IngredientEvidenceCompleteness.complete,
        );
        expect(
          recovered.evidence!.fvlEvidence.state,
          CompositionPercentageState.provenAbsent,
          reason:
              'plain dairy ingredients contain no qualifying FVL item, so '
              'completeness alone is enough to prove absence',
        );
        expect(
          recovered.blockerReasons,
          isNot(contains('ingredients_incomplete')),
        );
        expect(recovered.blockerReasons, isNot(contains('fvl_unknown')));
        // The honest, required caveat: recovering ingredient completeness
        // is not sufficient for final score readiness by itself. A
        // genuinely separate, undeclared fibre value must still block.
        expect(
          recovered.blockerReasons,
          contains('missing_fiber'),
          reason:
              'restoring ingredient completeness must never be conflated '
              'with restoring nutrition completeness',
        );
        expect(recovered.finalScoreReady, isFalse);
      },
    );

    test(
      'ordinary unmatched ingredients do not block additive quality',
      () async {
        final result = await _recover(
          product: _product(ingredientsText: 'mısır unu, ayçiçek yağı, tuz'),
        );

        expect(result.additiveReady, isTrue);
        expect(
          result.blockerReasons,
          isNot(contains('canonical_additive_unresolved')),
        );
      },
    );

    test('unknown additive-like ingredient remains a blocker', () async {
      final result = await _recover(
        product: _product(
          ingredientsText: 'mısır unu, bilinmeyen koruyucu, tuz',
        ),
      );

      expect(result.additiveReady, isFalse);
      expect(result.blockerReasons, contains('canonical_additive_unresolved'));
    });

    test(
      'functional parents do not block and generic aroma is out of additive scope',
      () async {
        const text =
            'emülgatör (yağ asitlerinin mono- ve digliseritleri), '
            'koruyucular (kalsiyum propiyonat, potasyum sorbat), '
            'jelleştirici (pektin), asitlik düzenleyici (sitrik asit), '
            'aroma vericiler';
        const matcher = IngredientMatcherService();
        final matching = await matcher.matchIngredients(
          text,
          _functionalChildCatalogue(),
        );
        final assessment = const CanonicalIngredientRiskService()
            .assessForScoring(matching);

        expect(assessment.unresolvedIngredients, isEmpty);
        expect(assessment.outOfScopeFlavouringEvidence, hasLength(1));
        expect(assessment.outOfScopeFlavouringEvidence.single.sourceTokens, [
          'aroma vericiler',
        ]);
        final unresolvedSourceTokens = assessment.unresolvedIngredients
            .expand((ingredient) => ingredient.sourceTokens)
            .toSet();
        expect(
          unresolvedSourceTokens.intersection(const {
            'emülgatör',
            'koruyucu',
            'jelleştirici',
            'asitlik düzenleyici',
          }),
          isEmpty,
        );
      },
    );

    test(
      '7 Days recovery becomes final-score-ready after reviewed risk decisions',
      () async {
        const ingredients =
            'un, çilek parçaları (%4), çilek püresi (%1,5), şeker, '
            'emülgatör (yağ asitlerinin mono- ve digliseritleri), '
            'koruyucular (kalsiyum propiyonat, potasyum sorbat), '
            'jelleştirici (pektin), asitlik düzenleyici (sitrik asit), '
            'aroma vericiler';
        final product = _product(
          name: '7 Days Çilekli Kruvasan 60 G',
          ingredientsText: ingredients,
        );
        final result = await recovery.recover(
          product: product,
          stagingMatches: [_staging(product: product)],
          ingredientCatalogue: _sevenDaysCatalogueWithoutE282(),
        );

        expect(result.evidence!.fvlEvidence.percentage, 5.5);
        expect(result.fvlReady, isTrue);
        expect(result.additiveReady, isTrue);
        expect(result.finalScoreReady, isTrue);
        expect(result.blockerReasons, isEmpty);
      },
    );

    test('product name never supplies legacy classification', () async {
      final result = await _recover(
        product: _product(
          name: 'Gazlı İçecek Cips Peynir',
          categoryTags: const [],
          canonicalCategory: null,
        ),
      );

      expect(result.classificationReady, isFalse);
      // Basis independence: category being unresolved (the name alone
      // suggests several categories, none trusted) must not retroactively
      // make the separately, independently proven basis ambiguous too —
      // see the "missing category with proven basis" test above.
      expect(result.evidence!.nutritionBasis, NutritionBasis.per100g);
      expect(result.blockerReasons, contains('missing_classification'));
    });

    test('identical duplicate staging evidence is deterministic', () async {
      final result = await recovery.recover(
        product: _product(),
        stagingMatches: [
          _staging(id: 'staging-b'),
          _staging(id: 'staging-a'),
        ],
        ingredientCatalogue: const [],
      );

      expect(result.canWrite, isTrue);
      expect(result.selectedStagingId, 'staging-a');
    });

    test('conflicting duplicate staging evidence is blocked', () async {
      final result = await recovery.recover(
        product: _product(),
        stagingMatches: [
          _staging(id: 'staging-a'),
          _staging(id: 'staging-b', basis: 'unknown'),
        ],
        ingredientCatalogue: const [],
      );

      expect(result.canWrite, isFalse);
      expect(result.blockerReasons, contains('ambiguous_staging_match'));
    });
  });

  group('legacy evidence backfill runner', () {
    group('only-final-score-ready write filter', () {
      test('ready product writes with flag', () async {
        final source = _FakeDataSource(products: [_product()]);
        final summary = await _run(
          source,
          dryRun: false,
          maxProducts: 1,
          onlyFinalScoreReady: true,
        );

        expect(summary.onlyFinalScoreReady, isTrue);
        expect(summary.finalScoreReady, 1);
        expect(summary.wouldWrite, 1);
        expect(summary.written, 1);
        expect(source.writeCalls, 1);
      });

      test('recoverable partial evidence does not write with flag', () async {
        final nutrition = _nutrition()..remove('fiber');
        final source = _FakeDataSource(
          products: [_product(nutrition: nutrition)],
        );
        final summary = await _run(
          source,
          dryRun: false,
          maxProducts: 1,
          onlyFinalScoreReady: true,
        );

        expect(summary.finalScoreReady, 0);
        expect(summary.notReady, 1);
        expect(summary.blockerReasons['missing_fiber'], 1);
        expect(summary.wouldWrite, 0);
        expect(summary.written, 0);
        expect(source.writeCalls, 0);
        expect(source.products.single.scoringEvidence, isNull);
      });

      test(
        'without flag partial-evidence behavior remains unchanged',
        () async {
          final nutrition = _nutrition()..remove('fiber');
          final source = _FakeDataSource(
            products: [_product(nutrition: nutrition)],
          );
          final summary = await _run(source, dryRun: false, maxProducts: 1);

          expect(summary.onlyFinalScoreReady, isFalse);
          expect(summary.finalScoreReady, 0);
          expect(summary.wouldWrite, 1);
          expect(summary.written, 1);
          expect(source.writeCalls, 1);
          expect(source.products.single.scoringEvidence, isNotNull);
        },
      );

      test('dry-run performs zero writes with flag', () async {
        final source = _FakeDataSource(products: [_product()]);
        final summary = await _run(
          source,
          dryRun: true,
          onlyFinalScoreReady: true,
        );

        expect(summary.finalScoreReady, 1);
        expect(summary.wouldWrite, 1);
        expect(summary.written, 0);
        expect(source.writeCalls, 0);
        expect(source.products.single.scoringEvidence, isNull);
      });

      test('existing evidence is not overwritten with flag', () async {
        final existing = ScoringEvidenceSnapshot();
        final source = _FakeDataSource(
          products: [_product(scoringEvidence: existing)],
        );
        final summary = await _run(
          source,
          dryRun: false,
          maxProducts: 1,
          onlyFinalScoreReady: true,
        );

        expect(summary.existingScoringEvidence, 1);
        expect(summary.wouldWrite, 0);
        expect(summary.written, 0);
        expect(source.writeCalls, 0);
        expect(source.products.single.scoringEvidence, same(existing));
      });
    });

    test('dry-run performs zero writes', () async {
      final source = _FakeDataSource(products: [_product()]);
      final summary = await _run(source, dryRun: true);

      expect(summary.wouldWrite, 1);
      expect(summary.written, 0);
      expect(source.writeCalls, 0);
      expect(source.products.single.scoringEvidence, isNull);
    });

    test('apply is bounded by max-products', () async {
      final source = _FakeDataSource(
        products: [
          _product(id: '0001'),
          _product(id: '0002'),
          _product(id: '0003'),
        ],
      );
      final summary = await _run(source, dryRun: false, maxProducts: 2);

      expect(summary.totalProductsExamined, 2);
      expect(summary.written, 2);
      expect(summary.reachedLimit, isTrue);
      expect(source.writeCalls, 2);
    });

    test('resume cursor starts strictly after the supplied product', () async {
      final source = _FakeDataSource(
        products: [
          _product(id: '0001'),
          _product(id: '0002'),
          _product(id: '0003'),
        ],
      );
      final summary = await _run(
        source,
        dryRun: true,
        startAfterProductId: '0001',
      );

      expect(summary.totalProductsExamined, 2);
      expect(summary.lastExaminedCursor, '0003');
      expect(summary.safeResumeCursor, '0003');
    });

    test('existing evidence is never overwritten', () async {
      final existing = ScoringEvidenceSnapshot();
      final source = _FakeDataSource(
        products: [_product(scoringEvidence: existing)],
      );
      final summary = await _run(source, dryRun: false, maxProducts: 1);

      expect(summary.existingScoringEvidence, 1);
      expect(summary.wouldWrite, 0);
      expect(source.writeCalls, 0);
      expect(source.products.single.scoringEvidence, same(existing));
    });

    test('conditional writes make repeated apply idempotent', () async {
      final source = _FakeDataSource(products: [_product()]);
      final first = await _run(source, dryRun: false, maxProducts: 1);
      final second = await _run(source, dryRun: false, maxProducts: 1);

      expect(first.written, 1);
      expect(second.written, 0);
      expect(second.existingScoringEvidence, 1);
      expect(source.writeCalls, 1);
    });

    test('a per-product write error does not stop later products', () async {
      final source = _FakeDataSource(
        products: [
          _product(id: '0001'),
          _product(id: '0002'),
          _product(id: '0003'),
        ],
        failingWriteIds: const {'0002'},
      );
      final summary = await _run(source, dryRun: false, maxProducts: 3);

      expect(summary.errors, 1);
      expect(summary.written, 2);
      expect(summary.failedProductIds, ['0002']);
      expect(summary.lastExaminedCursor, '0003');
      expect(summary.safeResumeCursor, '0001');
      expect(summary.halted, isFalse);
    });

    test(
      'formatter cannot leak credential text from swallowed failures',
      () async {
        const secret = 'service-role-secret-must-not-appear';
        final source = _FakeDataSource(
          products: [_product()],
          catalogueError: StateError(secret),
        );
        final summary = await _run(source, dryRun: true);
        const formatter = LegacyScoringEvidenceBackfillFormatter();

        expect(summary.halted, isTrue);
        expect(formatter.formatSummary(summary), isNot(contains(secret)));
      },
    );
  });
}

Future<LegacyScoringEvidenceRecoveryResult> _recover({
  Product? product,
  LegacyStagingScoringEvidence? staging,
}) {
  final target = product ?? _product();
  return const LegacyScoringEvidenceRecoveryService().recover(
    product: target,
    stagingMatches: [staging ?? _staging(product: target)],
    ingredientCatalogue: const [],
  );
}

Future<LegacyScoringEvidenceBackfillSummary> _run(
  _FakeDataSource source, {
  required bool dryRun,
  int? maxProducts,
  String? startAfterProductId,
  bool onlyFinalScoreReady = false,
}) {
  return LegacyScoringEvidenceBackfillRunner(dataSource: source).run(
    LegacyScoringEvidenceBackfillOptions(
      dryRun: dryRun,
      onlyFinalScoreReady: onlyFinalScoreReady,
      batchSize: 2,
      maxProducts: maxProducts,
      startAfterProductId: startAfterProductId,
    ),
  );
}

Product _product({
  String id = '0001',
  String name = 'Legacy product',
  Map<String, dynamic>? nutrition,
  List<String>? categoryTags = const ['cips_kraker'],
  String? canonicalCategory,
  String ingredientsText = 'mısır unu, bitkisel yağ, tuz',
  ScoringEvidenceSnapshot? scoringEvidence,
}) {
  final now = DateTime.utc(2026, 8, 8);
  return Product(
    id: id,
    barcode: '8690000000000',
    name: name,
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(nutrition ?? _nutrition()),
    source: 'web_scraper:migros',
    sourceUrl: 'https://www.migros.com.tr/product-$id',
    verificationStatus: 'imported',
    categoryTags: categoryTags,
    canonicalCategory: canonicalCategory,
    scoringEvidence: scoringEvidence,
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, dynamic> _nutrition() => {
  'energy_kj': 840,
  'energy_kcal': 200,
  'fat': 3,
  'saturated_fat': 1,
  'carbohydrates': 15,
  'sugars': 5,
  'fiber': 2,
  'proteins': 4,
  'salt': 0.5,
};

List<Ingredient> _functionalChildCatalogue() {
  final now = DateTime.utc(2026, 8, 8);
  Ingredient ingredient({
    required String id,
    required String name,
    required String normalizedName,
    required String risk,
    required String eCode,
    required String group,
  }) => Ingredient(
    id: id,
    name: name,
    normalizedName: normalizedName,
    eCode: eCode,
    additiveGroup: group,
    riskLevel: risk,
    createdAt: now,
    updatedAt: now,
  );

  return [
    ingredient(
      id: 'e471',
      name: 'Mono ve Digliseritler',
      normalizedName: 'mono ve digliseritler',
      risk: 'low',
      eCode: 'E471',
      group: 'emülgatör',
    ),
    ingredient(
      id: 'e282',
      name: 'Kalsiyum Propiyonat',
      normalizedName: 'kalsiyum propiyonat',
      risk: 'low',
      eCode: 'E282',
      group: 'koruyucu',
    ),
    ingredient(
      id: 'e202',
      name: 'Potasyum Sorbat',
      normalizedName: 'potasyum sorbat',
      risk: 'low',
      eCode: 'E202',
      group: 'koruyucu',
    ),
    ingredient(
      id: 'e440',
      name: 'Pektin',
      normalizedName: 'pektin',
      risk: 'low',
      eCode: 'E440',
      group: 'jelleştirici',
    ),
    ingredient(
      id: 'e330',
      name: 'Sitrik Asit',
      normalizedName: 'sitrik asit',
      risk: 'low',
      eCode: 'E330',
      group: 'asitlik düzenleyici',
    ),
  ];
}

List<Ingredient> _sevenDaysCatalogueWithoutE282() => _functionalChildCatalogue()
    .where((ingredient) => ingredient.eCode != 'E282')
    .toList(growable: false);

// Basis independence correction: 'per_100' (the ONLY value the real
// historical Migros scraper contract ever produces — see
// _recoveredBasisFromEvidence's doc comment) never distinguishes g from
// ml and therefore now correctly resolves to NutritionBasis.unknown, not
// a category-invented value. Tests whose actual subject is something OTHER
// than basis (dedup, fibre recovery, FVL, additive readiness, etc.) need a
// fixture with genuinely PROVEN basis evidence to exercise what they are
// actually testing — 'per_100g' is the forward-compatible, explicitly
// supported distinct-unit string (never produced by the real Migros
// contract today, but a legitimate, sanctioned form of trusted evidence
// for a fixture that intentionally models proof, same as "existing
// trusted/versioned admin evidence" would). Tests specifically about basis
// ambiguity itself pass 'per_100' explicitly — see the dedicated
// "basis independence" group below.
LegacyStagingScoringEvidence _staging({
  String id = 'staging-1',
  String? basis = 'per_100g',
  List<String> warnings = const [],
  Product? product,
  String? ingredientsQuality = 'ingredients_ok',
  Map<String, dynamic>? nutritionJson,
}) {
  final target = product ?? _product();
  return LegacyStagingScoringEvidence(
    id: id,
    sourceUrl: target.sourceUrl!,
    nutritionBasis: basis,
    nutritionWarnings: warnings,
    source: 'web_scraper:migros',
    ingredientsSource: 'web_scraper:migros',
    ingredientsRaw: 'İçindekiler: ${target.ingredientsText}',
    ingredientsText: target.ingredientsText,
    ingredientsQuality: ingredientsQuality,
    nutritionSource: 'web_scraper:migros',
    nutritionStrategy: 'dom',
    nutritionJson: nutritionJson ?? target.nutrition?.toMap(),
  );
}

class _FakeDataSource implements LegacyScoringEvidenceBackfillDataSource {
  _FakeDataSource({
    required List<Product> products,
    this.catalogueError,
    this.failingWriteIds = const {},
  }) : products = [...products]
         ..sort((left, right) => left.id.compareTo(right.id));

  final List<Product> products;
  final Object? catalogueError;
  final Set<String> failingWriteIds;
  int writeCalls = 0;

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async {
    if (catalogueError != null) throw catalogueError!;
    return const [];
  }

  @override
  Future<Product?> fetchProductById(String productId) async {
    return products.where((product) => product.id == productId).firstOrNull;
  }

  @override
  Future<List<Product>> fetchProductsAfter({
    required String? afterProductId,
    required int limit,
  }) async {
    return products
        .where(
          (product) =>
              afterProductId == null ||
              product.id.compareTo(afterProductId) > 0,
        )
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<Map<String, List<LegacyStagingScoringEvidence>>> fetchStagingMatches(
    Set<String> sourceUrls,
  ) async {
    return {
      for (final sourceUrl in sourceUrls)
        sourceUrl: [
          _staging(
            id: 'staging-$sourceUrl',
            product: products.firstWhere(
              (product) => product.sourceUrl == sourceUrl,
            ),
          ),
        ],
    };
  }

  @override
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence,
  ) async {
    if (failingWriteIds.contains(productId)) {
      throw StateError('simulated write failure');
    }
    final index = products.indexWhere((product) => product.id == productId);
    if (index < 0 || products[index].scoringEvidence != null) return false;
    writeCalls++;
    products[index] = _copyWithEvidence(products[index], evidence);
    return true;
  }
}

Product _copyWithEvidence(Product product, ScoringEvidenceSnapshot evidence) {
  return Product(
    id: product.id,
    barcode: product.barcode,
    name: product.name,
    normalizedName: product.normalizedName,
    brand: product.brand,
    categoryId: product.categoryId,
    imageUrl: product.imageUrl,
    ingredientsText: product.ingredientsText,
    nutritionText: product.nutritionText,
    source: product.source,
    sourceUrl: product.sourceUrl,
    verificationStatus: product.verificationStatus,
    searchKeywords: product.searchKeywords,
    categoryTags: product.categoryTags,
    canonicalCategory: product.canonicalCategory,
    canonicalSubcategory: product.canonicalSubcategory,
    scoringEvidence: evidence,
    createdAt: product.createdAt,
    updatedAt: product.updatedAt,
  );
}
