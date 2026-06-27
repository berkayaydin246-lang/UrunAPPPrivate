import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/pages/category_products_page.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

class _ThemeRepo extends ProductRepository {
  const _ThemeRepo();

  @override
  Future<({List<Product> results, bool hasMore})> filteredSearch(
    ProductSearchFilter filter, {
    int pageSize = 20,
    int serverOffset = 0,
  }) async {
    final now = DateTime(2026, 1, 1);
    return (
      results: [
        Product(
          id: 'theme-product-${filter.mainCategory ?? 'global'}',
          name: 'Kategori Renk Test Ürünü',
          brand: 'Etiketly',
          canonicalCategory: filter.mainCategory,
          verificationStatus: 'verified',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      hasMore: false,
    );
  }

  @override
  Future<List<String>> getBrandFacets(ProductSearchFilter filter) async =>
      const ['Etiketly'];
}

Future<void> _pumpCategoryPage(WidgetTester tester, String categoryId) async {
  final category = ProductCategories.findById(categoryId)!;
  await tester.pumpWidget(
    ProviderScope(
      key: ValueKey('category-page-provider-$categoryId'),
      child: _CategoryPageHarness(category: category),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 260));
  await tester.pump();
}

class _CategoryPageHarness extends StatelessWidget {
  final ProductCategory? category;

  const _CategoryPageHarness({required this.category});

  @override
  Widget build(BuildContext context) {
    final resolvedCategory =
        category ?? ProductCategories.findById('atistirmalik')!;
    return MaterialApp(
      theme: AppTheme.lightTheme(useGoogleFonts: false),
      home: CategoryProductsPage(
        category: resolvedCategory,
        productRepository: const _ThemeRepo(),
      ),
    );
  }
}

TabBar _mainTabBar(WidgetTester tester) {
  return tester.widget<TabBar>(
    find.byKey(const ValueKey('main-category-tab-bar')),
  );
}

Color _tabUnderlineColor(TabBar tabBar) {
  final indicator = tabBar.indicator as UnderlineTabIndicator;
  return indicator.borderSide.color;
}

void _expectMainTabUsesTheme(WidgetTester tester, CategoryThemeData theme) {
  final tabBar = _mainTabBar(tester);
  expect(tabBar.labelColor?.toARGB32(), theme.selectedChipColor.toARGB32());
  expect(
    _tabUnderlineColor(tabBar).toARGB32(),
    theme.selectedChipColor.toARGB32(),
  );
}

void main() {
  testWidgets('selected main tab text and underline follow tapped category', (
    tester,
  ) async {
    await _pumpCategoryPage(tester, 'atistirmalik');
    final snackTheme = getCategoryTheme(CanonicalCategoryMapper.kAtistirmalik);
    _expectMainTabUsesTheme(tester, snackTheme);

    await tester.tap(find.text('İçecek').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final drinkTheme = getCategoryTheme(CanonicalCategoryMapper.kIcecek);
    _expectMainTabUsesTheme(tester, drinkTheme);
    expect(
      _mainTabBar(tester).labelColor?.toARGB32(),
      isNot(snackTheme.selectedChipColor.toARGB32()),
    );
  });

  testWidgets('initial selected tabs use their own unique accents', (
    tester,
  ) async {
    final cases = {
      'icecek': CanonicalCategoryMapper.kIcecek,
      'temel-gida': CanonicalCategoryMapper.kTemelGida,
      'et-tavuk-balik': CanonicalCategoryMapper.kEtTavukBalik,
    };

    for (final entry in cases.entries) {
      await _pumpCategoryPage(tester, entry.key);
      _expectMainTabUsesTheme(tester, getCategoryTheme(entry.value));
    }
  });

  testWidgets('listing controls share the selected category accent', (
    tester,
  ) async {
    await _pumpCategoryPage(tester, 'icecek');
    final theme = getCategoryTheme(CanonicalCategoryMapper.kIcecek);
    _expectMainTabUsesTheme(tester, theme);

    final chip = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('subcategory-chip-İçecek-Tümü')),
    );
    final chipDecoration = chip.decoration! as BoxDecoration;
    final chipBorder = chipDecoration.border! as Border;
    expect(
      chipDecoration.color?.toARGB32(),
      theme.selectedChipColor.toARGB32(),
    );
    expect(chipBorder.top.color.toARGB32(), theme.selectedChipColor.toARGB32());

    final searchField = tester.widget<TextField>(
      find.byKey(const ValueKey('product-search-field-İçecek')),
    );
    final searchIcon = searchField.decoration!.prefixIcon! as Icon;
    final enabledBorder =
        searchField.decoration!.enabledBorder! as OutlineInputBorder;
    final focusedBorder =
        searchField.decoration!.focusedBorder! as OutlineInputBorder;
    expect(searchIcon.color?.toARGB32(), theme.selectedChipColor.toARGB32());
    expect(
      enabledBorder.borderSide.color.toARGB32(),
      theme.selectedChipColor.toARGB32(),
    );
    expect(
      focusedBorder.borderSide.color.toARGB32(),
      theme.selectedChipColor.toARGB32(),
    );

    final filterButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('product-filter-button-İçecek')),
    );
    final filterIcon = filterButton.icon as Icon;
    final filterSide = filterButton.style?.side?.resolve(<WidgetState>{});
    expect(filterIcon.color?.toARGB32(), theme.selectedChipColor.toARGB32());
    expect(filterSide?.color.toARGB32(), theme.selectedChipColor.toARGB32());

    final countText = tester.widget<Text>(
      find.byKey(const ValueKey('product-result-count-İçecek')),
    );
    expect(
      countText.style?.color?.toARGB32(),
      theme.selectedChipColor.toARGB32(),
    );
    expect(find.byKey(const ValueKey('category-product-grid')), findsOneWidget);
  });

  testWidgets(
    'subcategory chips keep centered equal-height layout on narrow phones',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;

      await _pumpCategoryPage(tester, 'atistirmalik');

      final selectedChipFinder = find.byKey(
        const ValueKey('subcategory-chip-Atıştırmalık-Tümü'),
      );
      final unselectedChipFinder = find.byKey(
        const ValueKey('subcategory-chip-Atıştırmalık-Bisküvi'),
      );
      final selectedSize = tester.getSize(selectedChipFinder);
      final unselectedSize = tester.getSize(unselectedChipFinder);
      final selectedCenter = tester.getCenter(selectedChipFinder).dy;
      final selectedTextCenter = tester
          .getCenter(
            find.descendant(
              of: selectedChipFinder,
              matching: find.text('Tümü'),
            ),
          )
          .dy;

      expect(selectedSize.height, 36);
      expect(unselectedSize.height, selectedSize.height);
      expect((selectedCenter - selectedTextCenter).abs(), lessThan(1.5));
      expect(tester.takeException(), isNull);
    },
  );
}
