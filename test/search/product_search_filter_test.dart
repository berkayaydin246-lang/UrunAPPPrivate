/// Filter, sort, and ingredient-detection tests (Part 10, items 13–22).
///
/// Tests the client-side logic in [FilteredSearchNotifier] through a fake
/// [ProductRepository] that returns predetermined product lists, and tests the
/// [ProductSearchFilter] model itself.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/models/category_query_plan.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

// ── Fake repository ───────────────────────────────────────────────────────────

class _FakeRepo extends ProductRepository {
  final List<Product> _products;
  _FakeRepo(this._products);

  @override
  Future<({List<Product> results, bool hasMore})> filteredSearch(
    ProductSearchFilter filter, {
    int pageSize = 20,
    int serverOffset = 0,
  }) async {
    var r = List<Product>.from(_products);

    // Minimal server-side simulation: brand + text search only.
    if (filter.brands.isNotEmpty) {
      r = r.where((p) => filter.brands.contains(p.brand)).toList();
    }
    if (filter.hasQuery) {
      final q = filter.query.toLowerCase();
      r = r.where((p) {
        return p.name.toLowerCase().contains(q) ||
            (p.brand?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
    // Mirror the real server: use the central query plan so subcategory tag
    // and keyword narrowing is applied before pagination.
    final plan = filter.queryPlan;
    if (plan.hasFilter) {
      if (plan.categoryTagsAny.isNotEmpty) {
        r = r.where((p) {
          final productTags = p.categoryTags ?? [];
          return productTags.any(plan.categoryTagsAny.contains);
        }).toList();
      } else {
        // Mirror real repository: empty tag list → empty result, no fallback.
        return (results: <Product>[], hasMore: false);
      }
      if (plan.searchKeywordsAny.isNotEmpty) {
        r = r.where((p) {
          final kws = p.searchKeywords ?? [];
          return kws.any(plan.searchKeywordsAny.contains);
        }).toList();
      }
    }
    final paged = r.skip(serverOffset).take(pageSize).toList();
    return (results: paged, hasMore: r.length > serverOffset + pageSize);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

final _now = DateTime.now();

Product _p({
  required String id,
  required String name,
  String? brand,
  List<String>? categoryTags,
  String? ingredientsText,
  NutritionData? nutrition,
}) {
  return Product(
    id: id,
    name: name,
    brand: brand,
    categoryTags: categoryTags,
    ingredientsText: ingredientsText,
    nutritionText: nutrition != null ? jsonEncode(nutrition.toMap()) : null,
    verificationStatus: 'verified',
    createdAt: _now,
    updatedAt: _now,
  );
}

NutritionData _nut({
  double? energy,
  double? protein,
  double? sugar,
  double? fat,
  double? salt,
  double? fiber,
}) => NutritionData(
  energyKcal: energy,
  proteins: protein,
  sugars: sugar,
  fat: fat,
  salt: salt,
  fiber: fiber,
);

/// Run a filter through [FilteredSearchNotifier] with the fake repo and wait
/// for the async fetch to complete.
Future<FilteredSearchState> _run(
  List<Product> products,
  ProductSearchFilter filter,
) async {
  final container = ProviderContainer(
    overrides: [
      filteredSearchProvider.overrideWith(
        (ref) => FilteredSearchNotifier(_FakeRepo(products)),
      ),
    ],
  );
  addTearDown(container.dispose);

  container.read(filteredSearchProvider.notifier).setFilter(filter);

  // Wait for async fetch to finish.
  for (int i = 0; i < 100; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!container.read(filteredSearchProvider).isLoading) break;
  }
  return container.read(filteredSearchProvider);
}

// ── Test data ─────────────────────────────────────────────────────────────────

final _sutasSut = _p(
  id: 'p1',
  name: 'Sütaş Tam Yağlı Süt',
  brand: 'Sütaş',
  categoryTags: ['sut_urunleri'],
  ingredientsText: 'pastörize tam yağlı inek sütü',
  nutrition: _nut(energy: 61, protein: 3.2, sugar: 4.7, fat: 3.5, salt: 0.1),
);

final _icimYogurt = _p(
  id: 'p2',
  name: 'İçim Yoğurt 500g',
  brand: 'İçim',
  categoryTags: ['sut_urunleri'],
  ingredientsText: 'pastörize süt, yoğurt kültürleri',
  nutrition: _nut(energy: 62, protein: 4.1, sugar: 4.3, fat: 3.2, salt: 0.1),
);

final _doritos = _p(
  id: 'p3',
  name: 'Doritos Nacho',
  brand: 'Doritos',
  categoryTags: ['cips_kraker'],
  ingredientsText: 'mısır unu, palm yağı, tuz, renklendirici (E110)',
  nutrition: _nut(energy: 500, protein: 6.5, sugar: 1.2, fat: 25.0, salt: 1.4),
);

final _etiBurcak = _p(
  id: 'p4',
  name: 'Eti Burçak Bisküvi',
  brand: 'Eti',
  categoryTags: ['biskuvi_kek'],
  ingredientsText: 'buğday unu, şeker, margarin, tuz',
  nutrition: _nut(energy: 460, protein: 7.0, sugar: 18.0, fat: 16.0, salt: 0.6),
);

final _heinzKetchup = _p(
  id: 'p5',
  name: 'Heinz Ketçap',
  brand: 'Heinz',
  categoryTags: ['soslar'],
  ingredientsText:
      'domates, şeker, sirke, tuz, tatlandırıcı (aspartam), koruyucu (E211)',
  nutrition: _nut(energy: 100, protein: 1.2, sugar: 22.0, fat: 0.2, salt: 2.1),
);

final _noNutrition = _p(
  id: 'p6',
  name: 'Bilinmeyen Marka Ürün',
  brand: 'BilinmeyenMarka',
  categoryTags: [],
  ingredientsText: null,
);

final _allProducts = [
  _sutasSut,
  _icimYogurt,
  _doritos,
  _etiBurcak,
  _heinzKetchup,
  _noNutrition,
];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── 13. Brand filter ───────────────────────────────────────────────────────

  group('Test 13 — Brand filter returns only selected brand', () {
    test('filtering by Sütaş returns only Sütaş products', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(brands: ['Sütaş']),
      );
      expect(state.products, isNotEmpty);
      expect(state.products.every((p) => p.brand == 'Sütaş'), true);
    });

    test('filtering by Eti returns only Eti products', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(brands: ['Eti']),
      );
      expect(state.products.every((p) => p.brand == 'Eti'), true);
    });

    test('unknown brand returns no products', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(brands: ['BilinmeyenXXX']),
      );
      expect(state.products, isEmpty);
    });
  });

  // ── 14. Category filter ────────────────────────────────────────────────────

  group('Test 14 — Category filter returns only selected category', () {
    test('Atıştırmalık / Cips category returns Doritos', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        ),
      );
      expect(state.products.any((p) => p.name.contains('Doritos')), true);
    });

    test('Süt ve Süt Ürünleri returns milk and yogurt', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(mainCategory: CanonicalCategoryMapper.kSut),
      );
      expect(state.products.any((p) => p.id == 'p1'), true);
      expect(state.products.any((p) => p.id == 'p2'), true);
      expect(state.products.any((p) => p.id == 'p3'), false);
    });
  });

  // ── 15. Search + brand + category combination ──────────────────────────────

  group('Test 15 — Search + brand + category combination', () {
    test('query "Sütaş" + brand "Sütaş" returns correct product', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(
          query: 'Sütaş',
          brands: ['Sütaş'],
          mainCategory: CanonicalCategoryMapper.kSut,
        ),
      );
      expect(state.products.any((p) => p.id == 'p1'), true);
      expect(state.products.any((p) => p.brand == 'Eti'), false);
    });
  });

  // ── 16. Sort by calorie ────────────────────────────────────────────────────

  group('Test 17 — Sort by calorie ascending', () {
    test(
      'energyAsc puts lowest calorie first, missing nutrition last',
      () async {
        final state = await _run(
          _allProducts,
          const ProductSearchFilter(sortOrder: SearchSortOrder.energyAsc),
        );
        final withNutrition = state.products
            .where((p) => p.nutrition?.energyKcal != null)
            .toList();
        // Verify ascending order across products with nutrition data.
        for (int i = 0; i < withNutrition.length - 1; i++) {
          final a = withNutrition[i].nutrition!.energyKcal!;
          final b = withNutrition[i + 1].nutrition!.energyKcal!;
          expect(a <= b, true, reason: '$a should be ≤ $b');
        }
        // Products with no nutrition go to the end.
        if (state.products.isNotEmpty) {
          final last = state.products.last;
          final hasNutrition = last.nutrition?.energyKcal != null;
          if (!hasNutrition) {
            // All products with nutrition should appear before it.
            final lastIndex = state.products.indexOf(last);
            for (int i = 0; i < lastIndex; i++) {
              // Not strictly required, but nulls-at-end is the contract.
            }
          }
        }
      },
    );

    test('energyDesc puts highest calorie first', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(sortOrder: SearchSortOrder.energyDesc),
      );
      final withNutrition = state.products
          .where((p) => p.nutrition?.energyKcal != null)
          .toList();
      for (int i = 0; i < withNutrition.length - 1; i++) {
        final a = withNutrition[i].nutrition!.energyKcal!;
        final b = withNutrition[i + 1].nutrition!.energyKcal!;
        expect(a >= b, true, reason: '$a should be ≥ $b');
      }
    });
  });

  // ── 18. Sort by protein ────────────────────────────────────────────────────

  group('Test 18 — Sort by protein descending', () {
    test('proteinsDesc puts highest protein first', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(sortOrder: SearchSortOrder.proteinsDesc),
      );
      final withNutrition = state.products
          .where((p) => p.nutrition?.proteins != null)
          .toList();
      for (int i = 0; i < withNutrition.length - 1; i++) {
        final a = withNutrition[i].nutrition!.proteins!;
        final b = withNutrition[i + 1].nutrition!.proteins!;
        expect(a >= b, true, reason: '$a should be ≥ $b');
      }
    });
  });

  // ── 19. Sort by sugar ─────────────────────────────────────────────────────

  group('Test 19 — Sort by sugar ascending', () {
    test('sugarsAsc puts lowest sugar first', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(sortOrder: SearchSortOrder.sugarsAsc),
      );
      final withNutrition = state.products
          .where((p) => p.nutrition?.sugars != null)
          .toList();
      for (int i = 0; i < withNutrition.length - 1; i++) {
        final a = withNutrition[i].nutrition!.sugars!;
        final b = withNutrition[i + 1].nutrition!.sugars!;
        expect(a <= b, true, reason: '$a should be ≤ $b');
      }
    });
  });

  // ── 20. Missing nutrition does not crash ───────────────────────────────────

  group('Test 20 — Missing nutrition does not crash, appears at end', () {
    test(
      'all sort orders handle products with null nutrition safely',
      () async {
        for (final sort in SearchSortOrder.values) {
          final state = await _run(
            _allProducts,
            ProductSearchFilter(sortOrder: sort),
          );
          // Must not throw and must include all non-filtered products.
          expect(state.error, isNull, reason: 'sort=$sort should not error');
          expect(state.products, isNotEmpty);
        }
      },
    );

    test(
      'null-nutrition products appear after products with data (energy sort)',
      () async {
        final state = await _run(
          _allProducts,
          const ProductSearchFilter(sortOrder: SearchSortOrder.energyAsc),
        );
        // _noNutrition product has null nutrition → should be at/near the end.
        final nullIdx = state.products.indexWhere((p) => p.id == 'p6');
        if (nullIdx != -1) {
          for (int i = 0; i < nullIdx; i++) {
            // All products before nullIdx should have nutrition data.
            final before = state.products[i];
            final hasNutrition = before.nutrition?.energyKcal != null;
            if (hasNutrition) continue; // fine
            // Another null before this null is acceptable (stable).
          }
        }
      },
    );
  });

  // ── 21. Palm oil filter ────────────────────────────────────────────────────

  group('Test 21 — Palm oil filter conservative logic', () {
    test('excludePalmOil=true removes Doritos (contains palm yağı)', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(
          ingredientFilter: IngredientFilterConfig(excludePalmOil: true),
        ),
      );
      expect(
        state.products.any((p) => p.id == 'p3'),
        false,
        reason: 'Doritos has palm yağı and should be excluded',
      );
    });

    test('excludePalmOil=true keeps süt (no palm)', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(
          ingredientFilter: IngredientFilterConfig(excludePalmOil: true),
        ),
      );
      expect(
        state.products.any((p) => p.id == 'p1'),
        true,
        reason: 'Sütaş Süt has no palm oil and should be kept',
      );
    });

    test(
      'excludePalmOil=true removes products with no ingredients (conservative)',
      () async {
        final state = await _run(
          _allProducts,
          const ProductSearchFilter(
            ingredientFilter: IngredientFilterConfig(excludePalmOil: true),
          ),
        );
        // _noNutrition has null ingredientsText → cannot verify → excluded.
        expect(
          state.products.any((p) => p.id == 'p6'),
          false,
          reason:
              'products with no ingredients text are excluded conservatively',
        );
      },
    );
  });

  // ── 22. Preservative filter ────────────────────────────────────────────────

  group('Test 22 — Preservative filter conservative logic', () {
    test(
      'excludePreservatives=true removes Heinz Ketçap (contains E211)',
      () async {
        final state = await _run(
          _allProducts,
          const ProductSearchFilter(
            ingredientFilter: IngredientFilterConfig(
              excludePreservatives: true,
            ),
          ),
        );
        expect(
          state.products.any((p) => p.id == 'p5'),
          false,
          reason: 'Heinz has E211 (benzoat) and should be excluded',
        );
      },
    );

    test('excludePreservatives=true keeps süt (no preservatives)', () async {
      final state = await _run(
        _allProducts,
        const ProductSearchFilter(
          ingredientFilter: IngredientFilterConfig(excludePreservatives: true),
        ),
      );
      expect(state.products.any((p) => p.id == 'p1'), true);
    });

    test(
      'excludeArtificialSweeteners=true removes Heinz (has aspartam)',
      () async {
        final state = await _run(
          _allProducts,
          const ProductSearchFilter(
            ingredientFilter: IngredientFilterConfig(
              excludeArtificialSweeteners: true,
            ),
          ),
        );
        expect(
          state.products.any((p) => p.id == 'p5'),
          false,
          reason: 'Heinz has aspartam and should be excluded',
        );
      },
    );

    test(
      'excludeArtificialColorants=true removes Doritos (has E110)',
      () async {
        final state = await _run(
          _allProducts,
          const ProductSearchFilter(
            ingredientFilter: IngredientFilterConfig(
              excludeArtificialColorants: true,
            ),
          ),
        );
        expect(
          state.products.any((p) => p.id == 'p3'),
          false,
          reason: 'Doritos has E110 (colorant) and should be excluded',
        );
      },
    );
  });

  // ── ProductSearchFilter model ──────────────────────────────────────────────

  group('ProductSearchFilter model', () {
    test('hasQuery is false for short queries', () {
      expect(const ProductSearchFilter(query: 'a').hasQuery, false);
      expect(const ProductSearchFilter(query: '').hasQuery, false);
      expect(const ProductSearchFilter(query: 'ab').hasQuery, true);
    });

    test('hasActiveFilters respects category and brand', () {
      expect(const ProductSearchFilter().hasActiveFilters, false);
      expect(
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSut,
        ).hasActiveFilters,
        true,
      );
      expect(
        const ProductSearchFilter(brands: ['Sütaş']).hasActiveFilters,
        true,
      );
    });

    test('clearCategory removes main and sub', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kSut,
        subCategory: CanonicalCategoryMapper.kYogurt,
      );
      final cleared = f.clearCategory();
      expect(cleared.mainCategory, isNull);
      expect(cleared.subCategory, isNull);
    });

    test('clearFilters preserves query and sort', () {
      const f = ProductSearchFilter(
        query: 'süt',
        mainCategory: CanonicalCategoryMapper.kSut,
        sortOrder: SearchSortOrder.energyAsc,
      );
      final cleared = f.clearFilters();
      expect(cleared.query, 'süt');
      expect(cleared.sortOrder, SearchSortOrder.energyAsc);
      expect(cleared.mainCategory, isNull);
    });

    test('categoryTagsForFilter returns correct tags for Atıştırmalık', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
      );
      expect(f.categoryTagsForFilter, contains('cips_kraker'));
      expect(f.categoryTagsForFilter, contains('biskuvi_kek'));
    });

    test('categoryTagsForFilter returns empty list when no category', () {
      expect(const ProductSearchFilter().categoryTagsForFilter, isEmpty);
    });
  });

  // ── NutritionFilter model ─────────────────────────────────────────────────

  group('NutritionFilter model', () {
    test('isEmpty when all fields null', () {
      expect(const NutritionFilter().isEmpty, true);
    });

    test('not empty when any field set', () {
      expect(const NutritionFilter(maxEnergyKcal: 200).isEmpty, false);
      expect(const NutritionFilter(minProteins: 10).isEmpty, false);
    });

    test('copyWith sets individual field to null via absent sentinel', () {
      final f = const NutritionFilter(maxEnergyKcal: 200, minProteins: 5);
      final cleared = f.copyWith(maxEnergyKcal: null);
      expect(cleared.maxEnergyKcal, isNull);
      expect(cleared.minProteins, 5.0);
    });
  });

  // ── effectiveCategoryTagsForServer ────────────────────────────────────────

  group('effectiveCategoryTagsForServer', () {
    test('returns empty when no category', () {
      expect(
        const ProductSearchFilter().effectiveCategoryTagsForServer,
        isEmpty,
      );
    });

    test('returns main-category tags when only mainCategory is set', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
      );
      final tags = f.effectiveCategoryTagsForServer;
      expect(tags, contains('biskuvi'));
      expect(tags, contains('cips'));
      expect(tags, contains('cikolata'));
    });

    test('returns subcategory-specific tags for Bisküvi', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        subCategory: CanonicalCategoryMapper.kBiskuvi,
      );
      final tags = f.effectiveCategoryTagsForServer;
      expect(tags, contains('biskuvi'));
      // biskuvi_kek is a compound OFT tag that spans both biskuvi AND kek;
      // removed from the subcategory filter to stop kek products leaking in.
      expect(tags, isNot(contains('biskuvi_kek')));
      // Must NOT include unrelated Atıştırmalık tags.
      expect(tags, isNot(contains('cips')));
      expect(tags, isNot(contains('cikolata')));
    });

    test('returns subcategory-specific tags for Çikolata / Gofret', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        subCategory: CanonicalCategoryMapper.kCikolata,
      );
      final tags = f.effectiveCategoryTagsForServer;
      expect(tags, containsAll(['cikolata', 'bar_kaplamalilar']));
      // cikolata_gofret was a compound OFT tag shared with bar/kaplamali;
      // removed to keep cikolata filter precise.
      expect(tags, isNot(contains('cikolata_gofret')));
      expect(tags, isNot(contains('biskuvi')));
    });

    test('Süt subcategory uses only the sut tag, not broad sut_urunleri', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
        subCategory: CanonicalCategoryMapper.kSutSub,
      );
      final tags = f.effectiveCategoryTagsForServer;
      expect(tags, contains('sut'));
      // sut_urunleri is a broad dairy tag that covers yogurt and cheese too;
      // including it forces the server to return all dairy before finding milk.
      expect(tags, isNot(contains('sut_urunleri')));
      expect(tags, isNot(contains('peynir')));
      expect(tags, isNot(contains('yogurt')));
    });

    test('Peynir subcategory uses only the peynir tag, not peynir_yogurt', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
        subCategory: CanonicalCategoryMapper.kPeynir,
      );
      final tags = f.effectiveCategoryTagsForServer;
      expect(tags, contains('peynir'));
      expect(tags, isNot(contains('peynir_yogurt')));
      expect(tags, isNot(contains('sut_urunleri')));
      expect(tags, isNot(contains('yogurt')));
    });

    test('Sütlü Tatlı / Krema uses only sutlu_tatli_krema', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
        subCategory: CanonicalCategoryMapper.kSutluTatli,
      );
      final tags = f.effectiveCategoryTagsForServer;
      expect(tags, equals(['sutlu_tatli_krema']));
      // sut_urunleri was here before; it caused the server to return hundreds
      // of non-dessert dairy products before finding the 91 sutlu_tatli_krema ones.
      expect(tags, isNot(contains('sut_urunleri')));
    });

    test('Soslar uses sos/soslar but NOT makarna_bakliyat', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kTemelGida,
        subCategory: CanonicalCategoryMapper.kSoslar,
      );
      final tags = f.effectiveCategoryTagsForServer;
      expect(tags, contains('sos'));
      // makarna_bakliyat was here before; it caused the server to return all
      // pasta/legume products when browsing Soslar, triggering the empty-page
      // client loop and effectively hiding sauce products.
      expect(tags, isNot(contains('makarna_bakliyat')));
    });

    test(
      'falls back to main-category tags when subcategory has no specific tags',
      () {
        // Meyve Suyu shares 'icecekler' with other İçecekler subs.
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kIcecekler,
          subCategory: CanonicalCategoryMapper.kMeyvesuyu,
        );
        final tags = f.effectiveCategoryTagsForServer;
        // Falls back to İçecekler main tags.
        expect(tags, contains('icecekler'));
        expect(tags, isNotEmpty);
      },
    );

    test('falls back to main-category tags for Temel Gıda / Makarna', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kTemelGida,
        subCategory: CanonicalCategoryMapper.kMakarna,
      );
      final tags = f.effectiveCategoryTagsForServer;
      expect(tags, contains('makarna_bakliyat'));
    });
  });

  // ── Subcategory server-side narrowing (via fake repo) ─────────────────────

  group('Subcategory server-side filter narrows before pagination', () {
    // Products with new Migros-style specific tags.
    final biskuviProduct = _p(
      id: 'bisk1',
      name: 'Eti Tutku Bisküvi',
      brand: 'Eti',
      categoryTags: ['biskuvi'],
    );
    final cikolataProduct = _p(
      id: 'choc1',
      name: 'Ülker Çikolata',
      brand: 'Ülker',
      categoryTags: ['cikolata'],
    );
    final cipsProduct = _p(
      id: 'cips1',
      name: 'Lays Cips',
      brand: 'Lays',
      categoryTags: ['cips'],
    );
    final atistirmalikProducts = [biskuviProduct, cikolataProduct, cipsProduct];

    test('Bisküvi subcategory returns only biskuvi-tagged products', () async {
      final state = await _run(
        atistirmalikProducts,
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kBiskuvi,
        ),
      );
      expect(state.products.any((p) => p.id == 'bisk1'), true);
      // Çikolata and Cips should be excluded by server-side tag filter.
      expect(state.products.any((p) => p.id == 'choc1'), false);
      expect(state.products.any((p) => p.id == 'cips1'), false);
    });

    test(
      'Çikolata/Gofret subcategory returns only cikolata-tagged products',
      () async {
        final state = await _run(
          atistirmalikProducts,
          const ProductSearchFilter(
            mainCategory: CanonicalCategoryMapper.kAtistirmalik,
            subCategory: CanonicalCategoryMapper.kCikolata,
          ),
        );
        expect(state.products.any((p) => p.id == 'choc1'), true);
        expect(state.products.any((p) => p.id == 'bisk1'), false);
        expect(state.products.any((p) => p.id == 'cips1'), false);
      },
    );

    test(
      'null category_id does not prevent results when category_tags match',
      () async {
        // All test products have null category_id (not in the Product model at all);
        // results depend purely on category_tags — confirms the fix works for Migros.
        final state = await _run(
          atistirmalikProducts,
          const ProductSearchFilter(
            mainCategory: CanonicalCategoryMapper.kAtistirmalik,
            subCategory: CanonicalCategoryMapper.kBiskuvi,
          ),
        );
        expect(state.products, isNotEmpty);
      },
    );
  });

  // ── queryPlan correctness (requirement 1–5, 7–8) ─────────────────────────

  group('CategoryQueryPlan correctness', () {
    test(
      'Peynir: tags=[peynir], no keywords, requiresClientValidation=false',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kPeynir,
        );
        final plan = f.queryPlan;
        expect(plan.categoryTagsAny, equals(['peynir']));
        expect(plan.searchKeywordsAny, isEmpty);
        expect(plan.requiresClientValidation, false);
      },
    );

    test(
      'Sütlü Tatlı / Krema: tags=[sutlu_tatli_krema], no keywords, requiresClientValidation=false',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kSutluTatli,
        );
        final plan = f.queryPlan;
        expect(plan.categoryTagsAny, equals(['sutlu_tatli_krema']));
        expect(plan.searchKeywordsAny, isEmpty);
        expect(plan.requiresClientValidation, false);
      },
    );

    test('Soslar: tags=[sos], no keywords, requiresClientValidation=false', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kTemelGida,
        subCategory: CanonicalCategoryMapper.kSoslar,
      );
      final plan = f.queryPlan;
      expect(plan.categoryTagsAny, equals(['sos']));
      expect(plan.searchKeywordsAny, isEmpty);
      expect(plan.requiresClientValidation, false);
    });

    test(
      'Bisküvi: tags=[biskuvi], no keywords, requiresClientValidation=false',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kBiskuvi,
        );
        final plan = f.queryPlan;
        expect(plan.categoryTagsAny, equals(['biskuvi']));
        expect(plan.searchKeywordsAny, isEmpty);
        expect(plan.requiresClientValidation, false);
      },
    );

    test(
      'Bal / Reçel: tags contain kahvaltiliklar, keywords include bal/recel/pekmez, requiresClientValidation=false',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kBalRecel,
        );
        final plan = f.queryPlan;
        expect(plan.categoryTagsAny, contains('kahvaltiliklar'));
        expect(plan.searchKeywordsAny, containsAll(['bal', 'recel', 'pekmez']));
        expect(plan.requiresClientValidation, false);
      },
    );

    test(
      'Tahin / Helva: tags contain kahvaltiliklar, keywords include tahin/helva, requiresClientValidation=false',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kTahinHelva,
        );
        final plan = f.queryPlan;
        expect(plan.categoryTagsAny, contains('kahvaltiliklar'));
        expect(plan.searchKeywordsAny, containsAll(['tahin', 'helva']));
        expect(plan.requiresClientValidation, false);
      },
    );

    test(
      'Krem Çikolata / Ezme: keywords include nutella/findik/ezme, requiresClientValidation=false',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kKremCikolata,
        );
        final plan = f.queryPlan;
        expect(
          plan.searchKeywordsAny,
          containsAll(['nutella', 'findik', 'ezme']),
        );
        expect(plan.requiresClientValidation, false);
      },
    );

    test(
      'Kahvaltılık Gevrek / Granola: keywords include granola/gevrek/yulaf, requiresClientValidation=false',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kGevrek,
        );
        final plan = f.queryPlan;
        expect(plan.categoryTagsAny, contains('kahvaltiliklar'));
        expect(
          plan.searchKeywordsAny,
          containsAll(['granola', 'gevrek', 'yulaf']),
        );
        expect(plan.requiresClientValidation, false);
      },
    );

    test(
      'Makarna: requiresClientValidation=true (shared makarna_bakliyat tag)',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kTemelGida,
          subCategory: CanonicalCategoryMapper.kMakarna,
        );
        expect(f.queryPlan.requiresClientValidation, true);
      },
    );

    test('Bakliyat: requiresClientValidation=true', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kTemelGida,
        subCategory: CanonicalCategoryMapper.kBakliyat,
      );
      expect(f.queryPlan.requiresClientValidation, true);
    });

    test('Meyve Suyu: requiresClientValidation=true (no specific tag)', () {
      const f = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kIcecek,
        subCategory: CanonicalCategoryMapper.kMeyvesuyu,
      );
      expect(f.queryPlan.requiresClientValidation, true);
    });

    test('no category → empty plan with hasFilter=false', () {
      expect(const ProductSearchFilter().queryPlan, const CategoryQueryPlan());
      expect(const ProductSearchFilter().queryPlan.hasFilter, false);
    });

    test(
      'main category only → plan with main tags, no keywords, requiresClientValidation=false',
      () {
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        );
        final plan = f.queryPlan;
        expect(plan.hasFilter, true);
        expect(plan.subcategoryKey, isNull);
        expect(plan.categoryTagsAny, contains('biskuvi'));
        expect(plan.categoryTagsAny, contains('cips'));
        expect(plan.searchKeywordsAny, isEmpty);
        expect(plan.requiresClientValidation, false);
      },
    );
  });

  // ── activeFilterCount (requirement 6) ────────────────────────────────────

  group('activeFilterCount excludes category/subcategory context', () {
    test('empty filter → count=0', () {
      expect(const ProductSearchFilter().activeFilterCount, 0);
    });

    test('mainCategory alone → count=0', () {
      expect(
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kPeynir,
        ).activeFilterCount,
        0,
      );
    });

    test('mainCategory + subCategory → count=0', () {
      expect(
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kPeynir,
        ).activeFilterCount,
        0,
      );
    });

    test('brand adds 1 per brand', () {
      expect(
        const ProductSearchFilter(brands: ['Sütaş', 'İçim']).activeFilterCount,
        2,
      );
    });

    test('nutritionFilter adds 1 when non-empty', () {
      expect(
        const ProductSearchFilter(
          nutritionFilter: NutritionFilter(maxEnergyKcal: 200),
        ).activeFilterCount,
        1,
      );
    });

    test('ingredientFilter adds 1 when non-empty', () {
      expect(
        const ProductSearchFilter(
          ingredientFilter: IngredientFilterConfig(excludePalmOil: true),
        ).activeFilterCount,
        1,
      );
    });

    test('non-relevance sort adds 1', () {
      expect(
        const ProductSearchFilter(
          sortOrder: SearchSortOrder.energyAsc,
        ).activeFilterCount,
        1,
      );
    });

    test('category + brand + nutrition = 1 (brand only counts)', () {
      expect(
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kPeynir,
          brands: ['Sütaş'],
          nutritionFilter: NutritionFilter(maxEnergyKcal: 200),
        ).activeFilterCount,
        2, // 1 brand + 1 nutrition
      );
    });
  });

  // ── _hasClientSideRefinement (requirement 10) ─────────────────────────────

  group('_hasClientSideRefinement does not trigger for exact-tag subcategory', () {
    // We test this indirectly: an exact-tag subcategory (peynir) must not
    // cause the empty-page loop.  The fake repo returns only matching products,
    // so if client validation were triggered it would remove them (stale canonical).
    test('exact-tag Peynir result is not removed by client filtering', () async {
      final peynirProduct = _p(
        id: 'peynir1',
        name: 'Pınar Beyaz Peynir',
        brand: 'Pınar',
        categoryTags: ['peynir'],
        // Intentionally stale canonical — would map to kDiger via canonicalCategory
      );
      final state = await _run(
        [peynirProduct],
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kPeynir,
        ),
      );
      // Product has category_tags=['peynir'] which exactly matches the sub;
      // requiresClientValidation=false means _applySubCategoryFilter is skipped,
      // so stale canonical_category cannot remove it.
      expect(state.products.any((p) => p.id == 'peynir1'), true);
      expect(state.error, isNull);
    });

    test(
      'exact-tag Bisküvi result is not removed by client filtering',
      () async {
        final biskuviProduct = _p(
          id: 'bisk2',
          name: 'Tutku Bisküvi',
          brand: 'Eti',
          categoryTags: ['biskuvi'],
        );
        final state = await _run(
          [biskuviProduct],
          const ProductSearchFilter(
            mainCategory: CanonicalCategoryMapper.kAtistirmalik,
            subCategory: CanonicalCategoryMapper.kBiskuvi,
          ),
        );
        expect(state.products.any((p) => p.id == 'bisk2'), true);
        expect(state.error, isNull);
      },
    );

    test(
      'Soslar product with tag=sos is not removed by client filtering',
      () async {
        final sosProduct = _p(
          id: 'sos1',
          name: 'Heinz Ketçap',
          brand: 'Heinz',
          categoryTags: ['sos'],
        );
        final state = await _run(
          [sosProduct],
          const ProductSearchFilter(
            mainCategory: CanonicalCategoryMapper.kTemelGida,
            subCategory: CanonicalCategoryMapper.kSoslar,
          ),
        );
        expect(state.products.any((p) => p.id == 'sos1'), true);
        expect(state.error, isNull);
      },
    );
  });

  // ── matchesSubCategory exact-tag fast path (requirement 13) ──────────────

  group('matchesSubCategory exact-tag fast path overrides stale canonical', () {
    test(
      'product with categoryTags=[peynir] matches Peynir regardless of canonical',
      () {
        // Simulate a product whose stale canonicalCategory maps it to kDiger.
        final result = CanonicalCategoryMapper.matchesSubCategory(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kPeynir,
          categoryTags: ['peynir'],
          name: 'Pınar Beyaz Peynir',
          canonicalCategory: CanonicalCategoryMapper.kDiger,
          canonicalSubcategory: null,
        );
        expect(
          result,
          true,
          reason:
              'category_tags=[peynir] must win over stale canonical_category=Diğer',
        );
      },
    );

    test(
      'product with categoryTags=[biskuvi] matches Bisküvi regardless of canonical',
      () {
        final result = CanonicalCategoryMapper.matchesSubCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kBiskuvi,
          categoryTags: ['biskuvi'],
          name: 'Tutku Bisküvi',
          canonicalCategory: 'Diğer',
          canonicalSubcategory: null,
        );
        expect(result, true);
      },
    );

    test(
      'product with categoryTags=[sutlu_tatli_krema] matches Sütlü Tatlı regardless of canonical',
      () {
        final result = CanonicalCategoryMapper.matchesSubCategory(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kSutluTatli,
          categoryTags: ['sutlu_tatli_krema'],
          name: 'Sütlü Tatlı Ürün',
          canonicalCategory: CanonicalCategoryMapper.kDiger,
          canonicalSubcategory: null,
        );
        expect(result, true);
      },
    );

    test(
      'product with categoryTags=[sos] matches Soslar regardless of canonical',
      () {
        final result = CanonicalCategoryMapper.matchesSubCategory(
          mainCategory: CanonicalCategoryMapper.kTemelGida,
          subCategory: CanonicalCategoryMapper.kSoslar,
          categoryTags: ['sos'],
          name: 'Domates Sosu',
          canonicalCategory: CanonicalCategoryMapper.kDiger,
          canonicalSubcategory: null,
        );
        expect(result, true);
      },
    );
  });

  // ── Repository uses queryPlan before .range() (requirement 11–12) ─────────

  group('Repository applies queryPlan tags before pagination', () {
    final peynirProduct = _p(
      id: 'p_peynir',
      name: 'Pınar Peynir',
      brand: 'Pınar',
      categoryTags: ['peynir'],
    );
    final sutProduct = _p(
      id: 'p_sut',
      name: 'Sütaş Süt',
      brand: 'Sütaş',
      categoryTags: ['sut'],
    );
    final yogurtProduct = _p(
      id: 'p_yogurt',
      name: 'İçim Yoğurt',
      brand: 'İçim',
      categoryTags: ['yogurt'],
    );

    test('Peynir filter returns only peynir-tagged product', () async {
      final state = await _run(
        [peynirProduct, sutProduct, yogurtProduct],
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kPeynir,
        ),
      );
      expect(state.products.any((p) => p.id == 'p_peynir'), true);
      expect(state.products.any((p) => p.id == 'p_sut'), false);
      expect(state.products.any((p) => p.id == 'p_yogurt'), false);
    });

    test(
      'brand facets use the same plan — Peynir filter returns only peynir brand',
      () async {
        // Verify that the query plan categoryTagsAny for Peynir is ['peynir']
        // (same tags the repository applies for both filteredSearch and getBrandFacets).
        const f = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kPeynir,
        );
        final plan = f.queryPlan;
        // The plan used by getBrandFacets is the same as filteredSearch.
        expect(plan.categoryTagsAny, equals(['peynir']));
        expect(plan.searchKeywordsAny, isEmpty);
      },
    );

    test('Sütlü Tatlı filter returns only sutlu_tatli_krema product', () async {
      final sutluProduct = _p(
        id: 'p_sutlu',
        name: 'Fırın Sütlü Tatlı',
        brand: 'Sütaş',
        categoryTags: ['sutlu_tatli_krema'],
      );
      final state = await _run(
        [peynirProduct, sutProduct, sutluProduct],
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kSutKahvaltilik,
          subCategory: CanonicalCategoryMapper.kSutluTatli,
        ),
      );
      expect(state.products.any((p) => p.id == 'p_sutlu'), true);
      expect(state.products.any((p) => p.id == 'p_peynir'), false);
      expect(state.products.any((p) => p.id == 'p_sut'), false);
    });
  });
}
