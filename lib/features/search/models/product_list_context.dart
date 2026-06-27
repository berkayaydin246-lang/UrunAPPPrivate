import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

enum ProductListMode { globalSearch, mainCategory, subCategory, brand, search }

class ProductListContext {
  final ProductListMode mode;
  final String? lockedMainCategory;
  final String? lockedSubCategory;
  final String? userSelectedMainCategory;
  final String? userSelectedSubCategory;
  final String? searchText;
  final String? brandFilter;
  final NutritionFilter nutritionFilters;
  final IngredientFilterConfig ingredientFilters;
  final SearchSortOrder sortOption;

  const ProductListContext.globalSearch({
    this.userSelectedMainCategory,
    this.userSelectedSubCategory,
    this.searchText,
    this.brandFilter,
    this.nutritionFilters = const NutritionFilter(),
    this.ingredientFilters = const IngredientFilterConfig(),
    this.sortOption = SearchSortOrder.relevance,
  }) : mode = ProductListMode.globalSearch,
       lockedMainCategory = null,
       lockedSubCategory = null;

  const ProductListContext.mainCategory({
    required String mainCategory,
    this.userSelectedSubCategory,
    this.searchText,
    this.brandFilter,
    this.nutritionFilters = const NutritionFilter(),
    this.ingredientFilters = const IngredientFilterConfig(),
    this.sortOption = SearchSortOrder.relevance,
  }) : mode = ProductListMode.mainCategory,
       lockedMainCategory = mainCategory,
       lockedSubCategory = null,
       userSelectedMainCategory = null;

  const ProductListContext.subCategory({
    required String mainCategory,
    required String subCategory,
    this.searchText,
    this.brandFilter,
    this.nutritionFilters = const NutritionFilter(),
    this.ingredientFilters = const IngredientFilterConfig(),
    this.sortOption = SearchSortOrder.relevance,
  }) : mode = ProductListMode.subCategory,
       lockedMainCategory = mainCategory,
       lockedSubCategory = subCategory,
       userSelectedMainCategory = null,
       userSelectedSubCategory = null;

  bool get hasLockedCategory => lockedMainCategory != null;

  bool get locksMainCategory =>
      mode == ProductListMode.mainCategory ||
      mode == ProductListMode.subCategory;

  // SubCategory is never locked — users can switch to a sibling or clear the
  // sub-category; clearing it stays in the locked mainCategory, not global.
  bool get locksSubCategory => false;

  bool get canChangeMainCategory => mode == ProductListMode.globalSearch;

  bool get canChangeSubCategory => true;

  String? get lockedCategoryLabel => lockedSubCategory ?? lockedMainCategory;

  ProductSearchFilter initialFilter() {
    final brands = brandFilter == null || brandFilter!.trim().isEmpty
        ? const <String>[]
        : [brandFilter!.trim()];
    // For subCategory mode, pre-fill the locked sub as the user's starting selection.
    final initialSub = mode == ProductListMode.subCategory
        ? lockedSubCategory
        : userSelectedSubCategory;
    return normalizeFilter(
      ProductSearchFilter(
        query: searchText ?? '',
        mainCategory: userSelectedMainCategory,
        subCategory: initialSub,
        brands: brands,
        nutritionFilter: nutritionFilters,
        ingredientFilter: ingredientFilters,
        sortOrder: sortOption,
      ),
    );
  }

  ProductSearchFilter normalizeFilter(ProductSearchFilter filter) {
    switch (mode) {
      case ProductListMode.globalSearch:
      case ProductListMode.brand:
      case ProductListMode.search:
        final main = filter.mainCategory;
        return filter.copyWith(
          mainCategory: main,
          subCategory: main == null ? null : filter.subCategory,
        );
      case ProductListMode.mainCategory:
        final subs = lockedMainCategory == null
            ? const <String>[]
            : CanonicalCategoryMapper.subCategoriesFor(lockedMainCategory!);
        return filter.copyWith(
          mainCategory: lockedMainCategory,
          subCategory: subs.contains(filter.subCategory)
              ? filter.subCategory
              : null,
        );
      case ProductListMode.subCategory:
        // Main is always locked. Sub can be null (all) or any valid sibling.
        final subs = lockedMainCategory == null
            ? const <String>[]
            : CanonicalCategoryMapper.subCategoriesFor(lockedMainCategory!);
        return filter.copyWith(
          mainCategory: lockedMainCategory,
          subCategory: subs.contains(filter.subCategory)
              ? filter.subCategory
              : null,
        );
    }
  }

  ProductSearchFilter resetFilter({required String query}) {
    return normalizeFilter(ProductSearchFilter(query: query));
  }

  int visibleActiveFilterCount(ProductSearchFilter filter) {
    var count = 0;
    switch (mode) {
      case ProductListMode.globalSearch:
      case ProductListMode.brand:
      case ProductListMode.search:
        if (filter.mainCategory != null) count++;
        if (filter.subCategory != null) count++;
      case ProductListMode.mainCategory:
      // Subcategory selection is part of the locked category context on
      // category pages and should not inflate the optional-filter badge.
      case ProductListMode.subCategory:
      // Subcategory selection is never counted as an optional filter on
      // subcategory pages either; only brand/nutrition/ingredient matter.
    }

    count += filter.brands.length;
    if (!filter.nutritionFilter.isEmpty) count++;
    if (!filter.ingredientFilter.isEmpty) count++;
    return count;
  }

  List<String> availableMainCategories(ProductSearchFilter filter) {
    if (canChangeMainCategory) {
      return CanonicalCategoryMapper.visibleMainCategories;
    }
    return lockedMainCategory == null
        ? const <String>[]
        : [lockedMainCategory!];
  }

  List<String> availableSubCategories(ProductSearchFilter filter) {
    final main = locksMainCategory ? lockedMainCategory : filter.mainCategory;
    if (main == null) return const <String>[];
    return CanonicalCategoryMapper.subCategoriesFor(main);
  }
}
