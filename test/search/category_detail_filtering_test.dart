import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/models/product_list_context.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';
import 'package:food_analyzer_app/features/search/widgets/product_list_view.dart';

class _PagedRepo extends ProductRepository {
  final Map<int, List<Product>> pages;

  _PagedRepo(this.pages);

  @override
  Future<({List<Product> results, bool hasMore})> filteredSearch(
    ProductSearchFilter filter, {
    int pageSize = 20,
    int serverOffset = 0,
  }) async {
    final results = pages[serverOffset] ?? const <Product>[];
    final hasMore = pages.keys.any((key) => key > serverOffset);
    return (results: results, hasMore: hasMore);
  }
}

Product _product({
  required String id,
  required String name,
  List<String>? categoryTags,
  List<String>? searchKeywords,
  String? canonicalCategory,
  String? canonicalSubcategory,
}) {
  final now = DateTime.now();
  return Product(
    id: id,
    name: name,
    categoryTags: categoryTags,
    searchKeywords: searchKeywords,
    canonicalCategory: canonicalCategory,
    canonicalSubcategory: canonicalSubcategory,
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
  );
}

Future<FilteredSearchState> _runSearch(
  ProductRepository repo,
  ProductSearchFilter filter,
) async {
  final container = ProviderContainer(
    overrides: [
      filteredSearchProvider.overrideWith(
        (ref) => FilteredSearchNotifier(repo, initialFilter: filter),
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

void main() {
  group('ProductListContext', () {
    test(
      'subcategory mode keeps locked main category but allows clearing sub',
      () {
        const context = ProductListContext.subCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
        );

        // Clearing the filter (no sub provided) must NOT force lockedSub.
        final normalized = context.normalizeFilter(const ProductSearchFilter());

        expect(normalized.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
        expect(normalized.subCategory, null);
      },
    );

    test(
      'subcategory mode normalizeFilter allows switching to a sibling sub',
      () {
        const context = ProductListContext.subCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
        );

        final normalized = context.normalizeFilter(
          const ProductSearchFilter(
            subCategory: CanonicalCategoryMapper.kBiskuvi,
          ),
        );

        expect(normalized.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
        expect(normalized.subCategory, CanonicalCategoryMapper.kBiskuvi);
      },
    );

    test(
      'subcategory mode normalizeFilter rejects sub from unrelated main',
      () {
        const context = ProductListContext.subCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
        );

        // kYogurt belongs to kSut, not kAtistirmalik.
        final normalized = context.normalizeFilter(
          const ProductSearchFilter(
            subCategory: CanonicalCategoryMapper.kYogurt,
          ),
        );

        expect(normalized.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
        expect(normalized.subCategory, null);
      },
    );

    test('subcategory mode initialFilter pre-fills the locked sub', () {
      const context = ProductListContext.subCategory(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        subCategory: CanonicalCategoryMapper.kCikolata,
      );

      final initial = context.initialFilter();

      expect(initial.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
      expect(initial.subCategory, CanonicalCategoryMapper.kCikolata);
    });

    test(
      'subcategory mode locksSubCategory is false and canChangeSubCategory is true',
      () {
        const context = ProductListContext.subCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
        );

        expect(context.locksSubCategory, false);
        expect(context.canChangeSubCategory, true);
      },
    );

    test(
      'main-category mode does not count locked main category as extra filter',
      () {
        const context = ProductListContext.mainCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        );
        const filter = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kKraker,
          brands: ['Eti'],
        );

        expect(context.visibleActiveFilterCount(filter), 1);
      },
    );

    test(
      'subcategory mode visibleActiveFilterCount is 0 on default page state',
      () {
        const context = ProductListContext.subCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
        );
        // Sub equals lockedSub → no deviation from page default.
        const filter = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
        );

        expect(context.visibleActiveFilterCount(filter), 0);
      },
    );

    test(
      'subcategory mode visibleActiveFilterCount stays 0 when sub changes',
      () {
        const context = ProductListContext.subCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
        );
        // Subcategory context is locked to the page and does not count as an
        // optional filter in the badge.
        const filter = ProductSearchFilter(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kBiskuvi,
        );

        expect(context.visibleActiveFilterCount(filter), 0);
      },
    );
  });

  group('Category detail filtering', () {
    test(
      'skips empty first raw page for shared-tag subcategory (requiresClientValidation=true)',
      () async {
        // kMakarna and kBakliyat both share the makarna_bakliyat tag, so the
        // server returns both; the client-side pass distinguishes them.
        // Page 0 has a bakliyat product (rejected by kMakarna client filter).
        // Page 1 has a makarna product (accepted by kMakarna client filter).
        // The controller must loop past the empty page 0 and return page 1.
        final state = await _runSearch(
          _PagedRepo({
            0: [
              _product(
                id: 'nohut',
                name: 'Nohut 500g',
                categoryTags: const ['makarna_bakliyat'],
              ),
            ],
            1: [
              _product(
                id: 'makarna',
                name: 'Penne Makarna 500g',
                categoryTags: const ['makarna_bakliyat'],
              ),
            ],
          }),
          const ProductSearchFilter(
            mainCategory: CanonicalCategoryMapper.kTemelGida,
            subCategory: CanonicalCategoryMapper.kMakarna,
          ),
        );

        expect(state.products.map((p) => p.id), ['makarna']);
        expect(state.hasMore, false);
      },
    );

    test(
      'cikolata matcher includes chocolate snack but excludes breakfast spread',
      () {
        final chocolateMatch = CanonicalCategoryMapper.matchesSubCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
          categoryTags: const ['biskuvi_kek'],
          name: 'Popkek Bitter Cikolatali',
          searchKeywords: const ['popkek', 'cikolata', 'kaplamali'],
        );
        final spreadMatch = CanonicalCategoryMapper.matchesSubCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCikolata,
          categoryTags: const ['findik_ezmesi'],
          name: 'Cokokrem Findik Ezmesi',
          searchKeywords: const ['cokokrem', 'findik', 'ezme'],
          canonicalCategory: CanonicalCategoryMapper.kKahvaltilik,
          canonicalSubcategory: CanonicalCategoryMapper.kKremCikolata,
        );

        expect(chocolateMatch, true);
        expect(spreadMatch, false);
      },
    );
  });

  testWidgets(
    'category page: no duplicate main/sub chips; filter sheet shows context banner',
    (tester) async {
      const listContext = ProductListContext.subCategory(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        subCategory: CanonicalCategoryMapper.kCikolata,
      );
      final initialFilter = listContext.initialFilter();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            filteredSearchProvider.overrideWith(
              (ref) => FilteredSearchNotifier(
                _PagedRepo({0: const []}),
                initialFilter: initialFilter,
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ProductListView(listContext: listContext)),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // On a category page, the active-filter chip row does NOT show main/sub
      // chips — those live in CategoryProductsPage's _SubCategoryQuickFilter.
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      // Filter sheet shows the locked category in the context banner.
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      expect(find.text(CanonicalCategoryMapper.kAtistirmalik), findsWidgets);
      // Category section is hidden on category pages — unrelated mains absent.
      expect(find.text(CanonicalCategoryMapper.kSut), findsNothing);
      expect(find.text(CanonicalCategoryMapper.kKahvaltilik), findsNothing);
    },
  );
}
