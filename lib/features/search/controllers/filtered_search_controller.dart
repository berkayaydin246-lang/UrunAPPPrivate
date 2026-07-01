import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

// ── State ─────────────────────────────────────────────────────────────────────

class FilteredSearchState {
  final ProductSearchFilter filter;
  final List<Product> products;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  final int serverOffset;

  const FilteredSearchState({
    this.filter = const ProductSearchFilter(),
    this.products = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.error,
    this.serverOffset = 0,
  });

  bool get hasActiveSearch => filter.hasQuery || filter.hasActiveFilters;
  bool get isInitialLoading => isLoading && products.isEmpty;

  FilteredSearchState copyWith({
    ProductSearchFilter? filter,
    List<Product>? products,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    int? serverOffset,
  }) {
    return FilteredSearchState(
      filter: filter ?? this.filter,
      products: products ?? this.products,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
      serverOffset: serverOffset ?? this.serverOffset,
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class FilteredSearchNotifier extends StateNotifier<FilteredSearchState> {
  final ProductRepository _repo;

  FilteredSearchNotifier(this._repo, {ProductSearchFilter? initialFilter})
    : super(
        FilteredSearchState(
          filter: initialFilter ?? const ProductSearchFilter(),
          isLoading: _shouldAutoFetch(initialFilter),
        ),
      ) {
    if (_shouldAutoFetch(initialFilter)) {
      _fetchGen++;
      _fetchPage(gen: _fetchGen, serverOffset: 0, append: false);
    }
  }

  static bool _shouldAutoFetch(ProductSearchFilter? f) =>
      f != null && (f.hasActiveFilters || f.hasQuery);

  static const _pageSize = 20;

  // Incremented on every new search to discard stale async responses.
  int _fetchGen = 0;

  /// Update only the query string, preserving category/sort/other filters.
  void setQuery(String query) {
    setFilter(state.filter.copyWith(query: query));
  }

  /// Replace the full filter and restart from page 1.
  void setFilter(ProductSearchFilter filter) {
    _fetchGen++;
    state = FilteredSearchState(filter: filter, isLoading: true);
    _fetchPage(gen: _fetchGen, serverOffset: 0, append: false);
  }

  /// Re-run the current filter from scratch (e.g. after a staging approval).
  Future<void> refresh() async {
    _fetchGen++;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      products: const [],
      serverOffset: 0,
    );
    await _fetchPage(gen: _fetchGen, serverOffset: 0, append: false);
  }

  /// Fetch the next page and append to existing results.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    await _fetchPage(
      gen: _fetchGen,
      serverOffset: state.serverOffset,
      append: true,
    );
  }

  Future<void> _fetchPage({
    required int gen,
    required int serverOffset,
    required bool append,
  }) async {
    try {
      final page = await _fetchVisiblePage(
        filter: state.filter,
        serverOffset: serverOffset,
      );

      // Discard if a newer search has started.
      if (gen != _fetchGen || !mounted) return;
      final merged = append
          ? _appendUniqueProducts(state.products, page.results)
          : page.results;
      // Nutrition sorts are applied client-side across all loaded products.
      final sorted = _applyNutritionSort(merged, state.filter.sortOrder);

      state = state.copyWith(
        products: sorted,
        isLoading: false,
        isLoadingMore: false,
        hasMore: page.hasMore,
        serverOffset: page.nextServerOffset,
      );
    } catch (e) {
      if (gen != _fetchGen || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        error: UserMessage.forGeneric(e),
      );
    }
  }

  Future<({List<Product> results, bool hasMore, int nextServerOffset})>
  _fetchVisiblePage({
    required ProductSearchFilter filter,
    required int serverOffset,
  }) async {
    var nextOffset = serverOffset;

    while (true) {
      final (:results, :hasMore) = await _repo.filteredSearch(
        filter,
        pageSize: _pageSize,
        serverOffset: nextOffset,
      );
      nextOffset += results.length;

      // Client-side subcategory pass only for shared-tag subs where the server
      // query alone cannot determine the correct subcategory.  Exact-tag subs
      // (peynir, biskuvi, sos, …) trust the server result entirely.
      var filtered = filter.queryPlan.requiresClientValidation
          ? _applySubCategoryFilter(
              results,
              filter.mainCategory,
              filter.subCategory,
            )
          : results;
      filtered = _applyNutritionFilter(filtered, filter.nutritionFilter);
      filtered = _applyIngredientFilter(filtered, filter.ingredientFilter);

      _debugCategoryQuery(
        filter: filter,
        fetchedCount: results.length,
        resultCount: filtered.length,
      );

      final shouldSkipEmptyPage =
          filtered.isEmpty &&
          hasMore &&
          results.isNotEmpty &&
          _hasClientSideRefinement(filter);
      if (!shouldSkipEmptyPage) {
        return (
          results: filtered,
          hasMore: hasMore,
          nextServerOffset: nextOffset,
        );
      }
    }
  }

  bool _hasClientSideRefinement(ProductSearchFilter filter) {
    return filter.queryPlan.requiresClientValidation ||
        !filter.nutritionFilter.isEmpty ||
        !filter.ingredientFilter.isEmpty;
  }

  List<Product> _appendUniqueProducts(
    List<Product> existing,
    List<Product> nextPage,
  ) {
    if (nextPage.isEmpty) return existing;

    final seenIds = existing.map((product) => product.id).toSet();
    final uniqueNewProducts = <Product>[
      for (final product in nextPage)
        if (seenIds.add(product.id)) product,
    ];

    if (uniqueNewProducts.isEmpty) return existing;
    return [...existing, ...uniqueNewProducts];
  }

  void _debugCategoryQuery({
    required ProductSearchFilter filter,
    required int fetchedCount,
    required int resultCount,
  }) {
    if (!kDebugMode) return;
    if (filter.mainCategory == null) return;
    final plan = filter.queryPlan;
    debugPrint(
      '[category_query] '
      'main=${plan.mainCategoryKey} '
      'sub=${plan.subcategoryKey ?? 'Tümü'} '
      'tags=${plan.categoryTagsAny} '
      'keywords=${plan.searchKeywordsAny} '
      'requiresClientValidation=${plan.requiresClientValidation} '
      'optionalFilterCount=${filter.activeFilterCount} '
      'serverFilter=${plan.hasFilter} '
      'query="${filter.query.trim()}" '
      'fetched=$fetchedCount '
      'visible=$resultCount',
    );
  }

  // ── Sub-category (client-side) ─────────────────────────────────────────────

  List<Product> _applySubCategoryFilter(
    List<Product> products,
    String? mainCategory,
    String? subCategory,
  ) {
    if (subCategory == null) return products;
    return products.where((p) {
      final fallbackMain = CanonicalCategoryMapper.map(
        categoryTags: p.categoryTags,
        name: p.name,
        canonicalCategory: p.canonicalCategory,
        canonicalSubcategory: p.canonicalSubcategory,
      ).main;
      return CanonicalCategoryMapper.matchesSubCategory(
        mainCategory: mainCategory ?? fallbackMain,
        subCategory: subCategory,
        categoryTags: p.categoryTags,
        name: p.name,
        normalizedName: p.normalizedName,
        searchKeywords: p.searchKeywords,
        canonicalCategory: p.canonicalCategory,
        canonicalSubcategory: p.canonicalSubcategory,
      );
    }).toList();
  }

  // ── Nutrition filter (client-side) ─────────────────────────────────────────

  List<Product> _applyNutritionFilter(
    List<Product> products,
    NutritionFilter f,
  ) {
    if (f.isEmpty) return products;
    return products.where((p) {
      final n = p.nutrition;
      if (f.maxEnergyKcal != null) {
        if (n?.energyKcal == null || n!.energyKcal! > f.maxEnergyKcal!) {
          return false;
        }
      }
      if (f.minEnergyKcal != null) {
        if (n?.energyKcal == null || n!.energyKcal! < f.minEnergyKcal!) {
          return false;
        }
      }
      if (f.minProteins != null) {
        if (n?.proteins == null || n!.proteins! < f.minProteins!) return false;
      }
      if (f.maxProteins != null) {
        if (n?.proteins == null || n!.proteins! > f.maxProteins!) return false;
      }
      if (f.maxSugars != null) {
        if (n?.sugars == null || n!.sugars! > f.maxSugars!) return false;
      }
      if (f.minSugars != null) {
        if (n?.sugars == null || n!.sugars! < f.minSugars!) return false;
      }
      if (f.maxFat != null) {
        if (n?.fat == null || n!.fat! > f.maxFat!) return false;
      }
      if (f.minFat != null) {
        if (n?.fat == null || n!.fat! < f.minFat!) return false;
      }
      if (f.maxSaturatedFat != null) {
        if (n?.saturatedFat == null || n!.saturatedFat! > f.maxSaturatedFat!) {
          return false;
        }
      }
      if (f.minSaturatedFat != null) {
        if (n?.saturatedFat == null || n!.saturatedFat! < f.minSaturatedFat!) {
          return false;
        }
      }
      if (f.maxSalt != null) {
        if (n?.salt == null || n!.salt! > f.maxSalt!) return false;
      }
      if (f.minSalt != null) {
        if (n?.salt == null || n!.salt! < f.minSalt!) return false;
      }
      if (f.minFiber != null) {
        if (n?.fiber == null || n!.fiber! < f.minFiber!) return false;
      }
      if (f.maxFiber != null) {
        if (n?.fiber == null || n!.fiber! > f.maxFiber!) return false;
      }
      if (f.maxCarbohydrates != null) {
        if (n?.carbohydrates == null ||
            n!.carbohydrates! > f.maxCarbohydrates!) {
          return false;
        }
      }
      if (f.minCarbohydrates != null) {
        if (n?.carbohydrates == null ||
            n!.carbohydrates! < f.minCarbohydrates!) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // ── Ingredient filter (client-side, conservative) ──────────────────────────

  List<Product> _applyIngredientFilter(
    List<Product> products,
    IngredientFilterConfig f,
  ) {
    if (f.isEmpty) return products;
    return products.where((p) {
      final text = (p.ingredientsText ?? '').toLowerCase();
      // Conservative: no ingredients text → cannot verify → exclude.
      if (text.trim().isEmpty) return false;
      if (f.excludePalmOil && _hasPalmOil(text)) return false;
      if (f.excludePreservatives && _hasPreservatives(text)) return false;
      if (f.excludeArtificialColorants && _hasColorants(text)) return false;
      if (f.excludeArtificialSweeteners && _hasSweeteners(text)) return false;
      if (f.excludeAddedSugar && _hasAddedSugar(text)) return false;
      return true;
    }).toList();
  }

  static bool _hasPalmOil(String t) =>
      t.contains('palm') || t.contains('palmiye');

  static bool _hasPreservatives(String t) =>
      t.contains('koruyucu') ||
      t.contains('benzoat') ||
      t.contains('sorbat') ||
      t.contains('nitrit') ||
      t.contains('nitrat') ||
      t.contains('sülfür dioksit') ||
      t.contains('sulfur dioxide') ||
      t.contains('e211') ||
      t.contains('e202') ||
      t.contains('e250');

  static bool _hasColorants(String t) =>
      t.contains('renklendirici') ||
      t.contains('boyar madde') ||
      t.contains('e102') ||
      t.contains('e110') ||
      t.contains('e122') ||
      t.contains('e129') ||
      t.contains('e133');

  static bool _hasSweeteners(String t) =>
      t.contains('tatlandırıcı') ||
      t.contains('aspartam') ||
      t.contains('aspartame') ||
      t.contains('asesülfam') ||
      t.contains('acesulfame') ||
      t.contains('sukraloz') ||
      t.contains('sucralose') ||
      t.contains('stevia') ||
      t.contains('sorbitol') ||
      t.contains('maltitol') ||
      t.contains('sakarin') ||
      t.contains('saccharin') ||
      t.contains('siklamat') ||
      t.contains('e951') ||
      t.contains('e950') ||
      t.contains('e955');

  static bool _hasAddedSugar(String t) =>
      t.contains('şeker') ||
      t.contains('seker') ||
      t.contains('glikoz şurubu') ||
      t.contains('fruktoz şurubu') ||
      t.contains('mısır şurubu') ||
      t.contains('invert şeker') ||
      t.contains('dekstroz') ||
      t.contains('sakkaroz') ||
      t.contains('şeker şurubu') ||
      t.contains('glukoz') ||
      t.contains('fruktoz');

  // ── Nutrition sort (client-side) ───────────────────────────────────────────

  List<Product> _applyNutritionSort(
    List<Product> products,
    SearchSortOrder sort,
  ) {
    switch (sort) {
      case SearchSortOrder.relevance:
      case SearchSortOrder.nameAsc:
      case SearchSortOrder.nameDesc:
      case SearchSortOrder.brandAsc:
      case SearchSortOrder.brandDesc:
      case SearchSortOrder.newestFirst:
        return products; // server already ordered these
      case SearchSortOrder.energyAsc:
        return _byNutrition(products, (n) => n.energyKcal, asc: true);
      case SearchSortOrder.energyDesc:
        return _byNutrition(products, (n) => n.energyKcal, asc: false);
      case SearchSortOrder.proteinsAsc:
        return _byNutrition(products, (n) => n.proteins, asc: true);
      case SearchSortOrder.proteinsDesc:
        return _byNutrition(products, (n) => n.proteins, asc: false);
      case SearchSortOrder.sugarsAsc:
        return _byNutrition(products, (n) => n.sugars, asc: true);
      case SearchSortOrder.sugarsDesc:
        return _byNutrition(products, (n) => n.sugars, asc: false);
      case SearchSortOrder.fatAsc:
        return _byNutrition(products, (n) => n.fat, asc: true);
      case SearchSortOrder.fatDesc:
        return _byNutrition(products, (n) => n.fat, asc: false);
      case SearchSortOrder.saturatedFatAsc:
        return _byNutrition(products, (n) => n.saturatedFat, asc: true);
      case SearchSortOrder.saturatedFatDesc:
        return _byNutrition(products, (n) => n.saturatedFat, asc: false);
      case SearchSortOrder.saltAsc:
        return _byNutrition(products, (n) => n.salt, asc: true);
      case SearchSortOrder.saltDesc:
        return _byNutrition(products, (n) => n.salt, asc: false);
      case SearchSortOrder.fiberAsc:
        return _byNutrition(products, (n) => n.fiber, asc: true);
      case SearchSortOrder.fiberDesc:
        return _byNutrition(products, (n) => n.fiber, asc: false);
    }
  }

  List<Product> _byNutrition(
    List<Product> products,
    double? Function(NutritionData) getter, {
    required bool asc,
  }) {
    final list = [...products];
    list.sort((a, b) {
      final av = a.nutrition != null ? getter(a.nutrition!) : null;
      final bv = b.nutrition != null ? getter(b.nutrition!) : null;
      if (av == null && bv == null) return 0;
      if (av == null) return 1; // missing values go to end
      if (bv == null) return -1;
      return asc ? av.compareTo(bv) : bv.compareTo(av);
    });
    return list;
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final filteredSearchProvider =
    StateNotifierProvider<FilteredSearchNotifier, FilteredSearchState>(
      (ref) => FilteredSearchNotifier(const ProductRepository()),
    );
