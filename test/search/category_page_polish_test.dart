// Tests for category page Polish task:
// — _buildListContext bug fix (main category pages start with Tümü)
// — Filter sheet hides Category section on category pages
// — Brand section collapse (shows 5 + expand)
// — Bidirectional nutrition filter model
// — New sort enum values

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

// ── Helpers ───────────────────────────────────────────────────────────────────

class _EmptyRepo extends ProductRepository {
  @override
  Future<({List<Product> results, bool hasMore})> filteredSearch(
    ProductSearchFilter filter, {
    int pageSize = 20,
    int serverOffset = 0,
  }) async {
    return (results: const <Product>[], hasMore: false);
  }

  @override
  Future<List<String>> getBrandFacets(ProductSearchFilter filter) async =>
      List.generate(12, (i) => 'Marka${i + 1}');
}

Widget _makeApp({
  required ProductListContext listContext,
  ProductRepository? repo,
}) {
  final r = repo ?? _EmptyRepo();
  return ProviderScope(
    overrides: [
      filteredSearchProvider.overrideWith(
        (ref) => FilteredSearchNotifier(
          r,
          initialFilter: listContext.initialFilter(),
        ),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: ProductListView(listContext: listContext)),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ── Category default state: mainCategory mode always starts with Tümü ───────

  group('Category default state — Tümü', () {
    test('T1: mainCategory(kAtistirmalik) initialFilter has null sub', () {
      const ctx = ProductListContext.mainCategory(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
      );
      expect(ctx.initialFilter().subCategory, null);
    });

    test('T2: mainCategory(kSut) initialFilter has null sub', () {
      const ctx = ProductListContext.mainCategory(
        mainCategory: CanonicalCategoryMapper.kSut,
      );
      expect(ctx.initialFilter().subCategory, null);
    });

    test('T3: mainCategory(kIcecekler) initialFilter has null sub', () {
      const ctx = ProductListContext.mainCategory(
        mainCategory: CanonicalCategoryMapper.kIcecekler,
      );
      expect(ctx.initialFilter().subCategory, null);
    });

    test(
      'T4: subCategory shortcut pre-fills the locked sub in initialFilter',
      () {
        const ctx = ProductListContext.subCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
          subCategory: CanonicalCategoryMapper.kCips,
        );
        expect(ctx.initialFilter().subCategory, CanonicalCategoryMapper.kCips);
        expect(
          ctx.initialFilter().mainCategory,
          CanonicalCategoryMapper.kAtistirmalik,
        );
      },
    );

    test(
      'T5: mainCategory does not lock sub → canChangeSubCategory is true',
      () {
        const ctx = ProductListContext.mainCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        );
        expect(ctx.canChangeSubCategory, true);
      },
    );

    test('T6: mainCategory normalizeFilter allows any valid sub', () {
      const ctx = ProductListContext.mainCategory(
        mainCategory: CanonicalCategoryMapper.kAtistirmalik,
      );
      final result = ctx.normalizeFilter(
        const ProductSearchFilter(
          subCategory: CanonicalCategoryMapper.kBiskuvi,
        ),
      );
      expect(result.mainCategory, CanonicalCategoryMapper.kAtistirmalik);
      expect(result.subCategory, CanonicalCategoryMapper.kBiskuvi);
    });
  });

  // ── Filter sheet: no Category section on category pages ──────────────────────

  group('Filter sheet structure on category pages', () {
    testWidgets(
      'F1: filter sheet on mainCategory page hides Category section',
      (tester) async {
        const ctx = ProductListContext.mainCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        );
        await tester.pumpWidget(_makeApp(listContext: ctx));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.tune));
        await tester.pumpAndSettle();

        // Context banner is present (pushed-pin icon + category label).
        expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
        expect(find.text(CanonicalCategoryMapper.kAtistirmalik), findsWidgets);

        // The full category selector (choice chips for other mains) is absent.
        // kSut is never shown when category section is hidden.
        expect(find.text(CanonicalCategoryMapper.kSut), findsNothing);
      },
    );

    testWidgets(
      'F2: filter sheet on globalSearch page shows Category section',
      (tester) async {
        const ctx = ProductListContext.globalSearch();
        await tester.pumpWidget(_makeApp(listContext: ctx));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.tune));
        await tester.pumpAndSettle();

        // On global search, category section is present.
        expect(find.text('Ana kategori'), findsOneWidget);
      },
    );

    testWidgets(
      'F3: filter sheet on category page shows Sort and Brand; no Kategori section',
      (tester) async {
        const ctx = ProductListContext.mainCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        );
        await tester.pumpWidget(_makeApp(listContext: ctx));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.tune));
        await tester.pumpAndSettle();

        // Always-visible sections at the top of the sheet.
        expect(find.text('Sıralama'), findsOneWidget);
        expect(find.text('Marka'), findsOneWidget);
        // Category section ABSENT on category pages (key assertion).
        expect(find.text('Kategori'), findsNothing);
        // The _ContextBanner shows locked category — not the full category picker.
        expect(find.text('Ana kategori'), findsNothing);
      },
    );
  });

  // ── Active filter chips: no duplicate main/sub on category pages ─────────────

  group('Active filter chips on category pages', () {
    testWidgets(
      'C1: no push_pin or close chip visible on category page without extra filters',
      (tester) async {
        const ctx = ProductListContext.mainCategory(
          mainCategory: CanonicalCategoryMapper.kAtistirmalik,
        );
        await tester.pumpWidget(_makeApp(listContext: ctx));
        await tester.pumpAndSettle();

        // The _SubCategoryQuickFilter owns main/sub display; not the chip row.
        expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
        expect(find.byIcon(Icons.close), findsNothing);
      },
    );
  });

  // ── Sort section: primary + nutrition sort ────────────────────────────────────

  group('Sort — new enum values', () {
    test('S1: proteinsAsc is a distinct sort order', () {
      expect(SearchSortOrder.proteinsAsc, isNot(SearchSortOrder.proteinsDesc));
    });

    test(
      'S2: sugarsDesc, fatDesc, saltDesc, fiberAsc exist and have labels',
      () {
        for (final s in [
          SearchSortOrder.sugarsDesc,
          SearchSortOrder.fatDesc,
          SearchSortOrder.saltDesc,
          SearchSortOrder.fiberAsc,
          SearchSortOrder.saturatedFatAsc,
          SearchSortOrder.saturatedFatDesc,
        ]) {
          expect(s.label.isNotEmpty, true, reason: '$s has empty label');
        }
      },
    );

    test('S3: new nutrition sorts are flagged as isNutritionSort', () {
      for (final s in [
        SearchSortOrder.proteinsAsc,
        SearchSortOrder.sugarsDesc,
        SearchSortOrder.fatDesc,
        SearchSortOrder.saltDesc,
        SearchSortOrder.fiberAsc,
        SearchSortOrder.saturatedFatAsc,
        SearchSortOrder.saturatedFatDesc,
      ]) {
        final filter = ProductSearchFilter(sortOrder: s);
        expect(
          filter.isNutritionSort,
          true,
          reason: '$s should be nutrition sort',
        );
      }
    });

    test('S4: basic sorts are NOT flagged as isNutritionSort', () {
      for (final s in [
        SearchSortOrder.relevance,
        SearchSortOrder.newestFirst,
        SearchSortOrder.nameAsc,
        SearchSortOrder.nameDesc,
        SearchSortOrder.brandAsc,
        SearchSortOrder.brandDesc,
      ]) {
        final filter = ProductSearchFilter(sortOrder: s);
        expect(
          filter.isNutritionSort,
          false,
          reason: '$s should not be nutrition sort',
        );
      }
    });
  });

  // ── Bidirectional NutritionFilter model ──────────────────────────────────────

  group('NutritionFilter — bidirectional fields', () {
    test('N1: new fields start null, isEmpty is true', () {
      const n = NutritionFilter();
      expect(n.isEmpty, true);
      expect(n.minEnergyKcal, null);
      expect(n.maxProteins, null);
      expect(n.minSugars, null);
      expect(n.minFat, null);
      expect(n.maxSaturatedFat, null);
      expect(n.minSaturatedFat, null);
      expect(n.maxFiber, null);
      expect(n.maxCarbohydrates, null);
      expect(n.minCarbohydrates, null);
    });

    test('N2: setting minEnergyKcal makes isEmpty false', () {
      const n = NutritionFilter(minEnergyKcal: 200);
      expect(n.isEmpty, false);
      expect(n.minEnergyKcal, 200);
      expect(n.maxEnergyKcal, null);
    });

    test('N3: energy range filter: max AND min can both be set', () {
      const n = NutritionFilter(minEnergyKcal: 100, maxEnergyKcal: 300);
      expect(n.isEmpty, false);
      expect(n.minEnergyKcal, 100);
      expect(n.maxEnergyKcal, 300);
    });

    test('N4: copyWith sets new Doymuş Yağ fields', () {
      const n = NutritionFilter();
      final updated = n.copyWith(maxSaturatedFat: 3.0, minSaturatedFat: 1.0);
      expect(updated.maxSaturatedFat, 3.0);
      expect(updated.minSaturatedFat, 1.0);
      expect(updated.isEmpty, false);
    });

    test('N5: copyWith sets Karbonhidrat fields', () {
      const n = NutritionFilter();
      final updated = n.copyWith(
        maxCarbohydrates: 30.0,
        minCarbohydrates: 10.0,
      );
      expect(updated.maxCarbohydrates, 30.0);
      expect(updated.minCarbohydrates, 10.0);
    });

    test('N6: copyWith clears a field via explicit null (absent sentinel)', () {
      const n = NutritionFilter(maxEnergyKcal: 200, minEnergyKcal: 100);
      final cleared = n.copyWith(minEnergyKcal: null);
      expect(cleared.maxEnergyKcal, 200);
      expect(cleared.minEnergyKcal, null);
    });
  });

  // ── NutrientFilterSpec — exported specs unchanged for test compat ─────────────

  group('Exported kNutrientFilterSpecs unchanged', () {
    test('E1: still covers the 6 original nutrients', () {
      final keys = kNutrientFilterSpecs.map((s) => s.key).toSet();
      expect(
        keys,
        containsAll(['energy', 'protein', 'sugar', 'fat', 'salt', 'fiber']),
      );
    });

    test('E2: protein spec comparator still ≥', () {
      final spec = kNutrientFilterSpecs.firstWhere((s) => s.key == 'protein');
      expect(spec.comparator, '≥');
    });

    test('E3: energy spec comparator still ≤', () {
      final spec = kNutrientFilterSpecs.firstWhere((s) => s.key == 'energy');
      expect(spec.comparator, '≤');
    });
  });
}
