import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';

void main() {
  group('ProductCandidate serialization', () {
    test('fromJson → toJson round-trip preserves fields', () {
      final json = {
        'id': 'abc-1',
        'barcode': '8690526069906',
        'name': 'Popkek Bitter Çikolatalı',
        'brand': 'Eti',
        'category_suggestion': 'Kekler',
        'category_tags': ['en:cakes'],
        'search_keywords': ['popkek', 'cikolata'],
        'image_front_url': 'https://img/front.jpg',
        'ingredients_text': 'un, şeker, kakao',
        'nutrition_json': {'energy_kcal': 424.0, 'fat': 20.0},
        'source': 'open_food_facts',
        'source_url': 'https://tr.openfoodfacts.org/product/8690526069906',
        'raw_source_payload': {'code': '8690526069906'},
        'name_source': 'open_food_facts',
        'quality_score': 90,
        'missing_fields': <String>[],
        'status': 'pending',
        'created_at': '2026-06-02T10:00:00.000Z',
        'updated_at': '2026-06-02T10:00:00.000Z',
      };

      final candidate = ProductCandidate.fromJson(json);
      expect(candidate.id, 'abc-1');
      expect(candidate.barcode, '8690526069906');
      expect(candidate.name, 'Popkek Bitter Çikolatalı');
      expect(candidate.brand, 'Eti');
      expect(candidate.categoryTags, ['en:cakes']);
      expect(candidate.searchKeywords, ['popkek', 'cikolata']);
      expect(candidate.nutritionJson?['energy_kcal'], 424.0);
      expect(candidate.qualityScore, 90);
      expect(candidate.status, 'pending');

      final back = candidate.toJson();
      expect(back['barcode'], '8690526069906');
      expect(back['nutrition_json'], {'energy_kcal': 424.0, 'fat': 20.0});
      expect(back['quality_score'], 90);
    });

    test('safe null handling on minimal json', () {
      final candidate = ProductCandidate.fromJson({'source': 'manual_seed'});
      expect(candidate.source, 'manual_seed');
      expect(candidate.barcode, isNull);
      expect(candidate.name, isNull);
      expect(candidate.categoryTags, isNull);
      expect(candidate.missingFields, isEmpty);
      expect(candidate.status, 'pending');
      expect(candidate.qualityScore, 0);
    });

    test('nutrition getter reads nutritionJson via NutritionData', () {
      const candidate = ProductCandidate(
        source: 'open_food_facts',
        nutritionJson: {'energy_kcal': 424.0, 'salt': 0.8},
      );
      final n = candidate.nutrition;
      expect(n, isNotNull);
      expect(n!.energyKcal, 424.0);
      expect(n.salt, 0.8);
      expect(n.hasAnyData, isTrue);
    });

    test('nutrition getter returns null for empty map', () {
      const candidate = ProductCandidate(
        source: 'open_food_facts',
        nutritionJson: {},
      );
      expect(candidate.nutrition, isNull);
    });
  });

  group('toStagingInsertMap', () {
    test(
      'drops null/empty values but always keeps required quality fields',
      () {
        const candidate = ProductCandidate(
          barcode: '123',
          name: 'Test',
          brand: '',
          categoryTags: [],
          source: 'open_food_facts',
          qualityScore: 40,
          missingFields: ['brand', 'category'],
          status: 'insufficient_data',
        );

        final map = candidate.toStagingInsertMap();
        expect(map['barcode'], '123');
        expect(map['name'], 'Test');
        // empty brand dropped
        expect(map.containsKey('brand'), isFalse);
        // empty list dropped
        expect(map.containsKey('category_tags'), isFalse);
        // required fields always present
        expect(map['source'], 'open_food_facts');
        expect(map['quality_score'], 40);
        expect(map['missing_fields'], ['brand', 'category']);
        expect(map['status'], 'insufficient_data');
        // id/timestamps never included
        expect(map.containsKey('id'), isFalse);
        expect(map.containsKey('created_at'), isFalse);
      },
    );
  });

  group('copyWith', () {
    test('overrides only specified fields', () {
      const candidate = ProductCandidate(source: 'open_food_facts', name: 'A');
      final updated = candidate.copyWith(name: 'B', qualityScore: 50);
      expect(updated.name, 'B');
      expect(updated.qualityScore, 50);
      expect(updated.source, 'open_food_facts');
    });
  });
}
