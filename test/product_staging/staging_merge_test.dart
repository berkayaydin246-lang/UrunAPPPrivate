import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';
import 'package:food_analyzer_app/features/product_staging/repositories/product_staging_repository.dart';

void main() {
  group('ProductStagingRepository.mergeFillMissing', () {
    test('fills null/empty existing fields from incoming', () {
      const existing = ProductCandidate(
        source: 'open_food_facts',
        barcode: '123',
        name: 'Existing Name',
        brand: null, // missing
        ingredientsText: '', // empty
      );
      const incoming = ProductCandidate(
        source: 'open_food_facts',
        barcode: '123',
        name: 'New Name',
        brand: 'Eti',
        ingredientsText: 'un, şeker, kakao, bitkisel yağ',
        imageFrontUrl: 'https://img/front.jpg',
      );

      final merged = ProductStagingRepository.mergeFillMissing(
        existing,
        incoming,
      );

      // existing non-null preserved
      expect(merged.name, 'Existing Name');
      // missing filled
      expect(merged.brand, 'Eti');
      // empty filled
      expect(merged.ingredientsText, 'un, şeker, kakao, bitkisel yağ');
      // brand-new field added
      expect(merged.imageFrontUrl, 'https://img/front.jpg');
    });

    test('never overwrites existing non-null fields', () {
      const existing = ProductCandidate(
        source: 'open_food_facts',
        name: 'Keep Me',
        brand: 'KeepBrand',
        imageFrontUrl: 'https://existing/img.jpg',
        nutritionJson: {'energy_kcal': 100.0},
        categoryTags: ['en:original'],
      );
      const incoming = ProductCandidate(
        source: 'open_food_facts',
        name: 'Override Attempt',
        brand: 'OtherBrand',
        imageFrontUrl: 'https://new/img.jpg',
        nutritionJson: {'energy_kcal': 999.0},
        categoryTags: ['en:other'],
      );

      final merged = ProductStagingRepository.mergeFillMissing(
        existing,
        incoming,
      );

      expect(merged.name, 'Keep Me');
      expect(merged.brand, 'KeepBrand');
      expect(merged.imageFrontUrl, 'https://existing/img.jpg');
      expect(merged.nutritionJson, {'energy_kcal': 100.0});
      expect(merged.categoryTags, ['en:original']);
    });

    test('always refreshes raw_source_payload from incoming', () {
      const existing = ProductCandidate(
        source: 'open_food_facts',
        rawSourcePayload: {'old': true},
      );
      const incoming = ProductCandidate(
        source: 'open_food_facts',
        rawSourcePayload: {'new': true},
      );

      final merged = ProductStagingRepository.mergeFillMissing(
        existing,
        incoming,
      );
      expect(merged.rawSourcePayload, {'new': true});
    });

    test('keeps existing raw payload when incoming has none', () {
      const existing = ProductCandidate(
        source: 'open_food_facts',
        rawSourcePayload: {'keep': true},
      );
      const incoming = ProductCandidate(source: 'open_food_facts');

      final merged = ProductStagingRepository.mergeFillMissing(
        existing,
        incoming,
      );
      expect(merged.rawSourcePayload, {'keep': true});
    });
  });
}
