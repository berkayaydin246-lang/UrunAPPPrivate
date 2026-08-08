import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/engines/analysis_engine.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/analysis/models/product_context.dart';

void main() {
  final now = DateTime.now();
  Ingredient makeIngredient(
    String id,
    String name,
    String normalized,
    String risk,
  ) {
    return Ingredient(
      id: id,
      name: name,
      normalizedName: normalized,
      riskLevel: risk,
      createdAt: now,
      updatedAt: now,
    );
  }

  IngredientMatch makeMatch(
    String original,
    String normalized,
    Ingredient? ing,
    double conf,
    MatchType type, {
    bool affect = true,
  }) {
    return IngredientMatch(
      originalToken: original,
      normalizedText: normalized,
      matchedIngredient: ing,
      matchedToken: ing?.normalizedName,
      confidenceScore: conf,
      matchType: type,
      shouldAffectAnalysis: affect,
      needsUserConfirmation: false,
    );
  }

  test('A - Ingredients only: sugar, palm yağı, aroma vericiler', () {
    final ingSugar = makeIngredient('1', 'şeker', 'şeker', 'medium');
    final ingPalm = makeIngredient('2', 'palm yağı', 'palm yağı', 'high');
    final ingAroma = makeIngredient(
      '3',
      'aroma vericiler',
      'aroma vericiler',
      'medium',
    );

    final matches = [
      makeMatch('şeker', 'şeker', ingSugar, 0.95, MatchType.exactMatch),
      makeMatch('palm yağı', 'palm yağı', ingPalm, 0.95, MatchType.exactMatch),
      makeMatch(
        'aroma vericiler',
        'aroma vericiler',
        ingAroma,
        0.95,
        MatchType.exactMatch,
      ),
    ];

    final result = AnalysisEngine().analyze(
      IngredientMatchingResult(matches: matches),
    );
    expect(
      result.riskSignals.containsKey('sugar_syrup') ||
          result.riskSignals.containsKey('low_quality_oil') ||
          result.riskSignals.containsKey('flavoring'),
      true,
    );
    expect(result.productContextNote, isNull);
  });

  test(
    'B - Processed meat nitrite with product context processed_meat adds context note',
    () {
      final ingNitrit = makeIngredient(
        'n1',
        'sodyum nitrit',
        'sodyum nitrit',
        'high',
      );
      final matches = [
        makeMatch(
          'sodyum nitrit',
          'sodyum nitrit',
          ingNitrit,
          0.95,
          MatchType.exactMatch,
        ),
      ];
      final ctx = ProductContext(
        productType: 'processed_meat',
        confidence: 0.9,
        source: 'barcode_category',
      );
      final result = AnalysisEngine().analyze(
        IngredientMatchingResult(matches: matches),
        productContext: ctx,
      );
      expect(result.riskSignals.containsKey('processed_meat_additive'), true);
      expect(result.productContextNote, isNotNull);
      expect(
        result.productContextNote!.toLowerCase().contains('işlenmiş et'),
        true,
      );
    },
  );

  test('C - Energy drink context enrichment', () {
    final ingCafe = makeIngredient('c1', 'kafein', 'kafein', 'high');
    final ingTaur = makeIngredient('c2', 'taurin', 'taurin', 'high');
    final ingSweet = makeIngredient('s1', 'sukraloz', 'sukraloz', 'medium');
    final matches = [
      makeMatch('kafein', 'kafein', ingCafe, 0.95, MatchType.exactMatch),
      makeMatch('taurin', 'taurin', ingTaur, 0.95, MatchType.exactMatch),
      makeMatch('sukraloz', 'sukraloz', ingSweet, 0.95, MatchType.exactMatch),
    ];
    final ctx = ProductContext(
      productType: 'energy_drink',
      confidence: 0.95,
      source: 'product_category',
    );
    final result = AnalysisEngine().analyze(
      IngredientMatchingResult(matches: matches),
      productContext: ctx,
    );
    expect(result.riskSignals.containsKey('caffeine_stimulant'), true);
    expect(result.riskSignals.containsKey('artificial_sweetener'), true);
    expect(result.productContextNote, isNotNull);
    expect(result.productContextNote!.toLowerCase().contains('enerji'), true);
  });

  test('D - Chocolate spread sugar first + palm oil context note', () {
    final ingSugar = makeIngredient('1', 'şeker', 'şeker', 'medium');
    final ingPalm = makeIngredient('2', 'palm yağı', 'palm yağı', 'high');
    final ingFindik = makeIngredient('3', 'fındık', 'fındık', 'low');
    final ingKakao = makeIngredient('4', 'kakao tozu', 'kakao tozu', 'low');

    final matches = [
      makeMatch('şeker', 'şeker', ingSugar, 0.95, MatchType.exactMatch),
      makeMatch('palm yağı', 'palm yağı', ingPalm, 0.95, MatchType.exactMatch),
      makeMatch('fındık', 'fındık', ingFindik, 0.95, MatchType.exactMatch),
      makeMatch(
        'kakao tozu',
        'kakao tozu',
        ingKakao,
        0.95,
        MatchType.exactMatch,
      ),
    ];
    final ctx = ProductContext(
      productType: 'chocolate_spread',
      confidence: 0.85,
      source: 'product_name',
    );
    final result = AnalysisEngine().analyze(
      IngredientMatchingResult(matches: matches),
      productContext: ctx,
    );
    expect(
      result.riskSignals.containsKey('sugar_syrup') ||
          result.riskSignals.containsKey('low_quality_oil'),
      true,
    );
    expect(result.productContextNote, isNotNull);
  });

  test('E - Unknown product type still analyses without context', () {
    final ingSugar = makeIngredient('1', 'şeker', 'şeker', 'medium');
    final ingPalm = makeIngredient('2', 'palm yağı', 'palm yağı', 'high');
    final matches = [
      makeMatch('şeker', 'şeker', ingSugar, 0.95, MatchType.exactMatch),
      makeMatch('palm yağı', 'palm yağı', ingPalm, 0.95, MatchType.exactMatch),
    ];
    final result = AnalysisEngine().analyze(
      IngredientMatchingResult(matches: matches),
    );
    expect(result.productContextNote, isNull);
    expect(result.riskSignals.containsKey('low_quality_oil'), true);
  });

  test(
    'F - Monster-like mix keeps caffeine prominent and vitamins/citrate neutral',
    () {
      final ingCafe = makeIngredient('f1', 'kafein', 'kafein', 'medium');
      final ingTaur = makeIngredient('f2', 'taurin', 'taurin', 'medium');
      final ingAces = makeIngredient(
        'f3',
        'asesülfam k',
        'asesülfam k',
        'medium',
      );
      final ingSuc = makeIngredient('f4', 'sukraloz', 'sukraloz', 'medium');
      final ingTriSitrat = makeIngredient(
        'f5',
        'tri sodyum sitrat',
        'tri sodyum sitrat',
        'low',
      );
      final ingLCarn = makeIngredient(
        'f6',
        'l-karnitin l-tartarat',
        'l-karnitin l-tartarat',
        'low',
      );
      final ingB6 = makeIngredient('f7', 'vitamin b6', 'vitamin b6', 'low');
      final ingB12 = makeIngredient('f8', 'vitamin b12', 'vitamin b12', 'low');

      final matches = [
        makeMatch('kafein', 'kafein', ingCafe, 0.95, MatchType.exactMatch),
        makeMatch('taurin', 'taurin', ingTaur, 0.95, MatchType.exactMatch),
        makeMatch(
          'asesülfam k',
          'asesülfam k',
          ingAces,
          0.95,
          MatchType.exactMatch,
        ),
        makeMatch('sukraloz', 'sukraloz', ingSuc, 0.95, MatchType.exactMatch),
        makeMatch(
          'tri sodyum sitrat',
          'tri sodyum sitrat',
          ingTriSitrat,
          0.95,
          MatchType.exactMatch,
        ),
        makeMatch(
          'l-karnitin l-tartarat',
          'l-karnitin l-tartarat',
          ingLCarn,
          0.95,
          MatchType.exactMatch,
        ),
        makeMatch(
          'vitamin b6',
          'vitamin b6',
          ingB6,
          0.95,
          MatchType.exactMatch,
        ),
        makeMatch(
          'vitamin b12',
          'vitamin b12',
          ingB12,
          0.95,
          MatchType.exactMatch,
        ),
      ];

      final result = AnalysisEngine().analyze(
        IngredientMatchingResult(matches: matches),
      );

      expect(result.riskSignals.containsKey('caffeine_stimulant'), true);
      expect(result.riskSignals.containsKey('artificial_sweetener'), true);
      expect(
        result.detectedRiskIngredients.any(
          (i) => i.normalizedName == 'l-karnitin l-tartarat',
        ),
        false,
      );
      expect(
        result.otherRecognizedIngredients.any(
          (i) => i.normalizedName == 'l-karnitin l-tartarat',
        ),
        true,
      );
      expect(
        result.otherRecognizedIngredients.any(
          (i) => i.normalizedName == 'tri sodyum sitrat',
        ),
        true,
      );
    },
  );

  test('G - Uncertain section hidden when reviewRequiredMatches empty', () {
    final ingSugar = makeIngredient('1', 'şeker', 'şeker', 'medium');
    final matches = [
      makeMatch('şeker', 'şeker', ingSugar, 0.95, MatchType.exactMatch),
    ];
    final result = AnalysisEngine().analyze(
      IngredientMatchingResult(matches: matches),
    );
    expect(result.reviewRequiredMatches.isEmpty, true);
  });

  test('H - Uncertain section visible when pending matches exist', () {
    final ingPalm = makeIngredient('2', 'palm yağı', 'palm yağı', 'high');
    final uncertainMatch = IngredientMatch(
      originalToken: 'palm',
      normalizedText: 'palm yağı',
      matchedIngredient: ingPalm,
      matchedToken: 'palm yağı',
      confidenceScore: 0.65,
      matchType: MatchType.lowConfidencePossible,
      shouldAffectAnalysis: false,
      needsUserConfirmation: true,
    );
    final matchResult = IngredientMatchingResult(matches: [uncertainMatch]);
    final result = AnalysisEngine().analyze(matchResult);
    expect(result.reviewRequiredMatches.isNotEmpty, true);
    expect(result.reviewRequiredMatches.length, 1);
  });

  test(
    'I - Approving uncertain match includes item in detectedRiskIngredients',
    () {
      final ingCafe = makeIngredient('c1', 'kafein', 'kafein', 'high');
      final uncertainMatch = IngredientMatch(
        originalToken: 'kaf',
        normalizedText: 'kafein',
        matchedIngredient: ingCafe,
        matchedToken: 'kafein',
        confidenceScore: 0.6,
        matchType: MatchType.lowConfidencePossible,
        shouldAffectAnalysis: false,
        needsUserConfirmation: true,
      );

      var matchResult = IngredientMatchingResult(matches: [uncertainMatch]);
      var result1 = AnalysisEngine().analyze(matchResult);
      expect(
        result1.detectedRiskIngredients.any(
          (i) => i.normalizedName == 'kafein',
        ),
        false,
      );

      // User approves the match
      final approvedMatch = uncertainMatch.approveLowConfidence();
      matchResult = IngredientMatchingResult(matches: [approvedMatch]);
      final result2 = AnalysisEngine().analyze(matchResult);
      expect(
        result2.detectedRiskIngredients.any(
          (i) => i.normalizedName == 'kafein',
        ),
        true,
      );
    },
  );

  test('J - Rejecting uncertain match excludes item from analysis', () {
    final ingPalm = makeIngredient('2', 'palm yağı', 'palm yağı', 'high');
    final uncertainMatch = IngredientMatch(
      originalToken: 'palm',
      normalizedText: 'palm yağı',
      matchedIngredient: ingPalm,
      matchedToken: 'palm yağı',
      confidenceScore: 0.65,
      matchType: MatchType.lowConfidencePossible,
      shouldAffectAnalysis: false,
      needsUserConfirmation: true,
    );

    var matchResult = IngredientMatchingResult(matches: [uncertainMatch]);
    var result1 = AnalysisEngine().analyze(matchResult);
    expect(result1.reviewRequiredMatches.length, 1);

    // User rejects the match
    final rejectedMatch = uncertainMatch.rejectLowConfidence();
    matchResult = IngredientMatchingResult(matches: [rejectedMatch]);
    final result2 = AnalysisEngine().analyze(matchResult);
    expect(
      result2.detectedRiskIngredients.any(
        (i) => i.normalizedName == 'palm yağı',
      ),
      false,
    );
  });

  test(
    'K - High-risk ingredients appear before medium-risk in detectedRiskIngredients',
    () {
      final ingHigh = makeIngredient('h1', 'kafein', 'kafein', 'high');
      final ingMed = makeIngredient('m1', 'şeker', 'şeker', 'medium');
      final matches = [
        makeMatch('kafein', 'kafein', ingHigh, 0.95, MatchType.exactMatch),
        makeMatch('şeker', 'şeker', ingMed, 0.95, MatchType.exactMatch),
      ];
      final result = AnalysisEngine().analyze(
        IngredientMatchingResult(matches: matches),
      );
      // High-risk added first, so caffeine should appear before sugar in list
      expect(result.detectedRiskIngredients.isNotEmpty, true);
      expect(result.detectedRiskIngredients[0].name, 'kafein');
    },
  );

  test(
    'L - Top 2 important ingredients processed, rest available for accordion',
    () {
      final ingHigh1 = makeIngredient('h1', 'kafein', 'kafein', 'high');
      final ingHigh2 = makeIngredient('h2', 'taurin', 'taurin', 'high');
      final ingMed1 = makeIngredient(
        'm1',
        'asesülfam k',
        'asesülfam k',
        'medium',
      );
      final ingMed2 = makeIngredient('m2', 'palm yağı', 'palm yağı', 'medium');

      final matches = [
        makeMatch('kafein', 'kafein', ingHigh1, 0.95, MatchType.exactMatch),
        makeMatch('taurin', 'taurin', ingHigh2, 0.95, MatchType.exactMatch),
        makeMatch(
          'asesülfam k',
          'asesülfam k',
          ingMed1,
          0.95,
          MatchType.exactMatch,
        ),
        makeMatch(
          'palm yağı',
          'palm yağı',
          ingMed2,
          0.95,
          MatchType.exactMatch,
        ),
      ];

      final result = AnalysisEngine().analyze(
        IngredientMatchingResult(matches: matches),
      );
      // Should have 4 high/medium risk ingredients detected
      expect(result.detectedRiskIngredients.length, 4);
      // UI layer will show top 2 and accordion for rest (test here just verifies all 4 are present)
      expect(result.detectedRiskIngredients.length >= 2, true);
    },
  );
}
