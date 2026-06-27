import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product_staging/connectors/open_food_facts_candidate_connector.dart';

void main() {
  final connector = OpenFoodFactsCandidateConnector();

  group('candidateFromOffJson', () {
    test('prefers Turkish product_name_tr over English', () {
      final candidate = connector.candidateFromOffJson({
        'code': '8690526069906',
        'product_name_tr': 'Popkek Bitter Çikolatalı',
        'product_name': 'Popcake Dark Chocolate',
        'product_name_en': 'Popcake Dark Chocolate',
        'brands': 'Eti',
      });
      expect(candidate.name, 'Popkek Bitter Çikolatalı');
      expect(candidate.brand, 'Eti');
      expect(candidate.barcode, '8690526069906');
      expect(candidate.source, 'open_food_facts');
    });

    test('maps nutriments into NutritionData-compatible nutrition_json', () {
      final candidate = connector.candidateFromOffJson({
        'code': '8690526069906',
        'product_name_tr': 'Popkek',
        'nutriments': {
          'energy-kcal_100g': 424,
          'fat_100g': 20,
          'saturated-fat_100g': 10,
          'carbohydrates_100g': 55,
          'sugars_100g': 35,
          'proteins_100g': 6,
          'salt_100g': 0.8,
        },
      });

      final nj = candidate.nutritionJson;
      expect(nj, isNotNull);
      // Keys must match NutritionData.toMap()
      expect(nj!['energy_kcal'], 424.0);
      expect(nj['fat'], 20.0);
      expect(nj['saturated_fat'], 10.0);
      expect(nj['carbohydrates'], 55.0);
      expect(nj['sugars'], 35.0);
      expect(nj['proteins'], 6.0);
      expect(nj['salt'], 0.8);

      // And it round-trips through the NutritionData getter
      expect(candidate.nutrition?.energyKcal, 424.0);
      expect(candidate.nutrition?.salt, 0.8);
    });

    test('first brand is used when brands is comma-separated', () {
      final candidate = connector.candidateFromOffJson({
        'code': '1',
        'product_name': 'X',
        'brands': 'Eti, Ülker',
      });
      expect(candidate.brand, 'Eti');
    });

    test('field-level sources set only for populated fields', () {
      final candidate = connector.candidateFromOffJson({
        'code': '1',
        'product_name_tr': 'Adlı Ürün',
        // no brand, no image, no ingredients, no nutrition, no category
      });
      expect(candidate.nameSource, 'open_food_facts');
      expect(candidate.brandSource, isNull);
      expect(candidate.imageSource, isNull);
      expect(candidate.ingredientsSource, isNull);
      expect(candidate.nutritionSource, isNull);
      expect(candidate.categorySource, isNull);
    });

    test('rawSourcePayload preserves the original OFF json', () {
      final raw = {'code': '1', 'product_name': 'X', 'extra_field': 'kept'};
      final candidate = connector.candidateFromOffJson(raw);
      expect(candidate.rawSourcePayload?['extra_field'], 'kept');
    });

    test('prefers ingredients_text_tr over en', () {
      final candidate = connector.candidateFromOffJson({
        'code': '1',
        'product_name': 'X',
        'ingredients_text_tr': 'un, şeker',
        'ingredients_text_en': 'flour, sugar',
      });
      expect(candidate.ingredientsText, 'un, şeker');
    });

    test('selects front image from selected_images.front.display.tr', () {
      final candidate = connector.candidateFromOffJson({
        'code': '1',
        'product_name': 'X',
        'selected_images': {
          'front': {
            'display': {'tr': 'https://img/tr.jpg', 'en': 'https://img/en.jpg'},
          },
        },
        'image_front_url': 'https://img/fallback.jpg',
      });
      expect(candidate.imageFrontUrl, 'https://img/tr.jpg');
      expect(candidate.imageSource, 'open_food_facts');
    });

    test('category_suggestion and category_tags mapped from OFF', () {
      final candidate = connector.candidateFromOffJson({
        'code': '1',
        'product_name': 'X',
        'categories': 'Kekler, Çikolatalı',
        'categories_tags': ['en:cakes', 'en:chocolate-cakes'],
      });
      expect(candidate.categorySuggestion, 'Kekler, Çikolatalı');
      expect(candidate.categoryTags, ['en:cakes', 'en:chocolate-cakes']);
      expect(candidate.categorySource, 'open_food_facts');
    });
  });
}
