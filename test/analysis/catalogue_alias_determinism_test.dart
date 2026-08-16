import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

/// Regression coverage for the final Etiketly scoring hardening pass:
/// generic X-yağı/X-tozu fuzzy false-positive matches, source-order-
/// dependent duplicate canonical rows, and the exact production catalogue
/// rows captured in tmp/canonical_catalogue_conflict_diagnostic_output.txt.
/// Row ids below are the real production canonical ids; fixtures otherwise
/// reproduce the exact aliases/e_code/risk_level captured in that
/// diagnostic (and, where noted, the state after the accompanying
/// migration 20260815010000_correct_ingredient_catalogue_alias_overlaps.sql
/// is applied). Nothing here is product/brand/source-specific — every
/// assertion is about generic ingredient-identity resolution.
void main() {
  const matcher = IngredientMatcherService();
  const riskService = CanonicalIngredientRiskService();

  Ingredient row({
    required String id,
    required String name,
    required String normalizedName,
    String? eCode,
    String riskLevel = 'low',
    List<String>? aliases,
    List<String>? alternativeNames,
    List<String>? commonNames,
    List<String>? englishNames,
  }) {
    final now = DateTime.utc(2026, 8, 15);
    return Ingredient(
      id: id,
      name: name,
      normalizedName: normalizedName,
      eCode: eCode,
      riskLevel: riskLevel,
      aliases: aliases,
      alternativeNames: alternativeNames,
      commonNames: commonNames,
      englishNames: englishNames,
      createdAt: now,
      updatedAt: now,
    );
  }

  group(
    'Fuzzy false-positive fix — generic shared-suffix ingredient families',
    () {
      final onlyPalm = [
        row(
          id: '650e8400-e29b-41d4-a716-446655440007',
          name: 'Palm Yağı',
          normalizedName: 'palm yağı',
          riskLevel: 'medium',
          aliases: const ['palm yağı'],
        ),
      ];

      for (final falsePositive in const [
        'Pamuk Yağı',
        'Kanola Yağı',
        'Ayçiçek Yağı',
        'Mısır Yağı',
      ]) {
        test('$falsePositive must not fuzzy-match Palm Yağı', () async {
          final match = await matcher.matchSingleIngredient(
            falsePositive,
            onlyPalm,
          );
          expect(
            match.matchType,
            MatchType.unmatched,
            reason:
                'a shared generic suffix ("yağı") must not by itself make two '
                'distinct oils fuzzy-compatible',
          );
        });
      }

      test(
        'a genuinely different-source declaration also stays unmatched',
        () async {
          final match = await matcher.matchSingleIngredient(
            'Palm Çekirdeği Yağı ve Türevleri',
            onlyPalm,
          );
          expect(match.matchType, MatchType.unmatched);
        },
      );

      test(
        'exact spelling still resolves normally (fix removes false positives only)',
        () async {
          final match = await matcher.matchSingleIngredient(
            'Palm Yağı',
            onlyPalm,
          );
          expect(match.matchType, MatchType.exactMatch);
          expect(match.matchedIngredient?.name, 'Palm Yağı');
        },
      );

      test(
        'other shared-suffix families: X tozu does not cross-match',
        () async {
          final onlySutTozu = [
            row(
              id: 'sut-tozu',
              name: 'Süt Tozu',
              normalizedName: 'süt tozu',
              riskLevel: 'medium',
            ),
          ];
          final match = await matcher.matchSingleIngredient(
            'Peynir Tozu',
            onlySutTozu,
          );
          expect(
            match.matchType,
            MatchType.unmatched,
            reason: 'shared "tozu" suffix alone must not imply compatibility',
          );
        },
      );

      test(
        'other shared-suffix families: X şurubu does not cross-match',
        () async {
          final onlyGlikozSurubu = [
            row(
              id: 'glikoz-surubu',
              name: 'Glikoz Şurubu',
              normalizedName: 'glikoz şurubu',
              riskLevel: 'high',
            ),
          ];
          final match = await matcher.matchSingleIngredient(
            'Fruktoz Şurubu',
            onlyGlikozSurubu,
          );
          expect(match.matchType, MatchType.unmatched);
        },
      );
    },
  );

  group('Deterministic candidate precedence — real duplicate canonical rows', () {
    Ingredient palmYagi() => row(
      id: '650e8400-e29b-41d4-a716-446655440007',
      name: 'Palm Yağı',
      normalizedName: 'palm yağı',
      riskLevel: 'medium',
      aliases: const ['palm yağı'],
      alternativeNames: const ['palm oil'],
      commonNames: const ['palm yağı'],
      englishNames: const ['palm oil'],
    );
    Ingredient palmiyeYagiLower() => row(
      id: '0070dac1-8a10-48c2-81fb-061cfdef643c',
      name: 'Palmiye yağı',
      normalizedName: 'palmiye yagi',
      riskLevel: 'medium',
      alternativeNames: const ['Palm oil'],
      commonNames: const ['Palmiye yağı'],
      englishNames: const ['Palm oil'],
    );
    Ingredient palmiyeYagiUpper() => row(
      id: '69b11b82-200e-48c3-ad49-110fe192b1b8',
      name: 'Palmiye Yağı',
      normalizedName: 'palmiye yağı',
      riskLevel: 'medium',
      aliases: const ['palm oil', 'palm fat', 'palmyağ', 'rafine palmyağ'],
    );

    test(
      'palm oil resolves to the same canonical id regardless of row order',
      () async {
        final forward = [palmYagi(), palmiyeYagiLower(), palmiyeYagiUpper()];
        final reversed = [palmiyeYagiUpper(), palmiyeYagiLower(), palmYagi()];
        final shuffled = [palmiyeYagiLower(), palmYagi(), palmiyeYagiUpper()];

        final m1 = await matcher.matchSingleIngredient('palm oil', forward);
        final m2 = await matcher.matchSingleIngredient('palm oil', reversed);
        final m3 = await matcher.matchSingleIngredient('palm oil', shuffled);

        expect(m1.matchedIngredient?.id, isNotNull);
        expect(m2.matchedIngredient?.id, m1.matchedIngredient?.id);
        expect(m3.matchedIngredient?.id, m1.matchedIngredient?.id);
      },
    );

    test(
      'palm yağı / palmiye yağı / palmyağ / rafine palmyağ each resolve uniquely and deterministically',
      () async {
        final rows = [palmYagi(), palmiyeYagiLower(), palmiyeYagiUpper()];
        final cases = <String, String>{
          'palm yağı': '650e8400-e29b-41d4-a716-446655440007',
          'palmiye yağı': '69b11b82-200e-48c3-ad49-110fe192b1b8',
          'palmyağ': '69b11b82-200e-48c3-ad49-110fe192b1b8',
          'rafine palmyağ': '69b11b82-200e-48c3-ad49-110fe192b1b8',
        };
        for (final entry in cases.entries) {
          final match = await matcher.matchSingleIngredient(entry.key, rows);
          expect(
            match.matchedIngredient?.id,
            entry.value,
            reason:
                'token "${entry.key}" must deterministically select ${entry.value}',
          );
        }
      },
    );

    test(
      'E471 duplicate: the row with a verified e_code identity wins over an alias-only duplicate, regardless of order',
      () async {
        final withECode = row(
          id: '1611b8b5-0419-49c7-af3e-9317824b70ab',
          name: 'Mono ve digliseritler',
          normalizedName: 'mono ve digliseritler',
          eCode: 'E471',
          aliases: const ['E471', 'e471'],
          alternativeNames: const ['Mono and diglycerides'],
        );
        final aliasOnlyDuplicate = row(
          id: 'de11207d-c26f-4411-853d-92c13f106608',
          name: 'Mono- ve Digliseritler',
          normalizedName: 'mono- ve digliseritler',
          aliases: const [
            'mono and diglycerides',
            'monoglycerides',
            'diglycerides',
          ],
        );

        for (final rows in [
          [withECode, aliasOnlyDuplicate],
          [aliasOnlyDuplicate, withECode],
        ]) {
          final match = await matcher.matchSingleIngredient(
            'mono and diglycerides',
            rows,
          );
          expect(match.matchedIngredient?.id, withECode.id);
        }
      },
    );
  });

  group('Whey / milk-protein / milk-powder alias separation (real ids)', () {
    // Reflects the state AFTER
    // 20260815010000_correct_ingredient_catalogue_alias_overlaps.sql:
    // Peynir Altı Suyu Tozu keeps only 'whey powder'.
    List<Ingredient> rowsAfterMigration() => [
      row(
        id: 'abdc4ecd-e7f7-4761-812c-35559941886c',
        name: 'Peynir Altı Suyu Tozu',
        normalizedName: 'peynir altı suyu tozu',
        aliases: const ['whey powder'],
      ),
      row(
        id: '523393de-6271-48d6-a1d8-392ef6362d53',
        name: 'Protein (Peynir Altı Suyu Proteini)',
        normalizedName: 'protein (peynir altı suyu proteini)',
        aliases: const [
          'whey protein',
          'protein concentrate',
          'milk protein',
          'peynir altı suyu',
        ],
      ),
      row(
        id: '35cb460e-7a7d-4978-9f6e-fe0be5659f1d',
        name: 'Süt Tozunu',
        normalizedName: 'süt tozunu',
        aliases: const ['milk powder', 'powdered milk', 'dried milk'],
      ),
    ];

    test('each token resolves to its own distinct concept', () async {
      final rows = rowsAfterMigration();
      final cases = <String, String>{
        'peynir altı suyu tozu': 'abdc4ecd-e7f7-4761-812c-35559941886c',
        'whey powder': 'abdc4ecd-e7f7-4761-812c-35559941886c',
        'whey protein': '523393de-6271-48d6-a1d8-392ef6362d53',
        'milk powder': '35cb460e-7a7d-4978-9f6e-fe0be5659f1d',
      };
      for (final entry in cases.entries) {
        final match = await matcher.matchSingleIngredient(entry.key, rows);
        expect(
          match.matchedIngredient?.id,
          entry.value,
          reason: 'token "${entry.key}" must resolve to ${entry.value}',
        );
      }
    });

    test(
      'separation is order-independent (no longer relies on id tie-break luck)',
      () async {
        final forward = rowsAfterMigration();
        final reversed = rowsAfterMigration().reversed.toList();
        for (final token in ['whey protein', 'milk powder', 'whey powder']) {
          final m1 = await matcher.matchSingleIngredient(token, forward);
          final m2 = await matcher.matchSingleIngredient(token, reversed);
          expect(m1.matchedIngredient?.id, m2.matchedIngredient?.id);
        }
      },
    );
  });

  group('catalogueRiskMismatch — real abdc4ecd row', () {
    test(
      'BEFORE migration: the documented production aliases reproduce the exact catalogueRiskMismatch',
      () {
        final wheyRow = row(
          id: 'abdc4ecd-e7f7-4761-812c-35559941886c',
          name: 'Peynir Altı Suyu Tozu',
          normalizedName: 'peynir altı suyu tozu',
          aliases: const ['whey powder', 'whey protein', 'milk powder'],
        );
        final match = IngredientMatch(
          originalToken: 'peynir altı suyu tozu',
          normalizedText: 'peynir altı suyu tozu',
          matchedIngredient: wheyRow,
          matchedToken: 'peynir altı suyu tozu',
          matchType: MatchType.exactMatch,
          confidenceScore: 1.0,
          shouldAffectAnalysis: true,
          needsUserConfirmation: false,
        );
        final assessment = riskService.assess(
          IngredientMatchingResult(matches: [match]),
        );
        final item = assessment.recognizedIngredients.single;
        expect(item.riskLevel, CanonicalRiskLevel.unknown);
        expect(
          item.conflicts.map((c) => c.type),
          contains(CanonicalRiskConflictType.catalogueRiskMismatch),
        );
        expect(
          item.conflicts.single.ingredientCatalogueRisk,
          CanonicalRiskLevel.low,
        );
        expect(
          item.conflicts.single.reviewedCatalogueRisk,
          CanonicalRiskLevel.medium,
          reason:
              "caused by the row's own 'milk powder' alias colliding with "
              "the static reviewed catalogue's unrelated generic süt tozu "
              'entry (riskLevel: medium)',
        );
      },
    );

    test(
      'AFTER migration: no genuine reviewed-risk disagreement remains, risk resolves to the trusted low value',
      () {
        final wheyRow = row(
          id: 'abdc4ecd-e7f7-4761-812c-35559941886c',
          name: 'Peynir Altı Suyu Tozu',
          normalizedName: 'peynir altı suyu tozu',
          aliases: const ['whey powder'],
        );
        final match = IngredientMatch(
          originalToken: 'peynir altı suyu tozu',
          normalizedText: 'peynir altı suyu tozu',
          matchedIngredient: wheyRow,
          matchedToken: 'peynir altı suyu tozu',
          matchType: MatchType.exactMatch,
          confidenceScore: 1.0,
          shouldAffectAnalysis: true,
          needsUserConfirmation: false,
        );
        final assessment = riskService.assess(
          IngredientMatchingResult(matches: [match]),
        );
        final item = assessment.recognizedIngredients.single;
        expect(item.riskLevel, CanonicalRiskLevel.low);
        expect(item.conflicts, isEmpty);
      },
    );
  });

  group('catalogue containsAny substring boundary', () {
    test('true positive: Turkish suffix-inflected phrase still matches', () {
      final ingredient = row(
        id: 'x1',
        name: 'yağsız süt tozuna',
        normalizedName: 'yağsız süt tozuna',
      );
      expect(reviewedCatalogRiskLevelForIngredient(ingredient), isNotNull);
    });

    test(
      'true positive: nested mono ve digliserit suffix phrase still matches',
      () {
        final ingredient = row(
          id: 'x2',
          name: 'yağ asitlerinin mono ve digliseritleri',
          normalizedName: 'yağ asitlerinin mono ve digliseritleri',
        );
        expect(reviewedCatalogRiskLevelForIngredient(ingredient), isNotNull);
      },
    );

    test(
      'false collision: a short containsAny token fused onto an unrelated word must not match',
      () {
        final ingredient = row(
          id: 'x3',
          name: 'xbht destekli bileşen',
          normalizedName: 'xbht destekli bileşen',
        );
        expect(reviewedCatalogRiskLevelForIngredient(ingredient), isNull);
      },
    );

    test(
      'the real abdc4ecd row (post-migration aliases) no longer matches the unrelated süt tozu catalogue entry',
      () {
        final ingredient = row(
          id: 'abdc4ecd-e7f7-4761-812c-35559941886c',
          name: 'Peynir Altı Suyu Tozu',
          normalizedName: 'peynir altı suyu tozu',
          aliases: const ['whey powder'],
        );
        expect(reviewedCatalogRiskLevelForIngredient(ingredient), isNull);
      },
    );
  });

  group(
    'E471 standalone-label fail-closed + nested-child resolution (real duplicate rows)',
    () {
      List<Ingredient> e471Rows() => [
        row(
          id: '1611b8b5-0419-49c7-af3e-9317824b70ab',
          name: 'Mono ve digliseritler',
          normalizedName: 'mono ve digliseritler',
          eCode: 'E471',
          aliases: const ['E471', 'e471'],
          alternativeNames: const ['Mono and diglycerides'],
        ),
        // Post-migration: 'emülgatör' alias removed from the duplicate row.
        row(
          id: 'de11207d-c26f-4411-853d-92c13f106608',
          name: 'Mono- ve Digliseritler',
          normalizedName: 'mono- ve digliseritler',
          aliases: const [
            'mono and diglycerides',
            'monoglycerides',
            'diglycerides',
          ],
        ),
      ];

      test(
        'a standalone undeclared emülgatör cannot resolve to E471',
        () async {
          final result = await matcher.matchIngredients(
            'emülgatör',
            e471Rows(),
          );
          expect(result.getConfirmedMatches(), isEmpty);
        },
      );

      test(
        'emülgatör: yağ asitlerinin mono ve digliseritleri resolves the concrete E471 child',
        () async {
          final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
            'emülgatör: yağ asitlerinin mono ve digliseritleri, tuz',
          );
          expect(tokens, isNot(contains('emülgatör')));
          expect(tokens, contains('mono ve digliseritler'));

          final matchResult = await matcher.matchIngredientTokens(
            tokens,
            e471Rows(),
          );
          final assessment = riskService.assessForScoring(matchResult);
          expect(
            assessment.recognizedIngredients.map((i) => i.eCode),
            contains('E471'),
          );
          expect(assessment.unresolvedIngredients, isEmpty);
        },
      );
    },
  );

  group('E322 / Lesitin source specificity (post-migration aliases)', () {
    List<Ingredient> lesitinRows() => [
      row(
        id: '650e8400-e29b-41d4-a716-446655440008',
        name: 'Lesitin',
        normalizedName: 'lesitin',
        aliases: const ['lesitin', 'E322', 'E-322'],
        alternativeNames: const ['lecithin'],
      ),
      row(
        id: 'aafbf812-e57a-40a2-9567-4b890c425457',
        name: 'Soya Lesitin',
        normalizedName: 'soya lesitin',
        aliases: const ['soy lecithin'],
      ),
    ];

    test(
      'generic tokens (no declared source) resolve to the generic Lesitin row',
      () async {
        final rows = lesitinRows();
        for (final token in ['lesitin', 'lecithin', 'E322', 'E-322']) {
          final match = await matcher.matchSingleIngredient(token, rows);
          expect(
            match.matchedIngredient?.id,
            '650e8400-e29b-41d4-a716-446655440008',
            reason:
                'token "$token" does not declare a source and must not '
                'fabricate a soy-specific identity',
          );
        }
      },
    );

    test(
      'explicitly soy-qualified tokens resolve to the soy-specific row',
      () async {
        final rows = lesitinRows();
        final soyLecithin = await matcher.matchSingleIngredient(
          'soy lecithin',
          rows,
        );
        expect(
          soyLecithin.matchedIngredient?.id,
          'aafbf812-e57a-40a2-9567-4b890c425457',
        );

        final soyaLesitini = await matcher.matchSingleIngredient(
          'soya lesitini',
          rows,
        );
        expect(
          soyaLesitini.matchedIngredient?.id,
          'aafbf812-e57a-40a2-9567-4b890c425457',
          reason: 'the raw label explicitly declares "soya" here',
        );
      },
    );
  });

  group('E450 / sodium acid pyrophosphate (post-migration alias)', () {
    List<Ingredient> phosphateFamily() => [
      row(
        id: '0b77c066-6c85-4063-a241-e337aea1144e',
        name: 'Difosfat',
        normalizedName: 'difosfat',
        eCode: 'E450',
        riskLevel: 'medium',
        aliases: const [
          'E450',
          'e450',
          'sodyum asit pirofosfat',
          'sodium acid pyrophosphate',
        ],
        alternativeNames: const ['Diphosphate'],
      ),
      row(
        id: '24d34007-b642-4324-a841-265e2f814d78',
        name: 'Fosforik asit',
        normalizedName: 'fosforik asit',
        eCode: 'E338',
        riskLevel: 'medium',
        aliases: const ['E338', 'e338'],
      ),
      row(
        id: 'e0ee528c-53a9-4674-a7cc-55e71a6f89ca',
        name: 'Sodyum fosfat',
        normalizedName: 'sodyum fosfat',
        eCode: 'E339',
        riskLevel: 'medium',
        aliases: const ['E339', 'e339'],
      ),
      row(
        id: '46e94225-b2a4-42ae-b096-ba578c61ee4d',
        name: 'Trifosfat',
        normalizedName: 'trifosfat',
        eCode: 'E451',
        riskLevel: 'medium',
        aliases: const ['E451', 'e451'],
      ),
      row(
        id: '650e8400-e29b-41d4-a716-446655440002',
        name: 'Polifosfat',
        normalizedName: 'polifosfat',
        eCode: 'E452',
        riskLevel: 'medium',
        aliases: const ['E452', 'e452'],
      ),
    ];

    test(
      'sodium acid pyrophosphate / sodyum asit pirofosfat resolve to the E450 identity using its existing trusted risk',
      () async {
        final rows = phosphateFamily();
        for (final token in [
          'sodyum asit pirofosfat',
          'sodium acid pyrophosphate',
        ]) {
          final match = await matcher.matchSingleIngredient(token, rows);
          expect(
            match.matchedIngredient?.id,
            '0b77c066-6c85-4063-a241-e337aea1144e',
          );
          expect(match.matchedIngredient?.riskLevel, 'medium');
        }
      },
    );

    test(
      'chemically distinct phosphate E-codes stay distinct, never merged',
      () async {
        final rows = phosphateFamily();
        final cases = <String, String>{
          'E450': '0b77c066-6c85-4063-a241-e337aea1144e',
          'E338': '24d34007-b642-4324-a841-265e2f814d78',
          'E339': 'e0ee528c-53a9-4674-a7cc-55e71a6f89ca',
          'E451': '46e94225-b2a4-42ae-b096-ba578c61ee4d',
          'E452': '650e8400-e29b-41d4-a716-446655440002',
        };
        for (final entry in cases.entries) {
          final match = await matcher.matchSingleIngredient(entry.key, rows);
          expect(match.matchedIngredient?.id, entry.value);
        }
      },
    );
  });

  group('E500 / E503 variant coverage (real rows)', () {
    List<Ingredient> rows() => [
      row(
        id: '11b47719-b425-4193-a1e2-596318195f9a',
        name: 'Sodyum karbonat',
        normalizedName: 'sodyum karbonat',
        eCode: 'E500',
        aliases: const ['E500', 'e500'],
        alternativeNames: const ['Sodium carbonate'],
      ),
      row(
        id: 'efc4567a-b134-477c-a8e2-62488c3e09ac',
        name: 'Amonyum karbonat',
        normalizedName: 'amonyum karbonat',
        eCode: 'E503',
        aliases: const ['E503', 'e503'],
        alternativeNames: const ['Ammonium carbonate'],
      ),
    ];

    test(
      'E500 variants resolve to Sodyum karbonat via the canonicalizer + matcher pipeline',
      () async {
        final catalogueRows = rows();
        for (final raw in [
          'sodyum karbonat',
          'sodyum bikarbonat',
          'sodyum hidrojen karbonat',
          'E500',
        ]) {
          final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(raw);
          final matchResult = await matcher.matchIngredientTokens(
            tokens,
            catalogueRows,
          );
          expect(
            matchResult.matches.any(
              (m) =>
                  m.matchedIngredient?.id ==
                  '11b47719-b425-4193-a1e2-596318195f9a',
            ),
            isTrue,
            reason: '"$raw" must resolve to the E500 identity',
          );
        }
      },
    );

    test(
      'E503 variants resolve to Amonyum karbonat via the canonicalizer + matcher pipeline',
      () async {
        final catalogueRows = rows();
        for (final raw in ['amonyum karbonat', 'amonyum bikarbonat', 'E503']) {
          final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(raw);
          final matchResult = await matcher.matchIngredientTokens(
            tokens,
            catalogueRows,
          );
          expect(
            matchResult.matches.any(
              (m) =>
                  m.matchedIngredient?.id ==
                  'efc4567a-b134-477c-a8e2-62488c3e09ac',
            ),
            isTrue,
            reason: '"$raw" must resolve to the E503 identity',
          );
        }
      },
    );
  });

  group('Safety invariants unaffected by this pass', () {
    test(
      'a genuinely unresolved additive-like chemical stays blocked',
      () async {
        final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
          'un, tuz, sodyum asit pirofosfat',
        );
        final matchResult = await matcher.matchIngredientTokens(tokens, []);
        final assessment = riskService.assessForScoring(matchResult);
        expect(
          assessment.unresolvedIngredients.map((i) => i.normalizedToken),
          contains('sodyum asit pirofosfat'),
        );
      },
    );

    test(
      'a genuine catalogue risk conflict (distinct from the fixed whey case) still blocks',
      () {
        final now = DateTime.utc(2026, 8, 15);
        // "Şeker Şurubu" collides with a real containsAny entry
        // ('şeker şurubu', riskLevel: unspecified/low in catalogue) at a
        // deliberately mismatched DB risk to prove conflicts still fire when
        // genuine.
        final ingredient = Ingredient(
          id: 'genuine-conflict',
          name: 'Şeker Şurubu',
          normalizedName: 'şeker şurubu',
          riskLevel: 'high',
          createdAt: now,
          updatedAt: now,
        );
        final match = IngredientMatch(
          originalToken: 'şeker şurubu',
          normalizedText: 'şeker şurubu',
          matchedIngredient: ingredient,
          matchedToken: 'şeker şurubu',
          matchType: MatchType.exactMatch,
          confidenceScore: 1.0,
          shouldAffectAnalysis: true,
          needsUserConfirmation: false,
        );
        final assessment = riskService.assess(
          IngredientMatchingResult(matches: [match]),
        );
        final item = assessment.recognizedIngredients.single;
        expect(
          item.conflicts.map((c) => c.type),
          contains(CanonicalRiskConflictType.catalogueRiskMismatch),
          reason:
              'a real disagreement between the DB risk and the reviewed '
              'catalogue must still fail closed to unknown, not be silently '
              'suppressed by the boundary/alias fixes in this pass',
        );
        expect(item.riskLevel, CanonicalRiskLevel.unknown);
      },
    );

    test(
      'ordinary unmatched food remains harmless and does not require catalogue coverage',
      () async {
        final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
          'elma parçaları, su, karabiber',
        );
        final matchResult = await matcher.matchIngredientTokens(tokens, []);
        final assessment = riskService.assessForScoring(matchResult);
        expect(assessment.unresolvedIngredients, isEmpty);
        expect(assessment.recognizedIngredients, isEmpty);
      },
    );

    test(
      'same verified evidence produces the same assessment deterministically',
      () async {
        final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
          'kabartıcılar (amonyum bikarbonat, sodyum asit pirofosfat, sodyum bikarbonat)',
        );
        final rows = [
          row(
            id: 'e503',
            name: 'Amonyum karbonat',
            normalizedName: 'amonyum karbonat',
            eCode: 'E503',
          ),
          row(
            id: 'e500',
            name: 'Sodyum karbonat',
            normalizedName: 'sodyum karbonat',
            eCode: 'E500',
          ),
        ];
        final r1 = riskService.assessForScoring(
          await matcher.matchIngredientTokens(tokens, rows),
        );
        final r2 = riskService.assessForScoring(
          await matcher.matchIngredientTokens(tokens, rows),
        );
        expect(
          r1.recognizedIngredients.map((i) => i.canonicalKey).toList(),
          r2.recognizedIngredients.map((i) => i.canonicalKey).toList(),
        );
        expect(
          r1.unresolvedIngredients.map((i) => i.normalizedToken).toList(),
          r2.unresolvedIngredients.map((i) => i.normalizedToken).toList(),
        );
      },
    );
  });
}
