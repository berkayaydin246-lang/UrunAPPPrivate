import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

/// Regression coverage for the additive evidence pipeline hardening pass.
///
/// Every fixture here is either the exact real ingredient text from a saved
/// production diagnostic (see tmp/biscolata_starz_blocker.txt and
/// tmp/additive_only_exact5.txt) or a generic synthetic form covering a
/// structural pattern (colon/paren/bracket/semicolon/newline nesting) that
/// is not tied to any specific product, brand, or source — the fixes under
/// test operate at the tokenizer/matcher/risk-service level and must hold
/// for any future source adapter.
void main() {
  const matcher = IngredientMatcherService();
  const riskService = CanonicalIngredientRiskService();

  List<Ingredient> catalogue() {
    final now = DateTime.utc(2026, 8, 15);
    Ingredient of({
      required String id,
      required String name,
      required String normalizedName,
      String? eCode,
      String? additiveGroup,
      String riskLevel = 'low',
    }) => Ingredient(
      id: id,
      name: name,
      normalizedName: normalizedName,
      eCode: eCode,
      additiveGroup: additiveGroup,
      riskLevel: riskLevel,
      createdAt: now,
      updatedAt: now,
    );

    return [
      of(
        id: 'palm',
        name: 'Palm Yağı',
        normalizedName: 'palm yağı',
        additiveGroup: 'yağ',
        riskLevel: 'medium',
      ),
      of(
        id: 'lesitin',
        name: 'Lesitin',
        normalizedName: 'lesitin',
        eCode: 'E322',
        additiveGroup: 'emülgatör',
      ),
      of(
        id: 'e503',
        name: 'Amonyum karbonat',
        normalizedName: 'amonyum karbonat',
        eCode: 'E503',
        additiveGroup: 'kabartıcı',
      ),
      of(
        id: 'e500',
        name: 'Sodyum karbonat',
        normalizedName: 'sodyum karbonat',
        eCode: 'E500',
        additiveGroup: 'kabartıcı',
      ),
      of(
        id: 'e471',
        name: 'Mono ve digliseritler',
        normalizedName: 'mono ve digliseritler',
        eCode: 'E471',
        additiveGroup: 'emülgatör',
      ),
      of(
        id: 'guar',
        name: 'Guar gam',
        normalizedName: 'guar gam',
        eCode: 'E412',
        additiveGroup: 'kıvam artırıcı',
      ),
    ];
  }

  Future<CanonicalAdditiveAssessment> assessText(String rawText) async {
    final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(rawText);
    final matches = await matcher.matchIngredientTokens(tokens, catalogue());
    return riskService.assessForScoring(matches);
  }

  group(
    'Bug class 1 & 6 — known additive-like chemical never silently ordinary',
    () {
      test(
        'sodium acid pyrophosphate remains a blocking unresolved additive-like token',
        () async {
          final assessment = await assessText(
            'buğday unu, kabartıcı (sodyum bikarbonat, sodyum asit pirofosfat)',
          );

          expect(
            assessment.unresolvedIngredients.map(
              (item) => item.normalizedToken,
            ),
            contains('sodyum asit pirofosfat'),
            reason:
                'a recognizable additive-like chemical with no catalogue '
                'match must remain a retained blocker, never disappear into '
                'ordinary food',
          );
        },
      );

      test('ordinary unmatched food never blocks additive readiness', () async {
        final assessment = await assessText(
          'un, su, elma parçaları, tuz, kakao yağı',
        );

        expect(assessment.unresolvedIngredients, isEmpty);
      });
    },
  );

  group('Bug class 2 — functional-class labels with declared children', () {
    test('emülgatör: lesitin (colon) — real Ferrero Rocher pattern', () async {
      final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
        'yağı azaltılmış kakao tozu,\r\nemülgatör: lesitin (soya), \r\nkabartıcı (sodyum hidrojen karbonat),\r\ntuz',
      );

      expect(tokens, isNot(contains('emülgatör')));
      expect(tokens, contains('lesitin'));

      final assessment = await assessText(
        'yağı azaltılmış kakao tozu,\r\nemülgatör: lesitin (soya), \r\nkabartıcı (sodyum hidrojen karbonat),\r\ntuz',
      );
      expect(
        assessment.unresolvedIngredients.map((item) => item.normalizedToken),
        isNot(contains('emülgatör')),
      );
      expect(
        assessment.canonicalAdditives.map((item) => item.canonicalName),
        contains('Lesitin'),
      );
    });

    for (final form in <String, String>{
      'functionalClass: child': 'emülgatör: lesitin (soya)',
      'functionalClass (child)': 'emülgatör (lesitin (soya))',
      'functionalClass [child]': 'emülgatör [lesitin (soya)]',
      'functionalClass: child1, child2 stays scoped to one clause':
          'emülgatör: lesitin (soya), tuz',
      'functionalClass (child1, child2)':
          'kabartıcı (sodyum bikarbonat, amonyum bikarbonat)',
      'semicolon-separated declaration':
          'emülgatör : lesitin (soya);aroma verici',
      'newline-separated declaration': 'emülgatör:\nlesitin (soya)',
    }.entries) {
      test('generic form — ${form.key}', () async {
        final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
          form.value,
        );
        expect(
          tokens,
          isNot(contains('emülgatör')),
          reason:
              'a functional label with a discovered concrete child must not '
              'also survive as its own standalone token',
        );
      });
    }

    test(
      'nested component (functionalClass: child) — label nested inside another compound ingredient',
      () async {
        final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
          'sütlü çikolata (şeker, emülgatör: lesitin (soya), aroma verici)',
        );
        expect(tokens, contains('lesitin'));
      },
    );

    test(
      'a functional label with NO declared child correctly stays blocked — we do not know which additive it is',
      () async {
        final assessment = await assessText('un, tuz, emülgatör');

        expect(
          assessment.recognizedIngredients.map((item) => item.canonicalName),
          isNot(contains('Lesitin')),
          reason: 'no child was declared, so nothing may be fabricated',
        );
        expect(
          assessment.unresolvedIngredients.map((item) => item.normalizedToken),
          contains('emülgatör'),
          reason:
              'an undeclared emulsifier is genuinely unverifiable evidence '
              'and must remain a blocker — this is not the same case as a '
              'label whose child was successfully parsed',
        );
      },
    );

    test(
      'generic flavouring specifically has an explicit non-blocking exception, unlike other bare functional labels',
      () async {
        final assessment = await assessText('un, tuz, aroma verici');

        expect(
          assessment.outOfScopeFlavouringEvidence.map(
            (item) => item.normalizedToken,
          ),
          isNotEmpty,
        );
        expect(
          assessment.unresolvedIngredients.map((item) => item.normalizedToken),
          isNot(contains('aroma vericiler')),
        );
      },
    );
  });

  group('Bug class 3 — trailing declaration sentence boundary', () {
    test(
      'real Biscolata Starz composition list + trailing cocoa-content declaration',
      () {
        const raw =
            'İçindekiler: Kakaolu Bisküvi (%68) [buğday unu (gluten içerir), '
            'bitkisel yağ (palm), şeker, kakao tozu (%3,5), kabartıcı '
            '(amonyum bikarbonat, sodyum bikarbonat, sodyum asit pirofosfat), '
            'glukoz-fruktoz şurubu, yağsız süt tozu, tuz, emülgatör '
            '(ayçiçek lesitini), aroma verici], Bitter Çikolata (%19) '
            '[şeker, kakao kitlesi, kakao yağı, kakao tozu, emülgatör '
            '(ayçiçek lesitini), aroma verici, tuz], Sütlü Krema (%13) '
            '[şeker, bitkisel yağ (palm, ayçiçek, pamuk), peyniraltı suyu '
            'tozu (süt ürünü), yağsız süt tozu (%7), emülgatör (ayçiçek '
            'lesitini), aroma verici]. Bitter çikolata min. %55 kakao kuru '
            'maddesi içermektedir. A';

        final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(raw);

        for (final token in tokens) {
          expect(
            token,
            isNot(contains('içermektedir')),
            reason:
                'no token may merge ingredient content with the '
                'trailing regulatory declaration sentence',
          );
        }
      },
    );

    test(
      'trailing declaration after a parenthesis-only composition list — real Biscolata Stix pattern',
      () {
        const raw =
            'Sütlü çikolata (%59) (Şeker, kakao yağı, emülgatör (ayçiçek '
            'lesitini)), Bisküvi (%30) (Buğday unu (gluten içerir), '
            'kabartıcı (sodyum bikarbonat)).\n\nSütlü çikolata min. %30 '
            'kakao kuru maddesi içermektedir. \n\n"';

        final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(raw);

        for (final token in tokens) {
          expect(token, isNot(contains('içermektedir')));
          expect(token, isNot(contains('kuru maddesi')));
        }
      },
    );

    test(
      'a genuine ingredient listed after a bracketed group is NOT truncated',
      () {
        final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
          'karışım (%50) [şeker, tuz], vanilin, tarçın',
        );

        expect(tokens, contains('vanilin'));
        expect(tokens, contains('tarçın'));
      },
    );

    test('ingredient text with no brackets at all is never truncated', () {
      final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
        'un, su, tuz, maya',
      );
      expect(tokens, containsAll(['un', 'su', 'tuz', 'maya']));
    });
  });

  group('Bug class 4 & 7 — deterministic canonical resolution', () {
    Future<CanonicalIngredientAssessment> resolve(String token) async {
      final match = await matcher.matchSingleIngredient(token, catalogue());
      final assessment = riskService.assessForScoring(
        IngredientMatchingResult(matches: [match]),
      );
      return assessment.recognizedIngredients.single;
    }

    test('E500 resolves authoritatively for every observed phrasing', () async {
      for (final phrasing in [
        'sodyum karbonat',
        'sodyum bikarbonat',
        'sodyum hidrojen karbonat',
      ]) {
        final result = await resolve(phrasing);
        expect(
          result.matchAuthority,
          CanonicalMatchAuthority.authoritative,
          reason: phrasing,
        );
        expect(result.eCode, 'E500', reason: phrasing);
      }
    });

    test('E503 resolves authoritatively for every observed phrasing', () async {
      for (final phrasing in ['amonyum karbonat', 'amonyum bikarbonat']) {
        final result = await resolve(phrasing);
        expect(
          result.matchAuthority,
          CanonicalMatchAuthority.authoritative,
          reason: phrasing,
        );
        expect(result.eCode, 'E503', reason: phrasing);
      }
    });

    test(
      'E471 resolves authoritatively for both digliserit/digliserid spellings',
      () async {
        for (final phrasing in [
          'mono ve digliseritler',
          'yağ asitlerinin mono ve digliseridleri',
        ]) {
          final tokens = IngredientCanonicalizer.parseIngredientsAdvanced(
            'emülgatör ($phrasing)',
          );
          expect(tokens, contains('mono ve digliseritler'), reason: phrasing);
          final result = await resolve('mono ve digliseritler');
          expect(result.matchAuthority, CanonicalMatchAuthority.authoritative);
          expect(result.eCode, 'E471');
        }
      },
    );

    test('Palm Yağı resolves authoritatively and deterministically', () async {
      for (final phrasing in ['palm', 'palm yağı', 'palmiye yağı']) {
        final result = await resolve(phrasing);
        expect(
          result.matchAuthority,
          CanonicalMatchAuthority.authoritative,
          reason: phrasing,
        );
        expect(result.canonicalName, 'Palm Yağı', reason: phrasing);
      }
    });

    test(
      'duplicate candidate precedence: exact/alias/e-code always outrank fuzzy',
      () async {
        // "sodyum bikarbonat" could plausibly fuzzy-match "sodyum karbonat"
        // even without the alias fix; asserting authoritative here locks in
        // that the deterministic alias path — not a fuzzy fallback — is what
        // actually resolves it.
        final match = await matcher.matchSingleIngredient(
          'sodyum bikarbonat',
          catalogue(),
        );
        expect(match.matchType, MatchType.aliasMatch);
      },
    );

    test(
      'chemically distinct E-code subtypes are not blindly merged',
      () async {
        // Guar gam (E412) must never resolve to the E471 (mono/digliserit)
        // canonical row merely because both are emulsifier-family additives.
        final result = await resolve('guar gam');
        expect(result.eCode, 'E412');
        expect(result.canonicalName, isNot('Mono ve digliseritler'));
      },
    );
  });

  group('Bug class 5 — risk conflicts remain fail-closed', () {
    test(
      'a genuine catalogue-vs-reviewed risk conflict is never silently resolved to a value',
      () async {
        final now = DateTime.utc(2026, 8, 15);
        // E250 (sodium nitrite) has a reviewed static risk level in the
        // repository catalogue; a DB row disagreeing with it must produce a
        // conflict, not a guessed resolution.
        final conflicting = Ingredient(
          id: 'nitrite-conflict',
          name: 'Sodyum Nitrit',
          normalizedName: 'sodyum nitrit',
          eCode: 'E250',
          additiveGroup: 'koruyucu',
          riskLevel: 'low',
          createdAt: now,
          updatedAt: now,
        );
        final match = IngredientMatch(
          originalToken: 'sodyum nitrit',
          normalizedText: 'sodyum nitrit',
          matchedIngredient: conflicting,
          matchedToken: 'sodyum nitrit',
          matchType: MatchType.exactMatch,
          confidenceScore: 1,
          shouldAffectAnalysis: true,
        );
        final assessment = riskService.assessForScoring(
          IngredientMatchingResult(matches: [match]),
        );
        final resolved = assessment.recognizedIngredients.single;

        expect(resolved.conflicts, isNotEmpty);
        expect(resolved.riskLevel, CanonicalRiskLevel.unknown);
        expect(resolved.eligibleForFutureAdditiveScore, isFalse);
      },
    );
  });

  group(
    'end-to-end real production ingredient texts remain deterministic and free of the fixed defects',
    () {
      test(
        'Biscolata Starz — no false emülgatör/label blocker, sodium acid pyrophosphate retained',
        () async {
          const raw =
              'İçindekiler: Kakaolu Bisküvi (%68) [buğday unu (gluten içerir), '
              'bitkisel yağ (palm), şeker, kakao tozu (%3,5), kabartıcı '
              '(amonyum bikarbonat, sodyum bikarbonat, sodyum asit pirofosfat), '
              'glukoz-fruktoz şurubu, yağsız süt tozu, tuz, emülgatör '
              '(ayçiçek lesitini), aroma verici]. Bitter çikolata min. %55 '
              'kakao kuru maddesi içermektedir. A';

          final assessment = await assessText(raw);

          expect(
            assessment.canonicalAdditives.map((item) => item.eCode),
            containsAll(['E503', 'E500']),
          );
          for (final item in assessment.canonicalAdditives.where(
            (item) => item.eCode == 'E503' || item.eCode == 'E500',
          )) {
            expect(item.matchAuthority, CanonicalMatchAuthority.authoritative);
          }
          expect(
            assessment.unresolvedIngredients.map(
              (item) => item.normalizedToken,
            ),
            contains('sodyum asit pirofosfat'),
          );
        },
      );

      test(
        'Ferrero Rocher — emülgatör label no longer a false blocker',
        () async {
          const raw =
              "sütlü çikolata %30 (şeker,kakao yağı, emülgatör : lesitin "
              "(soya);aroma verici,(vanilin)),\r\nfındık (%28,5), \r\nşeker,"
              "\r\nemülgatör: lesitin (soya), \r\nkabartıcı (sodyum hidrojen "
              "karbonat),\r\ntuz";

          final assessment = await assessText(raw);

          expect(
            assessment.unresolvedIngredients.map(
              (item) => item.normalizedToken,
            ),
            isNot(contains('emülgatör')),
          );
          expect(
            assessment.canonicalAdditives.map((item) => item.canonicalName),
            containsAll(['Lesitin', 'Sodyum karbonat']),
          );
        },
      );
    },
  );
}
