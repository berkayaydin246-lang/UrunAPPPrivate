import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/controllers/search_controller.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';

// Pure-Dart unit tests for search and category logic.
// Network/Supabase integration tests require a live connection and are
// therefore omitted here.

void main() {
  // ── ProductCategory model ─────────────────────────────────────────────────

  group('ProductCategories', () {
    test('all list is non-empty and has correct count', () {
      expect(ProductCategories.all, isNotEmpty);
      expect(ProductCategories.all.length, 12);
    });

    test(
      'every category has a non-empty id and title; non-fallback categories have keywords',
      () {
        for (final cat in ProductCategories.all) {
          expect(cat.id, isNotEmpty, reason: 'id empty for ${cat.title}');
          expect(cat.title, isNotEmpty, reason: 'title empty for ${cat.id}');
          // 'diger' is intentionally a keyword-free catch-all fallback.
          if (cat.id != 'diger') {
            expect(
              cat.keywords,
              isNotEmpty,
              reason: 'keywords empty for ${cat.id}',
            );
          }
        }
      },
    );

    test('all ids are unique', () {
      final ids = ProductCategories.all.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('findById returns correct category', () {
      final cat = ProductCategories.findById('atistirmalik');
      expect(cat, isNotNull);
      expect(cat!.title, 'Atıştırmalık');
    });

    test('findById returns null for unknown id', () {
      expect(ProductCategories.findById('unknown-xyz'), isNull);
    });

    test('snack category keywords include çikolata', () {
      final cat = ProductCategories.findById('atistirmalik')!;
      expect(cat.keywords, contains('çikolata'));
    });

    test('drink category keywords include energy drink', () {
      final cat = ProductCategories.findById('icecek')!;
      expect(cat.keywords, contains('energy drink'));
    });
  });

  // ── Product data-completeness helpers ─────────────────────────────────────

  final now = DateTime(2026, 1, 1);

  Product makeProduct({
    String? ingredientsText,
    String? nutritionText,
    String? imageUrl,
  }) {
    return Product(
      id: 'test-id',
      name: 'Test Ürün',
      ingredientsText: ingredientsText,
      nutritionText: nutritionText,
      imageUrl: imageUrl,
      verificationStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
  }

  group('Product.hasIngredients', () {
    test('true when ingredients_text is long enough', () {
      final p = makeProduct(ingredientsText: 'su, tuz, şeker');
      expect(p.hasIngredients, isTrue);
    });

    test('false when ingredients_text is null', () {
      expect(makeProduct().hasIngredients, isFalse);
    });

    test('false when ingredients_text is too short (≤10 chars)', () {
      expect(makeProduct(ingredientsText: 'su').hasIngredients, isFalse);
    });

    test('false when ingredients_text is only whitespace', () {
      expect(makeProduct(ingredientsText: '   ').hasIngredients, isFalse);
    });
  });

  group('Product.hasNutrition', () {
    test('true when nutrition_text has data', () {
      expect(
        makeProduct(nutritionText: '{"energy_kcal":190}').hasNutrition,
        isTrue,
      );
    });

    test('false when nutrition_text is null', () {
      expect(makeProduct().hasNutrition, isFalse);
    });

    test('false when nutrition_text is too short', () {
      expect(makeProduct(nutritionText: '{}').hasNutrition, isFalse);
    });
  });

  group('Product.hasImage', () {
    test('true when imageUrl is set', () {
      expect(makeProduct(imageUrl: 'https://cdn/img.jpg').hasImage, isTrue);
    });

    test('false when imageUrl is null', () {
      expect(makeProduct().hasImage, isFalse);
    });

    test('false when imageUrl is empty string', () {
      expect(makeProduct(imageUrl: '').hasImage, isFalse);
    });
  });

  // ── SearchQueryNotifier ───────────────────────────────────────────────────

  group('SearchQueryNotifier', () {
    test('initial state is empty string', () {
      final notifier = SearchQueryNotifier();
      expect(notifier.state, '');
    });

    test('setQuery updates state', () {
      final notifier = SearchQueryNotifier();
      notifier.setQuery('çikolata');
      expect(notifier.state, 'çikolata');
    });

    test('clear resets state to empty string', () {
      final notifier = SearchQueryNotifier();
      notifier.setQuery('test');
      notifier.clear();
      expect(notifier.state, '');
    });
  });

  // ── OffTextSearchState ────────────────────────────────────────────────────

  group('OffTextSearchState', () {
    test('initial state has empty results and empty lastQuery', () {
      const s = OffTextSearchState();
      expect(s.lastQuery, '');
      expect(s.results, isA<AsyncData>());
    });

    test('copyWith preserves unmodified fields', () {
      const s = OffTextSearchState(lastQuery: 'kinder');
      final s2 = s.copyWith(results: const AsyncValue.loading());
      expect(s2.lastQuery, 'kinder');
      expect(s2.results, isA<AsyncLoading>());
    });
  });

  // ── Keyword search query construction ────────────────────────────────────

  group('category keyword construction', () {
    test('snack category keywords produce at least 3 search terms', () {
      final cat = ProductCategories.findById('atistirmalik')!;
      expect(cat.keywords.length, greaterThanOrEqualTo(3));
    });

    test('query parts built from keywords cover name and brand', () {
      const keywords = ['çikolata', 'gofret'];
      final parts = keywords
          .expand(
            (kw) => [
              'name.ilike.%$kw%',
              'brand.ilike.%$kw%',
              'normalized_name.ilike.%$kw%',
            ],
          )
          .toList();
      expect(parts, hasLength(6));
      expect(parts, contains('name.ilike.%çikolata%'));
      expect(parts, contains('brand.ilike.%gofret%'));
    });
  });
}
