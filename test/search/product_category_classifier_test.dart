import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/search/services/product_category_classifier.dart';

void main() {
  group('ProductCategoryClassifier', () {
    test('Lay\'s Yoğurt ve Mevsim Yeşillikli is chips, not dairy', () {
      final result = ProductCategoryClassifier.classify(
        name: "Lay's Yoğurt ve Mevsim Yeşillikli",
        brand: "Lay's",
        searchKeywords: const [
          'lays',
          'yogurt',
          'mevsim',
          'yesillikli',
          'chips',
        ],
        offCategoryTags: const ['en:chips-and-fries', 'en:salty-snacks'],
      );

      expect(result.categoryTags, contains('cips_kraker'));
      expect(result.categoryTags, contains('atistirmalik'));
      expect(result.categoryTags, isNot(contains('sut_urunleri')));
      expect(result.categoryTags, isNot(contains('peynir_yogurt')));
    });

    test('Eti brand chocolate does not match meat', () {
      final result = ProductCategoryClassifier.classify(
        name: 'Eti Çikolatalı Gofret',
        brand: 'Eti',
        searchKeywords: const ['eti', 'cikolata', 'gofret'],
      );

      expect(result.categoryTags, contains('cikolata_gofret'));
      expect(result.categoryTags, isNot(contains('et_sarkuteri')));
    });

    test('Hindi Salam matches meat category', () {
      final result = ProductCategoryClassifier.classify(
        name: 'Hindi Salam',
        brand: 'Pınar',
        searchKeywords: const ['hindi', 'salam'],
        offCategoryTags: const ['en:prepared-meats'],
      );

      expect(result.categoryTags, contains('et_sarkuteri'));
    });

    test('Namet Macar Salam matches meat category', () {
      final result = ProductCategoryClassifier.classify(
        name: 'Namet Macar Salam',
        brand: 'Namet',
        searchKeywords: const ['namet', 'macar', 'salam'],
        offCategoryTags: const ['en:prepared-meats'],
      );

      expect(result.categoryTags, contains('et_sarkuteri'));
    });

    test('Bol Bol Ketçap does not match meat and can match sauce', () {
      final result = ProductCategoryClassifier.classify(
        name: 'Bol Bol Ketçap',
        brand: 'Bol Bol',
        searchKeywords: const ['ketcap', 'ketchup'],
        offCategoryTags: const ['en:sauces'],
      );

      expect(result.categoryTags, isNot(contains('et_sarkuteri')));
      expect(result.categoryTags, contains('soslar'));
    });

    test('Eti Crax Çubuk Kraker matches chips and not meat', () {
      final result = ProductCategoryClassifier.classify(
        name: 'Eti Crax Çubuk Kraker',
        brand: 'Eti',
        searchKeywords: const ['eti', 'crax', 'cubuk', 'kraker'],
        offCategoryTags: const ['en:crackers', 'en:salty-snacks'],
      );

      expect(result.categoryTags, contains('cips_kraker'));
      expect(result.categoryTags, isNot(contains('et_sarkuteri')));
    });

    test('Çikolatalı Gofret matches chocolate and not meat', () {
      final result = ProductCategoryClassifier.classify(
        name: 'Çikolatalı Gofret',
        searchKeywords: const ['cikolata', 'gofret', 'wafer'],
        offCategoryTags: const ['en:wafers', 'en:chocolates'],
      );

      expect(result.categoryTags, contains('cikolata_gofret'));
      expect(result.categoryTags, isNot(contains('et_sarkuteri')));
    });
  });
}
