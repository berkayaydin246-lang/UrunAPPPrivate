/// Category-filtering correctness tests.
///
/// Verifies the full chain:
///   ProductCategory.databaseTags
///   → CanonicalCategoryMapper._mainToTags
///   → ProductSearchFilter.queryPlan.categoryTagsAny
///   → ProductRepository.filteredSearch() guard
///
/// Tests 1–12 from the category filtering spec.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

// ── Fake repository (mirrors real server filtering + guard) ───────────────────

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
    final plan = filter.queryPlan;
    if (plan.hasFilter) {
      if (plan.categoryTagsAny.isNotEmpty) {
        r = r.where((p) {
          final tags = p.categoryTags ?? const <String>[];
          return tags.any(plan.categoryTagsAny.contains);
        }).toList();
      } else {
        // Empty tag list → must never return unfiltered results.
        return (results: <Product>[], hasMore: false);
      }
    }
    final paged = r.skip(serverOffset).take(pageSize).toList();
    return (results: paged, hasMore: r.length > serverOffset + pageSize);
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

final _now = DateTime.now();

Product _p(String id, String name, {List<String>? categoryTags}) => Product(
  id: id,
  name: name,
  categoryTags: categoryTags,
  verificationStatus: 'verified',
  createdAt: _now,
  updatedAt: _now,
);

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
  for (var i = 0; i < 80; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!container.read(filteredSearchProvider).isLoading) break;
  }
  return container.read(filteredSearchProvider);
}

// ── Forbidden tags ────────────────────────────────────────────────────────────

const _snackDrinkTags = {
  'atistirmalik',
  'biskuvi_kek',
  'cips_kraker',
  'cikolata_gofret',
  'biskuvi',
  'cips',
  'kuruyemis',
  'cikolata',
  'bar_kaplamalilar',
  'kek',
  'kraker',
  'sekerleme',
  'sakiz',
  'icecekler',
  'enerji_icecekleri',
  'gazli_icecek',
  'gazsiz_icecek',
  'findik_ezmesi',
  'kahvaltilik',
  'kahvaltiliklar',
};

void main() {
  // ── Test 1: Meyve & Sebze tags don't include snack/drink/lokum tags ──────

  test('1: Meyve & Sebze tags exclude snack, drink, chocolate, lokum tags', () {
    final meyveTags = CanonicalCategoryMapper.mainCategoryToTags(
      CanonicalCategoryMapper.kMeyveSebze,
    );
    for (final forbidden in _snackDrinkTags) {
      expect(
        meyveTags,
        isNot(contains(forbidden)),
        reason: 'Meyve & Sebze must not include "$forbidden"',
      );
    }
  });

  // ── Test 2: Meyve & Sebze query plan uses fruit/vegetable tags only ───────

  test('2: Meyve & Sebze query plan tags are fruit/vegetable only', () {
    const filter = ProductSearchFilter(
      mainCategory: CanonicalCategoryMapper.kMeyveSebze,
    );
    final plan = filter.queryPlan;
    expect(plan.hasFilter, isTrue);
    expect(plan.categoryTagsAny, isNotEmpty);
    for (final tag in plan.categoryTagsAny) {
      expect(
        _snackDrinkTags,
        isNot(contains(tag)),
        reason: 'Meyve & Sebze query plan must not include "$tag"',
      );
    }
    // Verify fruit/veg tags present
    expect(
      plan.categoryTagsAny,
      containsAll(['meyve_sebze', 'meyve', 'sebze']),
    );
  });

  // ── Test 3: Empty category tags return empty, never all products ──────────

  test(
    '3: Empty categoryTagsAny plan returns empty, no unfiltered fallback',
    () async {
      final unrelatedProducts = [
        _p('kruv', '7 Days Kruvasan', categoryTags: ['biskuvi_kek']),
        _p('soda', '7UP Gazoz', categoryTags: ['gazli_icecek']),
        _p('lokum', 'Lokum', categoryTags: ['sekerleme']),
      ];

      // Build a filter whose queryPlan will have empty categoryTagsAny.
      // We achieve this by directly constructing the scenario via the mapper:
      // any category not in _mainToTags returns [].
      final emptyPlanTags = CanonicalCategoryMapper.mainCategoryToTags(
        '__unknown_category__',
      );
      expect(emptyPlanTags, isEmpty);

      // Simulate the filter that would produce empty tags.
      // Use a custom plan-aware fake that passes the real filter unchanged.
      final state = await _run(
        unrelatedProducts,
        const ProductSearchFilter(mainCategory: '__unknown_category__'),
      );
      expect(
        state.products,
        isEmpty,
        reason: 'Unknown category must not return unrelated products',
      );
    },
  );

  // ── Test 4: Unknown category produces empty results ───────────────────────

  test('4: Unknown category never returns unfiltered product list', () async {
    final products = List.generate(
      5,
      (i) => _p('p$i', 'Product $i', categoryTags: ['atistirmalik']),
    );
    final state = await _run(
      products,
      const ProductSearchFilter(mainCategory: 'NonExistentCategory'),
    );
    expect(state.products, isEmpty);
  });

  // ── Test 5: Repository uses category_tags with 'ov' ──────────────────────

  test('5: Query plan carries categoryTagsAny for ov filter, not raw ids', () {
    const filter = ProductSearchFilter(
      mainCategory: CanonicalCategoryMapper.kAtistirmalik,
    );
    final plan = filter.queryPlan;
    expect(plan.hasFilter, isTrue);
    expect(plan.mainCategoryKey, CanonicalCategoryMapper.kAtistirmalik);
    // categoryTagsAny should be non-empty DB tag slugs (no Turkish diacritics,
    // no spaces) — suitable for the PostgREST 'ov' operator.
    for (final tag in plan.categoryTagsAny) {
      expect(
        tag,
        isNot(contains(' ')),
        reason: 'tags must be slugs, not phrases',
      );
      expect(tag, isNot(isEmpty));
    }
  });

  // ── Test 6: toPostgresTextArrayLiteral helper ─────────────────────────────

  test('6: toPostgresTextArrayLiteral formats correctly', () {
    expect(
      CanonicalCategoryMapper.toPostgresTextArrayLiteral(['biskuvi', 'cips']),
      '{biskuvi,cips}',
    );
    expect(CanonicalCategoryMapper.toPostgresTextArrayLiteral([]), '');
    expect(
      CanonicalCategoryMapper.toPostgresTextArrayLiteral([
        ' meyve ',
        'sebze',
        'meyve',
      ]),
      '{meyve,sebze}',
      reason: 'trims spaces and de-duplicates',
    );
    expect(
      CanonicalCategoryMapper.toPostgresTextArrayLiteral(['', '  ', 'sebze']),
      '{sebze}',
      reason: 'drops empty/blank entries',
    );
    expect(
      CanonicalCategoryMapper.toPostgresTextArrayLiteral(['meyve_sebze']),
      '{meyve_sebze}',
    );
  });

  // ── Test 7: Atıştırmalık uses snack tags ─────────────────────────────────

  test('7: Atıştırmalık query uses snack tags', () async {
    final products = [
      _p('b1', 'Eti Burçak', categoryTags: ['biskuvi_kek']),
      _p('c1', 'Lay\'s Cips', categoryTags: ['cips_kraker']),
      _p('s1', 'Sütaş Süt', categoryTags: ['sut']),
    ];
    final state = await _run(
      products,
      const ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
      ),
    );
    final ids = state.products.map((p) => p.id).toSet();
    expect(ids, containsAll(['b1', 'c1']));
    expect(ids, isNot(contains('s1')));
  });

  // ── Test 8: İçecek uses drink tags ───────────────────────────────────────

  test('8: İçecek query uses drink tags', () async {
    final products = [
      _p('g1', '7UP Gazoz', categoryTags: ['gazli_icecek']),
      _p('e1', 'Monster Enerji', categoryTags: ['enerji_icecekleri']),
      _p('b1', 'Eti Burçak', categoryTags: ['biskuvi_kek']),
    ];
    final state = await _run(
      products,
      const ProductSearchFilter(mainCategory: CanonicalCategoryMapper.kIcecek),
    );
    final ids = state.products.map((p) => p.id).toSet();
    expect(ids, containsAll(['g1', 'e1']));
    expect(ids, isNot(contains('b1')));
  });

  // ── Test 9: Hazır & Donuk with no matching products shows empty state ──────

  test(
    '9: Hazır & Donuk shows empty state when no matching products exist',
    () async {
      final products = [
        _p('k1', '7 Days Kruvasan', categoryTags: ['biskuvi_kek']),
        _p('s1', '7UP Gazoz', categoryTags: ['gazli_icecek']),
        _p('l1', 'Lokum', categoryTags: ['sekerleme']),
      ];
      final state = await _run(
        products,
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kHazirDonuk,
        ),
      );
      expect(
        state.products,
        isEmpty,
        reason: 'Must show empty state, not unrelated snack/drink products',
      );
    },
  );

  // ── Test 10: Valid category products still render ─────────────────────────

  test('10: Products matching category tags are returned correctly', () async {
    final products = [
      _p('h1', 'Hazır Çorba', categoryTags: ['hazir_yemek']),
      _p('h2', 'Donuk Pizza', categoryTags: ['hazir_yemek']),
      _p('b1', 'Bisküvi', categoryTags: ['biskuvi_kek']),
    ];
    final state = await _run(
      products,
      const ProductSearchFilter(
        mainCategory: CanonicalCategoryMapper.kHazirDonuk,
      ),
    );
    final ids = state.products.map((p) => p.id).toSet();
    expect(ids, containsAll(['h1', 'h2']));
    expect(ids, isNot(contains('b1')));
  });

  // ── Test 11: All visible main category colors are unique ─────────────────

  test('11: Visible main category accent colors are unique', () {
    final colors = ProductCategories.getVisible()
        .map((c) => c.color.toARGB32())
        .toList();
    expect(
      colors.toSet().length,
      equals(colors.length),
      reason: 'Each main category must have a unique accent color',
    );
  });

  // ── Test 12: Subcategory chips use the correct category tags ─────────────

  test('12: Subcategory subs exist only for categories with defined tags', () {
    // For any category that has subcategories, the main category must have tags.
    for (final main in CanonicalCategoryMapper.visibleMainCategories) {
      final subs = CanonicalCategoryMapper.subCategoriesFor(main);
      if (subs.isNotEmpty) {
        final mainTags = CanonicalCategoryMapper.mainCategoryToTags(main);
        expect(
          mainTags,
          isNotEmpty,
          reason: '$main has subcategories but empty main tags',
        );
      }
    }
  });

  // ── Meyve & Sebze ProductCategory definition sanity ──────────────────────

  test('Meyve & Sebze ProductCategory databaseTags match mapper', () {
    final cat = ProductCategories.findById('meyve-sebze');
    expect(cat, isNotNull);
    expect(cat!.databaseTags, isNotEmpty);
    final mapperTags = CanonicalCategoryMapper.mainCategoryToTags(
      CanonicalCategoryMapper.kMeyveSebze,
    );
    expect(cat.databaseTags.toSet(), equals(mapperTags.toSet()));
    // No forbidden tags in databaseTags either.
    for (final t in cat.databaseTags) {
      expect(_snackDrinkTags, isNot(contains(t)));
    }
  });

  // ── Fırın & Pastane ProductCategory definition sanity ────────────────────

  test('Fırın & Pastane ProductCategory databaseTags are non-empty', () {
    final cat = ProductCategories.findById('firin-pastane');
    expect(cat, isNotNull);
    expect(cat!.databaseTags, isNotEmpty);
    final mapperTags = CanonicalCategoryMapper.mainCategoryToTags(
      CanonicalCategoryMapper.kFirinPastane,
    );
    expect(cat.databaseTags.toSet(), equals(mapperTags.toSet()));
  });

  // ── Meyve & Sebze shows empty when no matching DB products exist ──────────

  test(
    'Meyve & Sebze returns empty when no fruit/veg products in DB',
    () async {
      final unrelatedProducts = [
        _p('k', '7 Days Kruvasan', categoryTags: ['biskuvi_kek']),
        _p('s', '7UP Gazoz', categoryTags: ['gazli_icecek']),
        _p('cs', 'Tadibu Çikolata', categoryTags: ['findik_ezmesi']),
        _p('l', 'Lokum', categoryTags: ['sekerleme']),
      ];
      final state = await _run(
        unrelatedProducts,
        const ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kMeyveSebze,
        ),
      );
      expect(
        state.products,
        isEmpty,
        reason:
            'No fruit/veg tagged products → empty state, not snack products',
      );
    },
  );
}
