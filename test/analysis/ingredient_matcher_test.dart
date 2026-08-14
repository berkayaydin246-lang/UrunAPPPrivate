import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/analysis/engines/analysis_engine.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

Ingredient _ingredient({
  required String id,
  required String name,
  required String normalizedName,
  List<String>? aliases,
  String? eCode,
  String riskLevel = 'low',
}) {
  final now = DateTime(2026, 5, 9);
  return Ingredient(
    id: id,
    name: name,
    normalizedName: normalizedName,
    aliases: aliases,
    eCode: eCode,
    riskLevel: riskLevel,
    createdAt: now,
    updatedAt: now,
  );
}

List<Ingredient> _ingredients() => [
  _ingredient(
    id: '1',
    name: 'Sodyum Nitrit',
    normalizedName: 'sodyum nitrit',
    aliases: ['sodium nitrite', 'nitrit'],
    eCode: 'E250',
    riskLevel: 'high',
  ),
  _ingredient(
    id: '2',
    name: 'Tartrazin',
    normalizedName: 'tartrazin',
    aliases: ['e102'],
    eCode: 'E102',
    riskLevel: 'high',
  ),
  _ingredient(
    id: '3',
    name: 'Sitrik Asit',
    normalizedName: 'sitrik asit',
    aliases: ['citric acid'],
    eCode: 'E330',
  ),
  _ingredient(
    id: '4',
    name: 'Askorbik Asit',
    normalizedName: 'askorbik asit',
    aliases: ['vitamin c'],
    eCode: 'E300',
  ),
  _ingredient(
    id: '5',
    name: 'Palm Yağı',
    normalizedName: 'palm yağı',
    aliases: ['palm oil'],
  ),
  _ingredient(
    id: '6',
    name: 'Glikoz Şurubu',
    normalizedName: 'glikoz şurubu',
    aliases: ['glucose syrup'],
    riskLevel: 'high',
  ),
  _ingredient(id: '7', name: 'Tuz', normalizedName: 'tuz', riskLevel: 'medium'),
  _ingredient(id: '8', name: 'Şeker', normalizedName: 'şeker'),
  _ingredient(id: '9', name: 'Lesitin', normalizedName: 'lesitin'),
  _ingredient(id: '10', name: 'Soya', normalizedName: 'soya'),
];

void main() {
  group('IngredientMatcherService', () {
    final service = IngredientMatcherService();

    test('sodyum nitrit should match Sodyum Nitrit', () async {
      final result = await service.matchIngredients(
        'sodyum nitrit',
        _ingredients(),
      );
      expect(result.getConfirmedMatches(), hasLength(1));
      expect(
        result.getConfirmedMatches().first.matchedIngredient!.name,
        'Sodyum Nitrit',
      );
      expect(
        result.getConfirmedMatches().first.matchType,
        MatchType.exactMatch,
      );
    });

    test('E250 should match Sodyum Nitrit', () async {
      final result = await service.matchIngredients('E250', _ingredients());
      expect(result.getConfirmedMatches(), hasLength(1));
      expect(
        result.getConfirmedMatches().first.matchedIngredient!.name,
        'Sodyum Nitrit',
      );
      expect(
        result.getConfirmedMatches().first.matchType,
        MatchType.eCodeMatch,
      );
    });

    test('tartrazin should match only when present', () async {
      final withTartrazin = await service.matchIngredients(
        'su, tartrazin, şeker',
        _ingredients(),
      );
      expect(
        withTartrazin.getConfirmedMatches().any(
          (m) => m.matchedIngredient?.name == 'Tartrazin',
        ),
        isTrue,
      );

      final withoutTartrazin = await service.matchIngredients(
        'su, şeker, aroma vericiler',
        _ingredients(),
      );
      expect(
        withoutTartrazin.matches.any(
          (m) => m.matchedIngredient?.name == 'Tartrazin',
        ),
        isFalse,
      );
    });

    test('sitrik asit must not become askorbik asit', () async {
      final result = await service.matchIngredients(
        'sitrik asit',
        _ingredients(),
      );
      expect(result.getConfirmedMatches(), hasLength(1));
      expect(
        result.getConfirmedMatches().first.matchedIngredient!.name,
        'Sitrik Asit',
      );
      expect(
        result.getConfirmedMatches().first.matchedIngredient!.name,
        isNot('Askorbik Asit'),
      );
    });

    test('kalsiyum propiyonat never fuzzy matches Kalsiyum Forminat', () async {
      final result = await service.matchIngredients('kalsiyum propiyonat', [
        _ingredient(
          id: 'forminate',
          name: 'Kalsiyum Forminat',
          normalizedName: 'kalsiyum format',
        ),
      ]);

      expect(result.matches, hasLength(1));
      expect(
        result.matches.single.matchedIngredient?.name,
        'Kalsiyum Propiyonat',
      );
      expect(result.matches.single.matchedIngredient?.eCode, 'E282');
      expect(result.matches.single.matchedIngredient?.riskLevel, 'unknown');
      expect(result.matches.single.matchType, MatchType.exactMatch);
      expect(
        result.matches.single.matchedIngredient?.name,
        isNot('Kalsiyum Forminat'),
      );
    });

    test('E282 Turkish, English, and E-code aliases resolve exactly', () async {
      for (final expectation in const [
        ('kalsiyum propiyonat', MatchType.exactMatch),
        ('calcium propionate', MatchType.aliasMatch),
        ('E282', MatchType.eCodeMatch),
      ]) {
        final result = await service.matchIngredients(expectation.$1, const []);

        expect(result.matches.single.matchedIngredient?.eCode, 'E282');
        expect(result.matches.single.matchedIngredient?.riskLevel, 'unknown');
        expect(result.matches.single.matchType, expectation.$2);
      }
    });

    test('exact propiyonat name beats an earlier fuzzy candidate', () async {
      final result = await service.matchIngredients('kalsiyum propiyonat', [
        _ingredient(
          id: 'forminate',
          name: 'Kalsiyum Forminat',
          normalizedName: 'kalsiyum format',
        ),
        _ingredient(
          id: 'propionate',
          name: 'Kalsiyum Propiyonat',
          normalizedName: 'kalsiyum propiyonat',
          eCode: 'E282',
        ),
      ]);

      expect(
        result.matches.single.matchedIngredient?.name,
        'Kalsiyum Propiyonat',
      );
      expect(result.matches.single.matchType, MatchType.exactMatch);
    });

    test('unspecified aroma vericiler stays unresolved', () async {
      final result = await service.matchIngredients('aroma vericiler', [
        _ingredient(
          id: 'generic-flavoring',
          name: 'Aroma Vericileri',
          normalizedName: 'aroma vericileri',
          aliases: const ['aroma vericiler', 'aroma verici'],
        ),
      ]);

      expect(result.matches.single.matchedIngredient, isNull);
      expect(result.matches.single.matchType, MatchType.unmatched);
      expect(result.matches.single.originalToken, 'aroma vericiler');
    });

    test('palm yağı should match Palm Yağı', () async {
      final result = await service.matchIngredients(
        'palm yağı',
        _ingredients(),
      );
      expect(
        result.getConfirmedMatches().first.matchedIngredient!.name,
        'Palm Yağı',
      );
    });

    test('glikoz şurubu should match Glikoz Şurubu', () async {
      final result = await service.matchIngredients(
        'glikoz şurubu',
        _ingredients(),
      );
      expect(
        result.getConfirmedMatches().first.matchedIngredient!.name,
        'Glikoz Şurubu',
      );
    });

    test('random OCR garbage should remain unmatched', () async {
      final result = await service.matchIngredients(
        'xqz ### @@',
        _ingredients(),
      );
      expect(result.getUnmatched(), isNotEmpty);
      expect(result.getConfirmedMatches(), isEmpty);
    });

    test('trailing section letter artifact still detects Tuz', () async {
      final result = await service.matchIngredients(
        'BEYAZ LEBLEBİ, TUZ A',
        _ingredients(),
      );

      expect(
        result.getConfirmedMatches().any(
          (match) => match.matchedIngredient?.name == 'Tuz',
        ),
        isTrue,
      );
      expect(
        result.getConfirmedMatches().any(
          (match) => match.originalToken.toUpperCase().contains('TUZ A'),
        ),
        isFalse,
      );
    });

    test('toz şeker detects Şeker', () async {
      final result = await service.matchIngredients(
        'TOZ ŞEKER',
        _ingredients(),
      );

      expect(
        result.getConfirmedMatches().first.matchedIngredient!.name,
        'Şeker',
      );
    });

    test('bitkisel yağ (palm) detects Palm Yağı', () async {
      final result = await service.matchIngredients(
        'bitkisel yağ (palm)',
        _ingredients(),
      );

      expect(
        result.getConfirmedMatches().any(
          (match) => match.matchedIngredient?.name == 'Palm Yağı',
        ),
        isTrue,
      );
    });

    test('emülgatör: lesitin (soya) detects lesitin and soya', () async {
      final result = await service.matchIngredients(
        'emülgatör: lesitin (soya)',
        _ingredients(),
      );

      expect(
        result.getConfirmedMatches().any(
          (match) => match.matchedIngredient?.name == 'Lesitin',
        ),
        isTrue,
      );
      expect(
        result.getConfirmedMatches().any(
          (match) => match.matchedIngredient?.name == 'Soya',
        ),
        isTrue,
      );
    });
  });

  group('AnalysisEngine', () {
    const engine = AnalysisEngine();

    test('low-confidence matches do not affect analysis until approved', () {
      final tartrazin = _ingredient(
        id: '7',
        name: 'Tartrazin',
        normalizedName: 'tartrazin',
        aliases: ['e102'],
        eCode: 'E102',
        riskLevel: 'high',
      );

      final lowConfidence = IngredientMatch(
        originalToken: 'tartrazln',
        normalizedText: 'tartrazln',
        matchedIngredient: tartrazin,
        matchedToken: 'tartrazin',
        confidenceScore: 0.81,
        matchType: MatchType.lowConfidencePossible,
        shouldAffectAnalysis: false,
        needsUserConfirmation: true,
      );

      final matchingResult = IngredientMatchingResult(matches: [lowConfidence]);
      final result = engine.analyze(matchingResult, category: null);

      expect(result.detectedRiskIngredients, isEmpty);
      expect(result.reviewRequiredMatches, hasLength(1));

      final approvedResult = matchingResult.updateDecision('tartrazln', true);
      final approvedAnalysis = engine.analyze(approvedResult, category: null);
      expect(approvedAnalysis.detectedRiskIngredients, hasLength(1));
      expect(approvedAnalysis.detectedRiskIngredients.first.name, 'Tartrazin');
    });
  });
}
