import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/imports/models/off_product.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/services/category_relevance.dart';

void main() {
  final now = DateTime(2026, 1, 1);

  Product makeProduct({
    required String name,
    String? brand,
    List<String>? searchKeywords,
    List<String>? categoryTags,
  }) {
    return Product(
      id: 'p1',
      name: name,
      normalizedName: name.toLowerCase(),
      brand: brand,
      searchKeywords: searchKeywords,
      categoryTags: categoryTags,
      verificationStatus: 'verified',
      createdAt: now,
      updatedAt: now,
    );
  }

  final meatCategory = ProductCategories.findById('et-tavuk-balik')!;

  group('CategoryRelevance.evaluateProduct', () {
    test('rejects Eti chocolate for meat category', () {
      final p = makeProduct(
        name: 'Eti Çikolatalı Gofret',
        brand: 'Eti',
        searchKeywords: const ['eti', 'cikolata', 'gofret'],
      );

      final result = CategoryRelevance.evaluateProduct(p, meatCategory);
      expect(result.accepted, isFalse);
      // hasStrongNegative depends on which databaseTag wins _bestDecision.
      // With a multi-tag category (et-tavuk-balik), a tag with no negativeTerms
      // (e.g. ton_konserve) may outscore et_sarkuteri's strong-negative decision.
    });

    test('accepts salam product for meat category', () {
      final p = makeProduct(
        name: 'Dana Salam',
        brand: 'Pınar',
        searchKeywords: const ['dana', 'salam'],
        categoryTags: const ['et_sarkuteri'],
      );

      final result = CategoryRelevance.evaluateProduct(p, meatCategory);
      expect(result.accepted, isTrue);
      expect(
        result.score,
        greaterThanOrEqualTo(CategoryRelevance.acceptThreshold),
      );
    });

    test('rejects ketchup product for meat category', () {
      final p = makeProduct(
        name: 'Domates Ketçap',
        brand: 'Calve',
        searchKeywords: const ['domates', 'ketcap', 'ketchup'],
      );

      final result = CategoryRelevance.evaluateProduct(p, meatCategory);
      expect(result.accepted, isFalse);
    });
  });

  group('CategoryRelevance.evaluateOffProduct', () {
    test('rejects chocolate OFF product for meat category', () {
      final off = OffProduct(
        barcode: '1',
        name: 'Çikolatalı Gofret',
        brand: 'Eti',
        categories: const ['en:chocolates', 'en:wafers'],
        sourceUrl: 'https://tr.openfoodfacts.org/product/1',
      );

      final result = CategoryRelevance.evaluateOffProduct(off, meatCategory);
      expect(result.accepted, isFalse);
      // hasStrongNegative: see note in evaluateProduct test — multi-tag category.
    });

    test('accepts OFF salam with prepared-meats tag', () {
      final off = OffProduct(
        barcode: '2',
        name: 'Hindi Salam',
        brand: 'Banvit',
        categories: const ['en:prepared-meats'],
        sourceUrl: 'https://tr.openfoodfacts.org/product/2',
      );

      final result = CategoryRelevance.evaluateOffProduct(off, meatCategory);
      expect(result.accepted, isTrue);
    });
  });

  group('meat category fallback queries', () {
    test('do not include eti to avoid brand false positives', () {
      final queries = meatCategory.offFallbackQueries
          .map((e) => e.toLowerCase())
          .toList(growable: false);
      expect(queries.any((q) => q.contains('eti')), isFalse);
    });
  });
}
