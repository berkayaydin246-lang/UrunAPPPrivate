import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/engines/analysis_engine.dart';
import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

Ingredient _ingredient({
  required String id,
  required String name,
  required String risk,
  String? normalizedName,
  String? eCode,
  String? additiveGroup,
  List<String>? aliases,
}) {
  return Ingredient(
    id: id,
    name: name,
    normalizedName: normalizedName ?? name.toLowerCase(),
    aliases: aliases,
    eCode: eCode,
    additiveGroup: additiveGroup,
    riskLevel: risk,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

IngredientMatch _match({
  required String token,
  required Ingredient? ingredient,
  MatchType type = MatchType.exactMatch,
  double confidence = 1,
  bool affectsAnalysis = true,
  bool needsConfirmation = false,
  bool? userApproved,
}) {
  return IngredientMatch(
    originalToken: token,
    normalizedText: token.toLowerCase(),
    matchedIngredient: ingredient,
    matchedToken: ingredient?.normalizedName,
    confidenceScore: confidence,
    matchType: type,
    shouldAffectAnalysis: affectsAnalysis,
    needsUserConfirmation: needsConfirmation,
    userApproved: userApproved,
  );
}

CanonicalAdditiveAssessment _assess(
  List<IngredientMatch> matches, {
  ScoringCategory category = ScoringCategory.unknown,
  CanonicalUnresolvedIngredientPolicy unresolvedIngredientPolicy =
      CanonicalUnresolvedIngredientPolicy.retainAll,
}) {
  return const CanonicalIngredientRiskService().assess(
    IngredientMatchingResult(matches: matches),
    scoringCategory: category,
    unresolvedIngredientPolicy: unresolvedIngredientPolicy,
  );
}

void main() {
  group('canonical identity and deduplication', () {
    final additive = _ingredient(
      id: 'additive-1',
      name: 'Reviewed Additive',
      risk: 'medium',
      eCode: 'E900',
      additiveGroup: 'test_group',
      aliases: const ['reviewed alias'],
    );

    test('same ingredient ID deduplicates', () {
      final result = _assess([
        _match(token: 'Reviewed Additive', ingredient: additive),
        _match(token: 'Reviewed Additive', ingredient: additive),
      ]);

      expect(result.canonicalAdditives, hasLength(1));
      expect(result.canonicalAdditives.single.occurrenceCount, 2);
    });

    test('E-code and canonical name deduplicate', () {
      final result = _assess([
        _match(token: 'E900', ingredient: additive, type: MatchType.eCodeMatch),
        _match(token: 'Reviewed Additive', ingredient: additive),
      ]);

      expect(result.canonicalAdditives, hasLength(1));
      expect(
        result.canonicalAdditives.single.matchEvidence.map((e) => e.matchType),
        containsAll([MatchType.eCodeMatch, MatchType.exactMatch]),
      );
    });

    test('alias and E-code deduplicate', () {
      final result = _assess([
        _match(
          token: 'reviewed alias',
          ingredient: additive,
          type: MatchType.aliasMatch,
          confidence: 0.95,
        ),
        _match(token: 'E900', ingredient: additive, type: MatchType.eCodeMatch),
      ]);

      expect(result.canonicalAdditives, hasLength(1));
      expect(result.canonicalAdditives.single.sourceTokens, hasLength(2));
    });

    test('different additives in the same group remain separate', () {
      final second = _ingredient(
        id: 'additive-2',
        name: 'Second Reviewed Additive',
        risk: 'low',
        eCode: 'E901',
        additiveGroup: 'test_group',
      );

      final result = _assess([
        _match(token: 'E900', ingredient: additive),
        _match(token: 'E901', ingredient: second),
      ]);

      expect(result.canonicalAdditives, hasLength(2));
      expect(
        result.canonicalAdditives.map((item) => item.canonicalKey).toSet(),
        hasLength(2),
      );
    });

    test('repeated token creates one canonical item', () {
      final result = _assess(
        List.generate(3, (_) => _match(token: 'E900', ingredient: additive)),
      );

      expect(result.canonicalAdditives, hasLength(1));
      expect(result.canonicalAdditives.single.occurrenceCount, 3);
    });

    test('canonical key is stable and prefers ingredient ID', () {
      final service = const CanonicalIngredientRiskService();

      expect(
        service.canonicalKeyForIngredient(additive),
        service.canonicalKeyForIngredient(additive),
      );
      expect(
        service.canonicalKeyForIngredient(additive),
        'ingredient:additive-1',
      );
    });

    test('fallback canonical key prefers E-code without an ID', () {
      final withoutId = _ingredient(
        id: '',
        name: 'Fallback Additive',
        risk: 'low',
        eCode: 'E 902',
      );

      expect(
        const CanonicalIngredientRiskService().canonicalKeyForIngredient(
          withoutId,
        ),
        'e-code:E902',
      );
    });

    test('invalid E-code metadata falls back to canonical name', () {
      final withoutValidCode = _ingredient(
        id: '',
        name: 'Fallback Named Ingredient',
        risk: 'low',
        eCode: 'not-an-e-code',
      );

      expect(
        const CanonicalIngredientRiskService().canonicalKeyForIngredient(
          withoutValidCode,
        ),
        'name:fallback named ingredient',
      );
    });

    test('ordinary ingredient is not treated as an additive', () {
      final ordinary = _ingredient(id: 'water', name: 'Su', risk: 'low');
      final result = _assess([_match(token: 'su', ingredient: ordinary)]);

      expect(result.canonicalAdditives, isEmpty);
      expect(result.ordinaryIngredients, hasLength(1));
      expect(
        result.ordinaryIngredients.single.eligibleForFutureAdditiveScore,
        isFalse,
      );
    });

    test('unresolved token remains unresolved', () {
      final result = _assess([
        _match(
          token: 'tanimsiz katkı',
          ingredient: null,
          type: MatchType.unmatched,
          confidence: 0,
          affectsAnalysis: false,
        ),
      ]);

      expect(result.recognizedIngredients, isEmpty);
      expect(result.unresolvedIngredients, hasLength(1));
      expect(result.unresolvedIngredients.single.sourceTokens, [
        'tanimsiz katkı',
      ]);
    });

    test(
      'legacy policy drops ordinary unresolved but retains additive-like',
      () {
        final matches = [
          _match(
            token: 'buğday unu',
            ingredient: null,
            type: MatchType.unmatched,
            affectsAnalysis: false,
          ),
          _match(
            token: 'E9999',
            ingredient: null,
            type: MatchType.unmatched,
            affectsAnalysis: false,
          ),
        ];

        expect(_assess(matches).unresolvedIngredients, hasLength(2));
        final legacy = _assess(
          matches,
          unresolvedIngredientPolicy:
              CanonicalUnresolvedIngredientPolicy.additiveCandidatesOnly,
        );
        expect(legacy.unresolvedIngredients, hasLength(1));
        expect(legacy.unresolvedIngredients.single.sourceTokens, ['E9999']);
      },
    );
  });

  group('canonical risk authority', () {
    CanonicalIngredientAssessment assessRisk(String risk) {
      final ingredient = _ingredient(
        id: 'risk-$risk',
        name: 'Reviewed $risk additive',
        risk: risk,
        eCode: 'E903',
      );
      return _assess([
        _match(token: ingredient.name, ingredient: ingredient),
      ]).canonicalAdditives.single;
    }

    test('canonical reviewed low remains low', () {
      expect(assessRisk('low').riskLevel, CanonicalRiskLevel.low);
    });

    test('canonical reviewed medium remains medium', () {
      expect(assessRisk('medium').riskLevel, CanonicalRiskLevel.medium);
    });

    test('canonical reviewed high remains high', () {
      expect(assessRisk('high').riskLevel, CanonicalRiskLevel.high);
    });

    test('unknown remains unknown', () {
      final item = assessRisk('unknown');

      expect(item.riskLevel, CanonicalRiskLevel.unknown);
      expect(item.eligibleForFutureAdditiveScore, isFalse);
    });

    test('legacy hard-coded path cannot override canonical risk', () {
      final low = _ingredient(
        id: 'signal-low',
        name: 'Reviewed Low Additive',
        risk: 'low',
        eCode: 'E904',
      );
      final matching = IngredientMatchingResult(
        matches: [_match(token: 'nitrit signal', ingredient: low)],
      );

      final result = const AnalysisEngine().analyze(matching);

      expect(result.riskSignals, contains('processed_meat_additive'));
      expect(result.detectedRiskIngredients, isEmpty);
      expect(
        result.additiveAssessment!.canonicalAdditives.single.riskLevel,
        CanonicalRiskLevel.low,
      );
    });

    test('AnalysisEngine cannot upgrade or downgrade canonical risk', () {
      final medium = _ingredient(
        id: 'signal-medium',
        name: 'Reviewed Medium Additive',
        risk: 'medium',
        eCode: 'E905',
      );
      final result = const AnalysisEngine().analyze(
        IngredientMatchingResult(
          matches: [_match(token: 'tartrazin signal', ingredient: medium)],
        ),
      );

      expect(result.detectedRiskIngredients.single.riskLevel, 'medium');
      expect(
        result.negativePoints,
        isNot(contains('1 adet yüksek riskli içerik')),
      );
    });

    test('catalogue conflict is deterministic and visible', () {
      final bht = _ingredient(
        id: 'conflicting-bht',
        name: 'BHT',
        risk: 'high',
        eCode: 'E321',
      );

      final first = _assess([
        _match(token: 'BHT', ingredient: bht),
        _match(token: 'E321', ingredient: bht, type: MatchType.eCodeMatch),
      ]);
      final second = _assess([_match(token: 'BHT', ingredient: bht)]);

      expect(
        first.canonicalAdditives.single.riskLevel,
        CanonicalRiskLevel.unknown,
      );
      expect(first.conflicts, hasLength(1));
      expect(second.conflicts.single.type, first.conflicts.single.type);
    });

    test('consistent duplicate sources retain a resolved source', () {
      final databaseReviewed = _ingredient(
        id: 'shared-bht',
        name: 'BHT',
        risk: 'medium',
        eCode: 'E321',
      );
      final localFallback = _ingredient(
        id: 'shared-bht',
        name: 'BHT',
        risk: 'unknown',
        eCode: 'E321',
      );

      final item = _assess([
        _match(token: 'BHT', ingredient: databaseReviewed),
        _match(token: 'E321', ingredient: localFallback),
      ]).canonicalAdditives.single;

      expect(item.riskLevel, CanonicalRiskLevel.medium);
      expect(item.riskSource, CanonicalRiskSource.consistentCatalogues);
      expect(item.conflicts, isEmpty);
    });

    test('product name cannot change risk', () {
      final ingredient = _ingredient(
        id: 'name-independent',
        name: 'Name Independent Additive',
        risk: 'medium',
        eCode: 'E906',
      );

      final first = _assess([_match(token: 'E906', ingredient: ingredient)]);
      final second = _assess([
        _match(token: 'Name Independent Additive', ingredient: ingredient),
      ]);

      expect(
        first.canonicalAdditives.single.riskLevel,
        second.canonicalAdditives.single.riskLevel,
      );
    });

    test('assessment is deterministic without AI output', () {
      final ingredient = _ingredient(
        id: 'deterministic',
        name: 'Deterministic Additive',
        risk: 'high',
        eCode: 'E907',
      );

      final results = List.generate(
        3,
        (_) => _assess([_match(token: 'E907', ingredient: ingredient)]),
      );

      expect(
        results
            .map((result) => result.canonicalAdditives.single.riskLevel)
            .toSet(),
        {CanonicalRiskLevel.high},
      );
    });
  });

  group('match authority and future eligibility', () {
    final additive = _ingredient(
      id: 'eligibility',
      name: 'Eligibility Additive',
      risk: 'medium',
      eCode: 'E908',
      aliases: const ['eligibility alias'],
    );

    CanonicalIngredientAssessment assessMatch(MatchType type) => _assess([
      _match(
        token: type == MatchType.eCodeMatch ? 'E908' : 'Eligibility Additive',
        ingredient: additive,
        type: type,
        confidence: type == MatchType.highConfidenceFuzzy ? 0.9 : 1,
      ),
    ]).canonicalAdditives.single;

    test('exact E-code match is eligible', () {
      final item = assessMatch(MatchType.eCodeMatch);
      expect(item.matchAuthority, CanonicalMatchAuthority.authoritative);
      expect(item.eligibleForFutureAdditiveScore, isTrue);
    });

    test('exact canonical match is eligible', () {
      expect(
        assessMatch(MatchType.exactMatch).eligibleForFutureAdditiveScore,
        isTrue,
      );
    });

    test('exact reviewed alias is eligible under matcher guarantees', () {
      final item = _assess([
        _match(
          token: 'eligibility alias',
          ingredient: additive,
          type: MatchType.aliasMatch,
          confidence: 0.95,
        ),
      ]).canonicalAdditives.single;

      expect(item.matchAuthority, CanonicalMatchAuthority.authoritative);
      expect(item.eligibleForFutureAdditiveScore, isTrue);
    });

    test('fuzzy candidate is not automatically eligible', () {
      final item = assessMatch(MatchType.highConfidenceFuzzy);

      expect(item.matchAuthority, CanonicalMatchAuthority.reviewRequired);
      expect(item.eligibleForFutureAdditiveScore, isFalse);
    });

    test('unknown match is not scoring eligible', () {
      final result = _assess([
        _match(
          token: 'unknown',
          ingredient: null,
          type: MatchType.unmatched,
          affectsAnalysis: false,
        ),
      ]);

      expect(result.canonicalAdditives, isEmpty);
      expect(result.unresolvedIngredients, hasLength(1));
    });

    test('unknown canonical risk is not scoring eligible', () {
      final unknown = _ingredient(
        id: 'unknown-risk',
        name: 'Unknown Risk Additive',
        risk: 'unknown',
        eCode: 'E909',
      );

      expect(
        _assess([
          _match(token: 'E909', ingredient: unknown),
        ]).canonicalAdditives.single.eligibleForFutureAdditiveScore,
        isFalse,
      );
    });
  });

  group('beverage NNS nutrition overlap', () {
    final sucralose = _ingredient(
      id: 'sucralose',
      name: 'Sukraloz',
      normalizedName: 'sukraloz',
      risk: 'medium',
      eCode: 'E955',
      additiveGroup: 'sweetener',
    );

    test('qualifying beverage NNS carries overlap metadata', () {
      final item = _assess([
        _match(
          token: 'E955',
          ingredient: sucralose,
          type: MatchType.eCodeMatch,
        ),
      ], category: ScoringCategory.beverage).canonicalAdditives.single;

      expect(
        item.nutritionMethodologyOverlap,
        NutritionMethodologyOverlap.beverageNnsAlreadyRepresented,
      );
    });

    test('overlapped additive remains visible in additive assessment', () {
      final result = _assess([
        _match(token: 'sukraloz', ingredient: sucralose),
      ], category: ScoringCategory.beverage);

      expect(result.canonicalAdditives, hasLength(1));
      expect(result.canonicalAdditives.single.canonicalName, 'Sukraloz');
    });

    test('same non-beverage NNS has no beverage overlap flag', () {
      final item = _assess([
        _match(token: 'sukraloz', ingredient: sucralose),
      ], category: ScoringCategory.generalFood).canonicalAdditives.single;

      expect(
        item.nutritionMethodologyOverlap,
        NutritionMethodologyOverlap.none,
      );
    });

    test('excluded polyol is not a qualifying beverage NNS', () {
      final maltitol = _ingredient(
        id: 'maltitol',
        name: 'Maltitol',
        risk: 'medium',
        eCode: 'E965',
        additiveGroup: 'sweetener',
      );
      final item = _assess([
        _match(token: 'E965', ingredient: maltitol),
      ], category: ScoringCategory.beverage).canonicalAdditives.single;

      expect(
        item.nutritionMethodologyOverlap,
        NutritionMethodologyOverlap.none,
      );
    });

    test('overlap metadata has no effect on risk or eligibility', () {
      final beverage = _assess([
        _match(token: 'E955', ingredient: sucralose),
      ], category: ScoringCategory.beverage).canonicalAdditives.single;
      final food = _assess([
        _match(token: 'E955', ingredient: sucralose),
      ], category: ScoringCategory.generalFood).canonicalAdditives.single;

      expect(beverage.riskLevel, food.riskLevel);
      expect(
        beverage.eligibleForFutureAdditiveScore,
        food.eligibleForFutureAdditiveScore,
      );
    });
  });

  group('analysis regressions', () {
    test('duplicate ingredients do not inflate risk summaries', () {
      final high = _ingredient(
        id: 'one-high',
        name: 'One High Additive',
        risk: 'high',
        eCode: 'E910',
      );
      final matching = IngredientMatchingResult(
        matches: [
          _match(token: 'E910', ingredient: high),
          _match(token: 'One High Additive', ingredient: high),
        ],
      );

      final result = const AnalysisEngine().analyze(matching);

      expect(result.detectedRiskIngredients, hasLength(1));
      expect(
        result.negativePoints,
        contains('Etiketly değerlendirmesinde 1 yüksek düzey içerik'),
      );
      expect(result.additiveAssessment!.highRiskCount, 1);
    });

    test('unmatched ingredients do not crash analysis', () {
      final result = const AnalysisEngine().analyze(
        IngredientMatchingResult(
          matches: [
            _match(
              token: 'unmatched ingredient',
              ingredient: null,
              type: MatchType.unmatched,
              affectsAnalysis: false,
            ),
          ],
        ),
      );

      expect(result.detectedRiskIngredients, isEmpty);
      expect(result.additiveAssessment!.unresolvedIngredients, hasLength(1));
    });

    test('risk-count summaries count canonical additives only', () {
      final ordinaryHigh = _ingredient(
        id: 'ordinary-high',
        name: 'Ordinary Reviewed Ingredient',
        risk: 'high',
      );
      final additiveLow = _ingredient(
        id: 'additive-low',
        name: 'Low Additive',
        risk: 'low',
        eCode: 'E911',
      );
      final result = _assess([
        _match(token: ordinaryHigh.name, ingredient: ordinaryHigh),
        _match(token: additiveLow.name, ingredient: additiveLow),
      ]);

      expect(result.highRiskCount, 0);
      expect(result.lowRiskCount, 1);
      expect(result.ordinaryIngredients, hasLength(1));
    });
  });
}
