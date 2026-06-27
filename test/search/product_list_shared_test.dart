/// Tests for the shared ProductListView / filtering system (Part 10, items 1–5
/// and new fiberDesc / excludeAddedSugar filters).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';

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
    var results = _products.toList();

    results = results
        .where(
          (p) =>
              p.name != 'Bilinmeyen Ürün' &&
              p.name != 'Unknown Product' &&
              !(p.source?.toLowerCase().contains('openfoodfacts') ?? false),
        )
        .toList();

    if (filter.hasQuery) {
      final q = filter.query.trim().toLowerCase();
      results = results
          .where(
            (p) =>
                p.name.toLowerCase().contains(q) ||
                (p.brand?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    if (filter.brands.isNotEmpty) {
      results = results.where((p) => filter.brands.contains(p.brand)).toList();
    }

    final hasMore = results.length > pageSize;
    return (results: results.take(pageSize).toList(), hasMore: hasMore);
  }
}

// ── Helper: run notifier with fake repo, wait for load ───────────────────────

Future<FilteredSearchState> _run(
  List<Product> products,
  ProductSearchFilter filter,
) async {
  final container = ProviderContainer(
    overrides: [
      filteredSearchProvider.overrideWith(
        (ref) =>
            FilteredSearchNotifier(_FakeRepo(products), initialFilter: filter),
      ),
    ],
  );
  addTearDown(container.dispose);

  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (!container.read(filteredSearchProvider).isLoading) break;
  }
  return container.read(filteredSearchProvider);
}

// ── Product factory ───────────────────────────────────────────────────────────

Product _p({
  required String name,
  String? brand,
  String? source,
  String? ingredientsText,
  String? nutritionText,
  List<String>? categoryTags,
}) {
  final now = DateTime.now();
  return Product(
    id: name,
    name: name,
    brand: brand,
    source: source,
    ingredientsText: ingredientsText,
    nutritionText: nutritionText,
    categoryTags: categoryTags,
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
  );
}

// ── Category initial filter helper (mirrors the private page method) ──────────

ProductSearchFilter _buildCategoryFilter(ProductCategory cat) {
  final canonical = CanonicalCategoryMapper.map(
    categoryTags: cat.databaseTags.isNotEmpty ? cat.databaseTags : null,
    name: cat.title,
  );
  // All ProductCategories.all entries are main categories in the new 12-category
  // taxonomy. The page always creates a mainCategory-only filter (no pre-selected
  // sub) for these entries — sub is chosen via the chip bar by the user.
  return ProductSearchFilter(mainCategory: canonical.main);
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Part 10, items 1–5: shared filter system contracts ──────────────────────

  group('Shared filter system — initial state', () {
    test(
      '1. Main search uses empty initial filter (no category pre-selected)',
      () {
        final notifier = FilteredSearchNotifier(_FakeRepo([]));
        expect(notifier.state.filter.mainCategory, isNull);
        expect(notifier.state.filter.hasActiveFilters, false);
        expect(notifier.state.isLoading, false);
      },
    );

    test('2. Category page pre-selects its canonical main + sub category', () {
      final filter = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        subCategory: CanonicalCategoryMapper.kCips,
      );
      final notifier = FilteredSearchNotifier(
        _FakeRepo([]),
        initialFilter: filter,
      );
      expect(
        notifier.state.filter.mainCategory,
        CanonicalCategoryMapper.kAtistirmalik,
      );
      expect(notifier.state.filter.subCategory, CanonicalCategoryMapper.kCips);
      expect(notifier.state.filter.hasActiveFilters, true);
      expect(notifier.state.isLoading, true); // auto-fetch triggered
    });

    test(
      '3. Category sub-category can be removed while keeping main',
      () async {
        final initial = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCips,
        );
        final container = ProviderContainer(
          overrides: [
            filteredSearchProvider.overrideWith(
              (ref) =>
                  FilteredSearchNotifier(_FakeRepo([]), initialFilter: initial),
            ),
          ],
        );
        addTearDown(container.dispose);

        container
            .read(filteredSearchProvider.notifier)
            .setFilter(initial.copyWith(subCategory: null));

        expect(
          container.read(filteredSearchProvider).filter.mainCategory,
          CanonicalCategoryMapper.kAtistirmalik,
        );
        expect(
          container.read(filteredSearchProvider).filter.subCategory,
          isNull,
        );
      },
    );

    test('4. Clearing category filter removes mainCategory', () async {
      final initial = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kSut,
      );
      final container = ProviderContainer(
        overrides: [
          filteredSearchProvider.overrideWith(
            (ref) =>
                FilteredSearchNotifier(_FakeRepo([]), initialFilter: initial),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(filteredSearchProvider.notifier)
          .setFilter(initial.clearCategory());

      expect(
        container.read(filteredSearchProvider).filter.mainCategory,
        isNull,
      );
      expect(
        container.read(filteredSearchProvider).filter.hasActiveFilters,
        false,
      );
    });

    test('5. Sort option is independent of category pre-selection', () {
      final initial = ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kSut,
        sortOrder: SearchSortOrder.proteinsDesc,
      );
      final notifier = FilteredSearchNotifier(
        _FakeRepo([]),
        initialFilter: initial,
      );
      expect(notifier.state.filter.sortOrder, SearchSortOrder.proteinsDesc);
      expect(notifier.state.filter.mainCategory, CanonicalCategoryMapper.kSut);
    });
  });

  // ── Category initial filter mapping ─────────────────────────────────────────

  // Category → initial filter mapping.
  //
  // These tests verify that each main ProductCategory in ProductCategories.all
  // resolves to the expected canonical main category via CanonicalCategoryMapper.
  // Sub-category is always null here because _buildCategoryFilter now mirrors
  // the page's _buildListContext: all entries are main categories, sub is chosen
  // by the user via the chip bar.
  group('Category → initial filter mapping', () {
    test('atistirmalik → kAtistirmalik (via cips tag)', () {
      final f = _buildCategoryFilter(
        ProductCategories.findById('atistirmalik')!,
      );
      expect(f.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
      expect(f.subCategory, isNull);
    });

    test('icecek → kIcecek (via gazli_icecek tag)', () {
      final f = _buildCategoryFilter(ProductCategories.findById('icecek')!);
      expect(f.mainCategory, CanonicalCategoryMapper.kIcecek);
      expect(f.subCategory, isNull);
    });

    test('sut-kahvaltilik → kSutKahvaltilik (merged dairy + breakfast)', () {
      final f = _buildCategoryFilter(
        ProductCategories.findById('sut-kahvaltilik')!,
      );
      expect(f.mainCategory, CanonicalCategoryMapper.kSutKahvaltilik);
      expect(f.subCategory, isNull);
    });

    test('temel-gida → kTemelGida (via sos tag)', () {
      final f = _buildCategoryFilter(ProductCategories.findById('temel-gida')!);
      expect(f.mainCategory, CanonicalCategoryMapper.kTemelGida);
      expect(f.subCategory, isNull);
    });

    test('et-tavuk-balik → kEtTavukBalik (via sucuk tag)', () {
      final f = _buildCategoryFilter(
        ProductCategories.findById('et-tavuk-balik')!,
      );
      expect(f.mainCategory, CanonicalCategoryMapper.kEtTavukBalik);
      expect(f.subCategory, isNull);
    });

    test('hazir-donuk → kHazirDonuk (via hazir_yemek tag)', () {
      final f = _buildCategoryFilter(
        ProductCategories.findById('hazir-donuk')!,
      );
      expect(f.mainCategory, CanonicalCategoryMapper.kHazirDonuk);
      expect(f.subCategory, isNull);
    });

    test('dondurma → kDondurma (via dondurma_tatli tag)', () {
      final f = _buildCategoryFilter(ProductCategories.findById('dondurma')!);
      expect(f.mainCategory, CanonicalCategoryMapper.kDondurma);
      expect(f.subCategory, isNull);
    });

    test('bebek-gida → kBebek (via bebek_cocuk tag)', () {
      final f = _buildCategoryFilter(ProductCategories.findById('bebek-gida')!);
      expect(f.mainCategory, CanonicalCategoryMapper.kBebek);
      expect(f.subCategory, isNull);
    });
  });

  // ── fiberDesc sort ───────────────────────────────────────────────────────────

  group('SearchSortOrder.fiberDesc', () {
    test('label is "Lif: Çoktan Aza"', () {
      expect(SearchSortOrder.fiberDesc.label, 'Lif: Çoktan Aza');
    });

    test('isNutritionSort is true for fiberDesc', () {
      const f = ProductSearchFilter(sortOrder: SearchSortOrder.fiberDesc);
      expect(f.isNutritionSort, true);
    });

    test('fiberDesc sorts high→low, nulls at end', () async {
      final highFiber = _p(name: 'Yulaf', nutritionText: '{"fiber": 8.0}');
      final lowFiber = _p(name: 'Bisküvi', nutritionText: '{"fiber": 1.5}');
      final noFiber = _p(name: 'Salam');

      // mainCategory triggers auto-fetch; fake repo ignores it (returns all).
      final state = await _run(
        [lowFiber, noFiber, highFiber],
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kTemelGida,
          sortOrder: SearchSortOrder.fiberDesc,
        ),
      );

      expect(state.products[0].name, 'Yulaf');
      expect(state.products[1].name, 'Bisküvi');
      expect(state.products[2].name, 'Salam');
    });
  });

  // ── excludeAddedSugar filter ──────────────────────────────────────────────

  group('IngredientFilterConfig.excludeAddedSugar', () {
    test('isEmpty is false when excludeAddedSugar=true', () {
      const f = IngredientFilterConfig(excludeAddedSugar: true);
      expect(f.isEmpty, false);
    });

    test('copyWith sets excludeAddedSugar', () {
      const f = IngredientFilterConfig();
      expect(f.copyWith(excludeAddedSugar: true).excludeAddedSugar, true);
    });

    test('excludes products with "şeker" in ingredients', () async {
      final hasSheker = _p(
        name: 'İçecek',
        ingredientsText: 'su, şeker, sitrik asit',
      );
      final hasGlikoz = _p(
        name: 'Çorba',
        ingredientsText: 'su, nişasta, glikoz şurubu, tuz',
      );
      final clean = _p(name: 'Yoğurt', ingredientsText: 'süt, yoğurt kültürü');

      final state = await _run(
        [hasSheker, hasGlikoz, clean],
        const ProductSearchFilter(
          ingredientFilter: IngredientFilterConfig(excludeAddedSugar: true),
        ),
      );

      expect(state.products.map((p) => p.name), contains('Yoğurt'));
      expect(state.products.map((p) => p.name), isNot(contains('İçecek')));
      expect(state.products.map((p) => p.name), isNot(contains('Çorba')));
    });

    test('conservative: excludes products with no ingredients text', () async {
      final noIngredients = _p(name: 'XYZ');
      final withClean = _p(name: 'Temiz', ingredientsText: 'süt, maya, tuz');

      final state = await _run(
        [noIngredients, withClean],
        const ProductSearchFilter(
          ingredientFilter: IngredientFilterConfig(excludeAddedSugar: true),
        ),
      );

      expect(state.products.map((p) => p.name), contains('Temiz'));
      expect(state.products.map((p) => p.name), isNot(contains('XYZ')));
    });
  });

  // ── Nutrition filter thresholds ───────────────────────────────────────────

  group('Nutrition filter thresholds', () {
    test('lifli filter (minFiber=3) keeps high-fiber products', () async {
      final highFiber = _p(name: 'Kepekli', nutritionText: '{"fiber": 5.2}');
      final lowFiber = _p(name: 'Beyaz', nutritionText: '{"fiber": 1.1}');
      final noFiber = _p(name: 'Tuz');

      final state = await _run(
        [highFiber, lowFiber, noFiber],
        const ProductSearchFilter(
          nutritionFilter: NutritionFilter(minFiber: 3.0),
        ),
      );

      expect(state.products.map((p) => p.name), contains('Kepekli'));
      expect(state.products.map((p) => p.name), isNot(contains('Beyaz')));
      expect(state.products.map((p) => p.name), isNot(contains('Tuz')));
    });

    test('NutritionFilter with minFiber is not empty', () {
      expect(const NutritionFilter(minFiber: 3.0).isEmpty, false);
    });
  });

  // ── initialFilter auto-fetch ──────────────────────────────────────────────

  group('FilteredSearchNotifier initialFilter', () {
    test('no initialFilter → isLoading=false, no auto-fetch', () {
      final n = FilteredSearchNotifier(_FakeRepo([]));
      expect(n.state.isLoading, false);
      expect(n.state.products, isEmpty);
    });

    test('initialFilter with active filters → isLoading=true immediately', () {
      final n = FilteredSearchNotifier(
        _FakeRepo([]),
        initialFilter: const ProductSearchFilter(mainCategory: 'Atıştırmalık'),
      );
      expect(n.state.isLoading, true);
      expect(n.state.filter.mainCategory, 'Atıştırmalık');
    });

    test('initialFilter with empty ProductSearchFilter → no auto-fetch', () {
      final n = FilteredSearchNotifier(
        _FakeRepo([]),
        initialFilter: const ProductSearchFilter(),
      );
      expect(n.state.isLoading, false);
    });

    test('initialFilter results are loaded after async fetch', () async {
      final sutasP = _p(name: 'Sütaş Süt', brand: 'Sütaş');
      final state = await _run([
        sutasP,
      ], const ProductSearchFilter(mainCategory: 'Süt ve Süt Ürünleri'));
      // The fake repo doesn't filter by mainCategory server-side, but results arrive.
      expect(state.isLoading, false);
      expect(state.products, isNotEmpty);
    });
  });
}
