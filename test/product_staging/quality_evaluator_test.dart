import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';
import 'package:food_analyzer_app/features/product_staging/services/product_candidate_quality_evaluator.dart';

void main() {
  const evaluator = ProductCandidateQualityEvaluator();

  group('quality_score calculation', () {
    test('empty candidate scores 0 and is insufficient_data', () {
      const candidate = ProductCandidate(source: 'open_food_facts');
      final r = evaluator.evaluate(candidate);
      expect(r.qualityScore, 0);
      expect(r.suggestedStatus, 'insufficient_data');
      expect(
        r.missingFields,
        containsAll([
          'barcode',
          'name',
          'brand',
          'front_image',
          'ingredients',
          'nutrition',
          'category',
        ]),
      );
    });

    test('barcode + name only = 30 → insufficient_data', () {
      const candidate = ProductCandidate(
        source: 'open_food_facts',
        barcode: '123',
        name: 'Test',
      );
      final r = evaluator.evaluate(candidate);
      expect(r.qualityScore, 30);
      expect(r.suggestedStatus, 'insufficient_data');
    });

    test('barcode+name+brand+image+category = 65 → needs_review', () {
      const candidate = ProductCandidate(
        source: 'open_food_facts',
        barcode: '123',
        name: 'Test',
        brand: 'Eti',
        imageFrontUrl: 'https://img/front.jpg',
        categorySuggestion: 'Kekler',
      );
      final r = evaluator.evaluate(candidate);
      expect(r.qualityScore, 65); // 15+15+10+15+10
      expect(r.suggestedStatus, 'needs_review');
      expect(r.missingFields, containsAll(['ingredients', 'nutrition']));
    });

    test('full candidate scores 100 → pending', () {
      const candidate = ProductCandidate(
        source: 'open_food_facts',
        barcode: '8690526069906',
        name: 'Popkek Bitter Çikolatalı',
        brand: 'Eti',
        imageFrontUrl: 'https://img/front.jpg',
        ingredientsText:
            'buğday unu, şeker, bitkisel yağ, kakao, yumurta, kabartıcı',
        nutritionJson: {'energy_kcal': 424.0, 'fat': 20.0, 'salt': 0.8},
        categorySuggestion: 'Kekler',
      );
      final r = evaluator.evaluate(candidate);
      // 15+15+10+15+25+20+10 = 110 → clamped to 100
      expect(r.qualityScore, 100);
      expect(r.suggestedStatus, 'pending');
      expect(r.missingFields, isEmpty);
    });

    test('short ingredients (<=20 chars) does not score ingredients', () {
      const candidate = ProductCandidate(
        source: 'open_food_facts',
        ingredientsText: 'un, şeker',
      );
      final r = evaluator.evaluate(candidate);
      expect(r.qualityScore, 0);
      expect(r.missingFields, contains('ingredients'));
    });

    test('nutrition_json with no useful values does not score nutrition', () {
      const candidate = ProductCandidate(
        source: 'open_food_facts',
        nutritionJson: {'serving_size': '55 g'}, // no numeric nutrients
      );
      final r = evaluator.evaluate(candidate);
      expect(r.missingFields, contains('nutrition'));
    });

    test('category_tags alone satisfies category', () {
      const candidate = ProductCandidate(
        source: 'open_food_facts',
        categoryTags: ['en:cakes'],
      );
      final r = evaluator.evaluate(candidate);
      expect(r.qualityScore, 10);
      expect(r.missingFields, isNot(contains('category')));
    });
  });
}
