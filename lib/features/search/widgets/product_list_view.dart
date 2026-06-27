import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/models/product_list_context.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/widgets/product_card.dart';

// ── Nutrition filter specs (public — tests verify threshold values) ────────────

class NutrientFilterSpec {
  final String key;
  final String label;
  final String unit;
  final String comparator;
  final List<double> thresholds;

  const NutrientFilterSpec({
    required this.key,
    required this.label,
    required this.unit,
    required this.comparator,
    required this.thresholds,
  });

  double? getValue(NutritionFilter n) {
    switch (key) {
      case 'energy':
        return n.maxEnergyKcal;
      case 'protein':
        return n.minProteins;
      case 'sugar':
        return n.maxSugars;
      case 'fat':
        return n.maxFat;
      case 'salt':
        return n.maxSalt;
      case 'fiber':
        return n.minFiber;
      default:
        return null;
    }
  }

  NutritionFilter updateFilter(NutritionFilter n, double? v) {
    switch (key) {
      case 'energy':
        return n.copyWith(maxEnergyKcal: v);
      case 'protein':
        return n.copyWith(minProteins: v);
      case 'sugar':
        return n.copyWith(maxSugars: v);
      case 'fat':
        return n.copyWith(maxFat: v);
      case 'salt':
        return n.copyWith(maxSalt: v);
      case 'fiber':
        return n.copyWith(minFiber: v);
      default:
        return n;
    }
  }
}

const kNutrientFilterSpecs = <NutrientFilterSpec>[
  NutrientFilterSpec(
    key: 'energy',
    label: 'Kalori',
    unit: 'kcal',
    comparator: '≤',
    thresholds: [100, 200, 300, 400, 500],
  ),
  NutrientFilterSpec(
    key: 'protein',
    label: 'Protein',
    unit: 'g',
    comparator: '≥',
    thresholds: [5, 10, 15, 20, 25],
  ),
  NutrientFilterSpec(
    key: 'sugar',
    label: 'Şeker',
    unit: 'g',
    comparator: '≤',
    thresholds: [2, 5, 10, 15],
  ),
  NutrientFilterSpec(
    key: 'fat',
    label: 'Yağ',
    unit: 'g',
    comparator: '≤',
    thresholds: [3, 5, 10, 20],
  ),
  NutrientFilterSpec(
    key: 'salt',
    label: 'Tuz',
    unit: 'g',
    comparator: '≤',
    thresholds: [0.1, 0.3, 0.5, 1.0],
  ),
  NutrientFilterSpec(
    key: 'fiber',
    label: 'Lif',
    unit: 'g',
    comparator: '≥',
    thresholds: [2, 3, 5, 7],
  ),
];

// ── Private bidirectional nutrient specs (for the add-rule UI) ────────────────

class _BidiNutrientSpec {
  final String key;
  final String label;
  final String unit;
  final List<double> maxThresholds;
  final List<double> minThresholds;

  const _BidiNutrientSpec({
    required this.key,
    required this.label,
    required this.unit,
    required this.maxThresholds,
    required this.minThresholds,
  });

  List<double> thresholdsFor(bool isMax) =>
      isMax ? maxThresholds : minThresholds;
}

const _kBidiSpecs = <_BidiNutrientSpec>[
  _BidiNutrientSpec(
    key: 'energy',
    label: 'Kalori',
    unit: 'kcal',
    maxThresholds: [50, 100, 150, 200, 300, 400, 500],
    minThresholds: [100, 200, 300, 400, 500],
  ),
  _BidiNutrientSpec(
    key: 'protein',
    label: 'Protein',
    unit: 'g',
    maxThresholds: [5, 10, 15, 20, 25],
    minThresholds: [5, 10, 15, 20, 25],
  ),
  _BidiNutrientSpec(
    key: 'sugar',
    label: 'Şeker',
    unit: 'g',
    maxThresholds: [2, 5, 10, 15, 20],
    minThresholds: [5, 10, 15, 20],
  ),
  _BidiNutrientSpec(
    key: 'fat',
    label: 'Yağ',
    unit: 'g',
    maxThresholds: [3, 5, 10, 15, 20],
    minThresholds: [5, 10, 15, 20],
  ),
  _BidiNutrientSpec(
    key: 'saturatedFat',
    label: 'Doymuş Yağ',
    unit: 'g',
    maxThresholds: [1, 2, 3, 5, 7],
    minThresholds: [1, 2, 3, 5],
  ),
  _BidiNutrientSpec(
    key: 'salt',
    label: 'Tuz',
    unit: 'g',
    maxThresholds: [0.1, 0.3, 0.5, 1.0, 1.5],
    minThresholds: [0.3, 0.5, 1.0, 1.5],
  ),
  _BidiNutrientSpec(
    key: 'fiber',
    label: 'Lif',
    unit: 'g',
    maxThresholds: [2, 3, 5, 7],
    minThresholds: [2, 3, 5, 7, 10],
  ),
  _BidiNutrientSpec(
    key: 'carbs',
    label: 'Karbonhidrat',
    unit: 'g',
    maxThresholds: [5, 10, 20, 30, 50],
    minThresholds: [30, 50, 70, 100],
  ),
];

// Nutrition rule model for active-rules display.
class _NutritionRule {
  final String key;
  final bool isMax;
  final double value;

  const _NutritionRule(this.key, this.isMax, this.value);

  String format() {
    final spec = _kBidiSpecs.firstWhere(
      (s) => s.key == key,
      orElse: () => _BidiNutrientSpec(
        key: key,
        label: key,
        unit: '',
        maxThresholds: const [],
        minThresholds: const [],
      ),
    );
    final comparator = isMax ? 'En fazla' : 'En az';
    final t = value == value.truncateToDouble() ? '${value.toInt()}' : '$value';
    return '${spec.label} $comparator $t ${spec.unit}';
  }
}

List<_NutritionRule> _activeRules(NutritionFilter n) {
  return [
    if (n.maxEnergyKcal != null)
      _NutritionRule('energy', true, n.maxEnergyKcal!),
    if (n.minEnergyKcal != null)
      _NutritionRule('energy', false, n.minEnergyKcal!),
    if (n.maxProteins != null) _NutritionRule('protein', true, n.maxProteins!),
    if (n.minProteins != null) _NutritionRule('protein', false, n.minProteins!),
    if (n.maxSugars != null) _NutritionRule('sugar', true, n.maxSugars!),
    if (n.minSugars != null) _NutritionRule('sugar', false, n.minSugars!),
    if (n.maxFat != null) _NutritionRule('fat', true, n.maxFat!),
    if (n.minFat != null) _NutritionRule('fat', false, n.minFat!),
    if (n.maxSaturatedFat != null)
      _NutritionRule('saturatedFat', true, n.maxSaturatedFat!),
    if (n.minSaturatedFat != null)
      _NutritionRule('saturatedFat', false, n.minSaturatedFat!),
    if (n.maxSalt != null) _NutritionRule('salt', true, n.maxSalt!),
    if (n.minSalt != null) _NutritionRule('salt', false, n.minSalt!),
    if (n.maxFiber != null) _NutritionRule('fiber', true, n.maxFiber!),
    if (n.minFiber != null) _NutritionRule('fiber', false, n.minFiber!),
    if (n.maxCarbohydrates != null)
      _NutritionRule('carbs', true, n.maxCarbohydrates!),
    if (n.minCarbohydrates != null)
      _NutritionRule('carbs', false, n.minCarbohydrates!),
  ];
}

NutritionFilter _setRule(NutritionFilter n, String key, bool isMax, double? v) {
  switch ('$key:${isMax ? 'max' : 'min'}') {
    case 'energy:max':
      return n.copyWith(maxEnergyKcal: v);
    case 'energy:min':
      return n.copyWith(minEnergyKcal: v);
    case 'protein:max':
      return n.copyWith(maxProteins: v);
    case 'protein:min':
      return n.copyWith(minProteins: v);
    case 'sugar:max':
      return n.copyWith(maxSugars: v);
    case 'sugar:min':
      return n.copyWith(minSugars: v);
    case 'fat:max':
      return n.copyWith(maxFat: v);
    case 'fat:min':
      return n.copyWith(minFat: v);
    case 'saturatedFat:max':
      return n.copyWith(maxSaturatedFat: v);
    case 'saturatedFat:min':
      return n.copyWith(minSaturatedFat: v);
    case 'salt:max':
      return n.copyWith(maxSalt: v);
    case 'salt:min':
      return n.copyWith(minSalt: v);
    case 'fiber:max':
      return n.copyWith(maxFiber: v);
    case 'fiber:min':
      return n.copyWith(minFiber: v);
    case 'carbs:max':
      return n.copyWith(maxCarbohydrates: v);
    case 'carbs:min':
      return n.copyWith(minCarbohydrates: v);
    default:
      return n;
  }
}

// ── ProductListView ───────────────────────────────────────────────────────────

class ProductListView extends ConsumerStatefulWidget {
  final String? searchHint;
  final Widget? idleContent;
  final ProductListContext listContext;
  final CategoryThemeData? categoryTheme;
  final bool simpleCards;
  final bool showFilterButton;

  const ProductListView({
    super.key,
    this.searchHint,
    this.idleContent,
    this.listContext = const ProductListContext.globalSearch(),
    this.categoryTheme,
    this.simpleCards = false,
    this.showFilterButton = true,
  });

  @override
  ConsumerState<ProductListView> createState() => _ProductListViewState();
}

class _ProductListViewState extends ConsumerState<ProductListView> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _warmedPreviewKeys = <String>{};
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final q = ref.read(filteredSearchProvider).filter.query;
    if (q.isNotEmpty) _textController.text = q;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      ref.read(filteredSearchProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      final current = ref.read(filteredSearchProvider).filter;
      ref
          .read(filteredSearchProvider.notifier)
          .setFilter(current.copyWith(query: value));
    });
    setState(() {});
  }

  void _clearSearch() {
    _textController.clear();
    _focusNode.unfocus();
    _debounce?.cancel();
    final current = ref.read(filteredSearchProvider).filter;
    ref
        .read(filteredSearchProvider.notifier)
        .setFilter(current.copyWith(query: ''));
    setState(() {});
  }

  Future<void> _openFilterSheet() async {
    final current = ref.read(filteredSearchProvider).filter;
    final facetFilter = widget.listContext.normalizeFilter(
      const ProductSearchFilter(),
    );
    final result = await showModalBottomSheet<ProductSearchFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductFilterSheet(
        initialFilter: current,
        listContext: widget.listContext,
        categoryTheme: widget.categoryTheme,
        brandFacetsLoader: () =>
            const ProductRepository().getBrandFacets(facetFilter),
      ),
    );
    if (result != null && mounted) {
      final withQuery = widget.listContext.normalizeFilter(
        result.copyWith(query: _textController.text),
      );
      ref.read(filteredSearchProvider.notifier).setFilter(withQuery);
    }
  }

  void _removeFilterChip(ProductSearchFilter updated) {
    final withQuery = widget.listContext.normalizeFilter(
      updated.copyWith(query: _textController.text),
    );
    ref.read(filteredSearchProvider.notifier).setFilter(withQuery);
  }

  void _openProduct(Product product) => context.push('/product/${product.id}');

  void _schedulePreviewWarm(List<Product> products) {
    final items = <ProductThumbnailPrecacheItem>[];

    for (final product in products) {
      final imageUrl = product.imageUrl?.trim();
      if (imageUrl == null || imageUrl.isEmpty) continue;

      final cacheKey = productThumbnailPreviewCacheKey(
        productId: product.id,
        imageUrl: imageUrl,
      );
      if (!_warmedPreviewKeys.add(cacheKey)) continue;

      items.add(
        ProductThumbnailPrecacheItem(productId: product.id, imageUrl: imageUrl),
      );
    }

    if (items.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      warmProductThumbnailPreviews(context, items);
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(filteredSearchProvider);
    _schedulePreviewWarm(searchState.products);
    final filter = searchState.filter;
    final pageTheme = widget.categoryTheme;
    final pageAccent = pageTheme?.selectedChipColor;
    final textFieldFill = AppColors.surface;
    final searchBorderColor = pageTheme?.searchBorderColor ?? AppColors.border;
    final searchIconColor = pageAccent ?? AppColors.accent;

    // On category pages the sub/main chips live in _SubCategoryQuickFilter
    // above this widget; only show the chip row for non-category filters.
    final hasActiveChips = widget.listContext.locksMainCategory
        ? (filter.brands.isNotEmpty ||
              !filter.nutritionFilter.isEmpty ||
              !filter.ingredientFilter.isEmpty ||
              filter.sortOrder != SearchSortOrder.relevance)
        : (widget.listContext.visibleActiveFilterCount(filter) > 0 ||
              widget.listContext.hasLockedCategory);

    final showResults =
        _textController.text.trim().length >= 2 || filter.hasActiveFilters;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            widget.showFilterButton ? 12 : 28,
            10,
            widget.showFilterButton ? 12 : 28,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.input),
                    boxShadow: AppShadows.soft(pageAccent ?? AppColors.accent),
                  ),
                  child: TextField(
                    key: ValueKey(
                      'product-search-field-${pageTheme?.mainCategory ?? 'global'}',
                    ),
                    controller: _textController,
                    focusNode: _focusNode,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText:
                          widget.searchHint ?? 'Ürün, marka veya barkod ara',
                      filled: true,
                      fillColor: textFieldFill,
                      prefixIcon: Icon(Icons.search, color: searchIconColor),
                      suffixIcon: _textController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: searchIconColor),
                              onPressed: _clearSearch,
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide(color: searchBorderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide(color: searchBorderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        borderSide: BorderSide(
                          color:
                              pageTheme?.searchBorderColor ?? AppColors.accent,
                          width: 1.6,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.showFilterButton) ...[
                const SizedBox(width: 8),
                _FilterButton(
                  activeCount: widget.listContext.visibleActiveFilterCount(
                    filter,
                  ),
                  categoryTheme: widget.categoryTheme,
                  onTap: _openFilterSheet,
                ),
              ],
            ],
          ),
        ),
        if (hasActiveChips)
          _ActiveFilterChips(
            filter: filter,
            listContext: widget.listContext,
            categoryTheme: widget.categoryTheme,
            onRemove: _removeFilterChip,
          ),
        const SizedBox(height: 4),
        Expanded(
          child: showResults || widget.idleContent == null
              ? _ResultsView(
                  searchState: searchState,
                  scrollController: _scrollController,
                  categoryTheme: widget.categoryTheme,
                  onProductTap: _openProduct,
                  simpleCards: widget.simpleCards,
                )
              : widget.idleContent!,
        ),
      ],
    );

    final backgroundColor = pageTheme == null
        ? null
        : Color.lerp(Colors.white, pageTheme.primaryColor, 0.035)!;
    if (backgroundColor == null) return content;
    return ColoredBox(
      key: const ValueKey('category-product-results-background'),
      color: backgroundColor,
      child: content,
    );
  }
}

// ── Filter button ─────────────────────────────────────────────────────────────

class _FilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;
  final CategoryThemeData? categoryTheme;

  const _FilterButton({
    required this.activeCount,
    required this.onTap,
    this.categoryTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = categoryTheme?.filterButtonColor ?? AppColors.accent;
    final hasActive = activeCount > 0;
    return Badge(
      isLabelVisible: hasActive,
      label: Text('$activeCount'),
      backgroundColor: categoryTheme?.badgeColor ?? theme.colorScheme.primary,
      textColor:
          categoryTheme?.selectedChipTextColor ?? theme.colorScheme.onPrimary,
      child: IconButton.outlined(
        key: ValueKey(
          'product-filter-button-${categoryTheme?.mainCategory ?? 'global'}',
        ),
        onPressed: onTap,
        icon: Icon(
          Icons.tune,
          color: hasActive || categoryTheme != null
              ? accent
              : accent.withValues(alpha: 0.65),
        ),
        style: IconButton.styleFrom(
          backgroundColor:
              categoryTheme?.chipTint.withValues(alpha: 0.48) ??
              AppColors.surface,
          side: BorderSide(
            color: categoryTheme != null || hasActive
                ? accent
                : AppColors.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
        ),
      ),
    );
  }
}

// ── Active filter chips ───────────────────────────────────────────────────────

class _ActiveFilterChips extends StatelessWidget {
  final ProductSearchFilter filter;
  final ProductListContext listContext;
  final CategoryThemeData? categoryTheme;
  final ValueChanged<ProductSearchFilter> onRemove;

  const _ActiveFilterChips({
    required this.filter,
    required this.listContext,
    required this.categoryTheme,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    // Category chips: only on non-category pages.
    // On category pages, _SubCategoryQuickFilter (in CategoryProductsPage) owns
    // the main/sub selection — no duplicate chips here.
    if (!listContext.locksMainCategory) {
      if (listContext.locksSubCategory && filter.mainCategory != null) {
        chips.add(
          _LockedChip(
            label: filter.mainCategory!,
            icon: Icons.push_pin_outlined,
            categoryTheme: categoryTheme,
          ),
        );
        if (filter.subCategory != null) {
          chips.add(
            _Chip(
              label: filter.subCategory!,
              categoryTheme: categoryTheme,
              onRemove: () => onRemove(filter.copyWith(subCategory: null)),
            ),
          );
        }
      } else if (filter.mainCategory != null) {
        chips.add(
          _Chip(
            label: filter.subCategory ?? filter.mainCategory!,
            categoryTheme: categoryTheme,
            onRemove: () => onRemove(filter.clearCategory()),
          ),
        );
      }
    }

    for (final brand in filter.brands) {
      chips.add(
        _Chip(
          label: brand,
          categoryTheme: categoryTheme,
          onRemove: () => onRemove(
            filter.copyWith(
              brands: filter.brands.where((b) => b != brand).toList(),
            ),
          ),
        ),
      );
    }

    if (!filter.nutritionFilter.isEmpty) {
      chips.add(
        _Chip(
          label: 'Beslenme filtresi',
          categoryTheme: categoryTheme,
          onRemove: () => onRemove(
            filter.copyWith(nutritionFilter: const NutritionFilter()),
          ),
        ),
      );
    }

    if (!filter.ingredientFilter.isEmpty) {
      chips.add(
        _Chip(
          label: 'İçerik filtresi',
          categoryTheme: categoryTheme,
          onRemove: () => onRemove(
            filter.copyWith(ingredientFilter: const IngredientFilterConfig()),
          ),
        ),
      );
    }

    if (filter.sortOrder != SearchSortOrder.relevance) {
      chips.add(
        _Chip(
          label: filter.sortOrder.label,
          categoryTheme: categoryTheme,
          onRemove: () =>
              onRemove(filter.copyWith(sortOrder: SearchSortOrder.relevance)),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        children: chips,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final CategoryThemeData? categoryTheme;
  final VoidCallback onRemove;
  const _Chip({
    required this.label,
    required this.categoryTheme,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final chipBg =
        categoryTheme?.chipTint.withValues(alpha: 0.9) ?? AppColors.surfaceSoft;
    final chipBorder =
        categoryTheme?.borderColor.withValues(alpha: 0.88) ?? AppColors.border;
    final chipText = categoryTheme?.badgeColor ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        backgroundColor: chipBg,
        side: BorderSide(color: chipBorder),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: chipText,
            fontWeight: FontWeight.w600,
          ),
        ),
        deleteIcon: Icon(
          Icons.close,
          size: 14,
          color: chipText.withValues(alpha: 0.82),
        ),
        onDeleted: onRemove,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _LockedChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final CategoryThemeData? categoryTheme;

  const _LockedChip({
    required this.label,
    required this.icon,
    required this.categoryTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = categoryTheme?.selectedChipColor ?? AppColors.accent;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        avatar: Icon(icon, size: 16, color: accent),
        label: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: accent,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor:
            categoryTheme?.chipTint.withValues(alpha: 0.9) ??
            AppColors.surfaceSoft,
        side: BorderSide(
          color:
              categoryTheme?.borderColor.withValues(alpha: 0.92) ??
              AppColors.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ── Results view ──────────────────────────────────────────────────────────────

class _ResultsView extends StatelessWidget {
  final FilteredSearchState searchState;
  final ScrollController scrollController;
  final CategoryThemeData? categoryTheme;
  final ValueChanged<Product> onProductTap;
  final bool simpleCards;

  const _ResultsView({
    required this.searchState,
    required this.scrollController,
    required this.categoryTheme,
    required this.onProductTap,
    this.simpleCards = false,
  });

  @override
  Widget build(BuildContext context) {
    if (searchState.isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchState.error != null && searchState.products.isEmpty) {
      return _ErrorView(error: searchState.error!);
    }

    if (searchState.products.isEmpty) {
      return _EmptyView(
        filter: searchState.filter,
        categoryTheme: categoryTheme,
      );
    }

    final products = searchState.products;
    final sortOrder = searchState.filter.isNutritionSort
        ? searchState.filter.sortOrder
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            '${products.length}${searchState.hasMore ? '+' : ''} ürün',
            key: ValueKey(
              'product-result-count-${categoryTheme?.mainCategory ?? 'global'}',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 14,
              color:
                  categoryTheme?.selectedChipColor ??
                  Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: simpleCards
              ? _CompactProductGrid(
                  products: products,
                  searchState: searchState,
                  scrollController: scrollController,
                  sortOrder: sortOrder,
                  categoryTheme: categoryTheme,
                  onProductTap: onProductTap,
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: products.length + 1,
                  itemBuilder: (context, i) {
                    if (i == products.length) {
                      return _LoadMoreFooter(state: searchState);
                    }
                    return ProductCard(
                      key: ValueKey('product-${products[i].id}'),
                      product: products[i],
                      sortOrder: sortOrder,
                      categoryTheme: categoryTheme,
                      onTap: () => onProductTap(products[i]),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CompactProductGrid extends StatelessWidget {
  final List<Product> products;
  final FilteredSearchState searchState;
  final ScrollController scrollController;
  final SearchSortOrder? sortOrder;
  final CategoryThemeData? categoryTheme;
  final ValueChanged<Product> onProductTap;

  const _CompactProductGrid({
    required this.products,
    required this.searchState,
    required this.scrollController,
    required this.sortOrder,
    required this.categoryTheme,
    required this.onProductTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isVeryNarrow = constraints.maxWidth < 340;
        final horizontalPadding = isVeryNarrow ? 12.0 : 16.0;
        final crossAxisSpacing = isVeryNarrow ? 8.0 : 10.0;
        const mainAxisSpacing = 16.0;
        final usableWidth =
            constraints.maxWidth - horizontalPadding * 2 - crossAxisSpacing * 2;
        final itemWidth = usableWidth / 3;
        final itemHeight = compactProductTileHeight(itemWidth);

        return CustomScrollView(
          key: const ValueKey('category-product-grid-scroll'),
          controller: scrollController,
          cacheExtent: 1200,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                2,
                horizontalPadding,
                0,
              ),
              sliver: SliverGrid(
                key: const ValueKey('category-product-grid'),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: crossAxisSpacing,
                  mainAxisSpacing: mainAxisSpacing,
                  mainAxisExtent: itemHeight,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final product = products[i];
                    return ProductCard(
                      key: ValueKey('product-${product.id}'),
                      product: product,
                      sortOrder: sortOrder,
                      categoryTheme: categoryTheme,
                      simpleMode: true,
                      onTap: () => onProductTap(product),
                    );
                  },
                  childCount: products.length,
                  findChildIndexCallback: (key) =>
                      _findProductChildIndex(key, products),
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                ),
              ),
            ),
            SliverToBoxAdapter(child: _LoadMoreFooter(state: searchState)),
          ],
        );
      },
    );
  }
}

int? _findProductChildIndex(Key key, List<Product> products) {
  if (key is! ValueKey<String>) return null;
  const prefix = 'product-';
  final value = key.value;
  if (!value.startsWith(prefix)) return null;
  final productId = value.substring(prefix.length);
  final index = products.indexWhere((product) => product.id == productId);
  return index == -1 ? null : index;
}

class _LoadMoreFooter extends StatelessWidget {
  final FilteredSearchState state;
  const _LoadMoreFooter({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return const SizedBox(height: 24);
  }
}

class _EmptyView extends StatelessWidget {
  final ProductSearchFilter filter;
  final CategoryThemeData? categoryTheme;

  const _EmptyView({required this.filter, required this.categoryTheme});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.search_off,
            size: 56,
            color:
                categoryTheme?.primaryColor.withValues(alpha: 0.42) ??
                theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Sonuç bulunamadı',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            filter.hasQuery
                ? '"${filter.query}" için onaylı veritabanında sonuç yok.'
                : 'Seçili filtreler için ürün bulunamadı.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Barkod Tara'),
              onPressed: () => context.push('/barcode'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('İçindekileri Fotoğrafla'),
              onPressed: () => context.push('/ocr'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            const Text('Arama sırasında hata oluştu.'),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── ProductFilterSheet ────────────────────────────────────────────────────────

class ProductFilterSheet extends StatefulWidget {
  final ProductSearchFilter initialFilter;
  final ProductListContext listContext;
  final CategoryThemeData? categoryTheme;
  final Future<List<String>> Function()? brandFacetsLoader;

  const ProductFilterSheet({
    super.key,
    required this.initialFilter,
    required this.listContext,
    this.categoryTheme,
    this.brandFacetsLoader,
  });

  @override
  State<ProductFilterSheet> createState() => _ProductFilterSheetState();
}

class _ProductFilterSheetState extends State<ProductFilterSheet> {
  late ProductSearchFilter _filter;
  List<String>? _availableBrands;
  final _brandSearchController = TextEditingController();
  String _brandSearchText = '';
  bool _showAllBrands = false;

  @override
  void initState() {
    super.initState();
    _filter = widget.listContext.normalizeFilter(widget.initialFilter);
    if (widget.brandFacetsLoader != null) {
      _loadBrands();
    } else {
      _availableBrands = const [];
    }
  }

  @override
  void dispose() {
    _brandSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadBrands() async {
    try {
      final brands = await widget.brandFacetsLoader!();
      if (mounted) setState(() => _availableBrands = brands);
    } catch (_) {
      if (mounted) setState(() => _availableBrands = const []);
    }
  }

  void _toggleBrand(String brand) {
    final current = List<String>.from(_filter.brands);
    if (current.contains(brand)) {
      current.remove(brand);
    } else {
      current.add(brand);
    }
    setState(() => _filter = _filter.copyWith(brands: current));
  }

  void _apply() => Navigator.of(context).pop(_filter);

  void _clear() {
    _brandSearchController.clear();
    setState(() {
      _brandSearchText = '';
      _showAllBrands = false;
      _filter = widget.listContext.normalizeFilter(
        _filter.copyWith(
          brands: const [],
          nutritionFilter: const NutritionFilter(),
          ingredientFilter: const IngredientFilterConfig(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.categoryTheme?.selectedChipColor ?? AppColors.primary;
    const sheetFill = AppColors.surface;
    final outline =
        widget.categoryTheme?.borderColor.withValues(alpha: 0.9) ??
        AppColors.border;
    final containerTint =
        widget.categoryTheme?.cardTint.withValues(alpha: 0.34) ??
        AppColors.surfaceSoft;
    final activeCount = widget.listContext.visibleActiveFilterCount(_filter);
    final viewInsets = MediaQuery.viewInsetsOf(context);

    // On category pages (locksMainCategory), hide the Category section because
    // the chip row in CategoryProductsPage already provides that control.
    final showCategorySection = !widget.listContext.locksMainCategory;
    final localTheme = theme.copyWith(
      chipTheme: theme.chipTheme.copyWith(
        backgroundColor:
            widget.categoryTheme?.chipTint.withValues(alpha: 0.46) ??
            AppColors.surfaceSoft,
        selectedColor:
            widget.categoryTheme?.selectedChipColor ??
            theme.chipTheme.selectedColor,
        side: BorderSide(color: outline),
        labelStyle: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: theme.textTheme.bodySmall?.copyWith(
          color:
              widget.categoryTheme?.selectedChipTextColor ??
              theme.colorScheme.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            widget.categoryTheme?.backgroundTint.withValues(alpha: 0.62) ??
            AppColors.surfaceSoft,
        labelStyle: TextStyle(color: accent),
        prefixIconColor: accent.withValues(alpha: 0.78),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: outline),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.white;
        }),
        side: BorderSide(color: outline),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor:
              widget.categoryTheme?.selectedChipTextColor ??
              theme.colorScheme.onPrimary,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.84,
        minChildSize: 0.52,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollCtrl) => Theme(
          data: localTheme,
          child: Material(
            color: sheetFill,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: outline,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Filtrele ve sırala',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (activeCount > 0)
                            _StatusPill(
                              label: '$activeCount aktif',
                              categoryTheme: widget.categoryTheme,
                            ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _clear,
                            child: const Text('Temizle'),
                          ),
                        ],
                      ),
                      if (widget.listContext.hasLockedCategory) ...[
                        const SizedBox(height: 12),
                        _ContextBanner(
                          listContext: widget.listContext,
                          categoryTheme: widget.categoryTheme,
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, color: outline.withValues(alpha: 0.8)),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _SectionCard(
                        title: 'Sıralama',
                        subtitle: 'Sonuçların görünüm sırasını belirleyin.',
                        categoryTheme: widget.categoryTheme,
                        backgroundColor: containerTint,
                        child: _SortSection(
                          current: _filter.sortOrder,
                          onChanged: (s) => setState(
                            () => _filter = _filter.copyWith(sortOrder: s),
                          ),
                        ),
                      ),
                      if (showCategorySection) ...[
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: 'Kategori',
                          subtitle: widget.listContext.canChangeMainCategory
                              ? 'Ana ve alt kategorileri seçin.'
                              : 'Sayfa bağlamı korunur; alt kategori ve diğer filtreler serbesttir.',
                          categoryTheme: widget.categoryTheme,
                          backgroundColor: containerTint,
                          child: _CategorySection(
                            listContext: widget.listContext,
                            filter: _filter,
                            onMainChanged: (main) => setState(() {
                              _filter = widget.listContext.normalizeFilter(
                                _filter.copyWith(
                                  mainCategory: main,
                                  subCategory: null,
                                ),
                              );
                            }),
                            onSubChanged: (sub) => setState(() {
                              _filter = widget.listContext.normalizeFilter(
                                _filter.copyWith(subCategory: sub),
                              );
                            }),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Marka',
                        subtitle: _availableBrands == null
                            ? 'Markalar yükleniyor…'
                            : _availableBrands!.isEmpty
                            ? 'Bu kategoride marka filtresi uygulanamıyor.'
                            : 'Birden fazla marka seçilebilir.',
                        categoryTheme: widget.categoryTheme,
                        backgroundColor: containerTint,
                        child: _BrandSection(
                          availableBrands: _availableBrands,
                          selectedBrands: _filter.brands,
                          searchController: _brandSearchController,
                          searchText: _brandSearchText,
                          showAll: _showAllBrands,
                          onSearchChanged: (t) =>
                              setState(() => _brandSearchText = t),
                          onBrandToggled: _toggleBrand,
                          onToggleShowAll: () =>
                              setState(() => _showAllBrands = !_showAllBrands),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'Beslenme filtreleri',
                        subtitle: 'Makro ve besin eşiklerine göre süzün.',
                        categoryTheme: widget.categoryTheme,
                        backgroundColor: containerTint,
                        child: _NutritionSection(
                          nutrition: _filter.nutritionFilter,
                          onChanged: (n) => setState(
                            () =>
                                _filter = _filter.copyWith(nutritionFilter: n),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionCard(
                        title: 'İçerik filtreleri',
                        subtitle: 'İstenmeyen içerikleri dışarıda bırakın.',
                        categoryTheme: widget.categoryTheme,
                        backgroundColor: containerTint,
                        child: _IngredientSection(
                          ingredient: _filter.ingredientFilter,
                          onChanged: (i) => setState(
                            () =>
                                _filter = _filter.copyWith(ingredientFilter: i),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _SheetFooter(
                  activeCount: activeCount,
                  onApply: _apply,
                  categoryTheme: widget.categoryTheme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section helpers ───────────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  final String label;
  final CategoryThemeData? categoryTheme;

  const _StatusPill({required this.label, required this.categoryTheme});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: categoryTheme?.badgeColor ?? AppColors.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: categoryTheme?.selectedChipTextColor ?? Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ContextBanner extends StatelessWidget {
  final ProductListContext listContext;
  final CategoryThemeData? categoryTheme;

  const _ContextBanner({
    required this.listContext,
    required this.categoryTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mainLabel = listContext.lockedMainCategory;
    if (mainLabel == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            categoryTheme?.chipTint.withValues(alpha: 0.46) ??
            AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              categoryTheme?.borderColor.withValues(alpha: 0.78) ??
              AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.push_pin_outlined,
            size: 16,
            color: categoryTheme?.filterButtonColor ?? AppColors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            mainLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: categoryTheme?.badgeColor ?? theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'sayfası',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final CategoryThemeData? categoryTheme;
  final Color backgroundColor;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.categoryTheme,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              categoryTheme?.borderColor.withValues(alpha: 0.72) ??
              AppColors.border,
        ),
        boxShadow: AppShadows.soft(
          categoryTheme?.primaryColor ?? AppColors.primary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SheetFooter extends StatelessWidget {
  final int activeCount;
  final VoidCallback onApply;
  final CategoryThemeData? categoryTheme;

  const _SheetFooter({
    required this.activeCount,
    required this.onApply,
    required this.categoryTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = categoryTheme?.filterButtonColor ?? AppColors.primary;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.98),
          border: Border(
            top: BorderSide(
              color:
                  categoryTheme?.borderColor.withValues(alpha: 0.85) ??
                  AppColors.border,
            ),
          ),
          boxShadow: AppShadows.soft(accent),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                activeCount == 0
                    ? 'Ek filtre seçilmedi'
                    : '$activeCount ek filtre hazır',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.check),
              label: const Text('Uygula'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sort section — primary dropdown + optional nutrition sort ─────────────────

class _SortSection extends StatefulWidget {
  final SearchSortOrder current;
  final ValueChanged<SearchSortOrder> onChanged;

  const _SortSection({required this.current, required this.onChanged});

  @override
  State<_SortSection> createState() => _SortSectionState();
}

class _SortSectionState extends State<_SortSection> {
  static const _basicSorts = [
    SearchSortOrder.relevance,
    SearchSortOrder.newestFirst,
    SearchSortOrder.nameAsc,
    SearchSortOrder.nameDesc,
    SearchSortOrder.brandAsc,
    SearchSortOrder.brandDesc,
  ];

  static const _nutritionMetrics = <(String, String)>[
    ('none', 'Belirtilmedi'),
    ('energy', 'Kalori'),
    ('protein', 'Protein'),
    ('sugar', 'Şeker'),
    ('fat', 'Yağ'),
    ('saturatedFat', 'Doymuş Yağ'),
    ('salt', 'Tuz'),
    ('fiber', 'Lif'),
  ];

  late String _nutritionMetric;
  late bool _nutritionAsc;

  @override
  void initState() {
    super.initState();
    _nutritionMetric = _metricOf(widget.current);
    _nutritionAsc = _isAscSort(widget.current);
  }

  @override
  void didUpdateWidget(_SortSection old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      _nutritionMetric = _metricOf(widget.current);
      _nutritionAsc = _isAscSort(widget.current);
    }
  }

  static String _metricOf(SearchSortOrder s) {
    switch (s) {
      case SearchSortOrder.energyAsc:
      case SearchSortOrder.energyDesc:
        return 'energy';
      case SearchSortOrder.proteinsAsc:
      case SearchSortOrder.proteinsDesc:
        return 'protein';
      case SearchSortOrder.sugarsAsc:
      case SearchSortOrder.sugarsDesc:
        return 'sugar';
      case SearchSortOrder.fatAsc:
      case SearchSortOrder.fatDesc:
        return 'fat';
      case SearchSortOrder.saturatedFatAsc:
      case SearchSortOrder.saturatedFatDesc:
        return 'saturatedFat';
      case SearchSortOrder.saltAsc:
      case SearchSortOrder.saltDesc:
        return 'salt';
      case SearchSortOrder.fiberAsc:
      case SearchSortOrder.fiberDesc:
        return 'fiber';
      default:
        return 'none';
    }
  }

  static bool _isAscSort(SearchSortOrder s) {
    switch (s) {
      case SearchSortOrder.energyAsc:
      case SearchSortOrder.proteinsAsc:
      case SearchSortOrder.sugarsAsc:
      case SearchSortOrder.fatAsc:
      case SearchSortOrder.saturatedFatAsc:
      case SearchSortOrder.saltAsc:
      case SearchSortOrder.fiberAsc:
        return true;
      default:
        return false;
    }
  }

  static SearchSortOrder _sortOrderFor(String metric, bool asc) {
    switch (metric) {
      case 'energy':
        return asc ? SearchSortOrder.energyAsc : SearchSortOrder.energyDesc;
      case 'protein':
        return asc ? SearchSortOrder.proteinsAsc : SearchSortOrder.proteinsDesc;
      case 'sugar':
        return asc ? SearchSortOrder.sugarsAsc : SearchSortOrder.sugarsDesc;
      case 'fat':
        return asc ? SearchSortOrder.fatAsc : SearchSortOrder.fatDesc;
      case 'saturatedFat':
        return asc
            ? SearchSortOrder.saturatedFatAsc
            : SearchSortOrder.saturatedFatDesc;
      case 'salt':
        return asc ? SearchSortOrder.saltAsc : SearchSortOrder.saltDesc;
      case 'fiber':
        return asc ? SearchSortOrder.fiberAsc : SearchSortOrder.fiberDesc;
      default:
        return SearchSortOrder.relevance;
    }
  }

  SearchSortOrder get _currentBasicSort => _basicSorts.contains(widget.current)
      ? widget.current
      : SearchSortOrder.relevance;

  void _onNutritionMetricChanged(String metric) {
    setState(() => _nutritionMetric = metric);
    if (metric == 'none') {
      widget.onChanged(_currentBasicSort);
    } else {
      widget.onChanged(_sortOrderFor(metric, _nutritionAsc));
    }
  }

  void _onNutritionAscChanged(bool asc) {
    setState(() => _nutritionAsc = asc);
    if (_nutritionMetric != 'none') {
      widget.onChanged(_sortOrderFor(_nutritionMetric, asc));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Primary sort
        InputDecorator(
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
          ),
          child: DropdownButton<SearchSortOrder>(
            value: _currentBasicSort,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: _basicSorts
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(s.label, style: const TextStyle(fontSize: 14)),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _nutritionMetric = 'none');
              widget.onChanged(v);
            },
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Besin değerine göre sırala',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Metric dropdown
            Expanded(
              flex: 3,
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Besin',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: DropdownButton<String>(
                  value: _nutritionMetric,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: _nutritionMetrics
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.$1,
                          child: Text(
                            m.$2,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) _onNutritionMetricChanged(v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Direction dropdown
            Expanded(
              flex: 2,
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Yön',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: IgnorePointer(
                  ignoring: _nutritionMetric == 'none',
                  child: Opacity(
                    opacity: _nutritionMetric == 'none' ? 0.4 : 1.0,
                    child: DropdownButton<bool>(
                      value: _nutritionAsc,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(
                          value: true,
                          child: Text('Artan', style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: false,
                          child: Text('Azalan', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) _onNutritionAscChanged(v);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Category section ──────────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final ProductListContext listContext;
  final ProductSearchFilter filter;
  final ValueChanged<String?> onMainChanged;
  final ValueChanged<String?> onSubChanged;

  const _CategorySection({
    required this.listContext,
    required this.filter,
    required this.onMainChanged,
    required this.onSubChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mainCategory = listContext.locksMainCategory
        ? listContext.lockedMainCategory
        : filter.mainCategory;
    final subCategory = filter.subCategory;
    final mainOptions = listContext.availableMainCategories(filter);
    final subOptions = listContext.availableSubCategories(filter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (listContext.canChangeMainCategory) ...[
          Text(
            'Ana kategori',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tümü', style: TextStyle(fontSize: 12)),
                selected: mainCategory == null,
                onSelected: (_) => onMainChanged(null),
              ),
              ...mainOptions.map((cat) {
                final selected = cat == mainCategory;
                return ChoiceChip(
                  label: Text(cat, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => onMainChanged(selected ? null : cat),
                );
              }),
            ],
          ),
        ] else ...[
          _ReadOnlyCategoryField(
            label: 'Ana kategori',
            value: mainCategory ?? 'Sabit kategori',
          ),
        ],
        if (mainCategory != null && subOptions.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Alt kategori',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Tümü', style: TextStyle(fontSize: 12)),
                selected: subCategory == null,
                onSelected: (_) => onSubChanged(null),
              ),
              ...subOptions.map((sub) {
                final selected = sub == subCategory;
                return ChoiceChip(
                  label: Text(sub, style: const TextStyle(fontSize: 12)),
                  selected: selected,
                  onSelected: (_) => onSubChanged(selected ? null : sub),
                );
              }),
            ],
          ),
        ],
      ],
    );
  }
}

class _ReadOnlyCategoryField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyCategoryField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Brand section — searchable multi-select with collapse ─────────────────────

class _BrandSection extends StatelessWidget {
  final List<String>? availableBrands;
  final List<String> selectedBrands;
  final TextEditingController searchController;
  final String searchText;
  final bool showAll;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onBrandToggled;
  final VoidCallback onToggleShowAll;

  const _BrandSection({
    required this.availableBrands,
    required this.selectedBrands,
    required this.searchController,
    required this.searchText,
    required this.showAll,
    required this.onSearchChanged,
    required this.onBrandToggled,
    required this.onToggleShowAll,
  });

  @override
  Widget build(BuildContext context) {
    if (availableBrands == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (availableBrands!.isEmpty) {
      return Text(
        'Bu kategori için marka listesi yüklenemedi.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      );
    }

    final filtered = searchText.isEmpty
        ? availableBrands!
        : availableBrands!
              .where((b) => b.toLowerCase().contains(searchText.toLowerCase()))
              .toList();

    // When searching, always show all matches.
    // When not searching, show first 5 + any selected beyond the first 5.
    final bool searching = searchText.isNotEmpty;
    final List<String> visibleBrands;
    if (searching || showAll) {
      visibleBrands = filtered;
    } else {
      final first5 = filtered.take(5).toSet();
      final alwaysVisible = filtered
          .where((b) => selectedBrands.contains(b))
          .toSet();
      final combined = {...first5, ...alwaysVisible};
      visibleBrands = filtered.where(combined.contains).toList();
    }

    final hiddenCount = filtered.length - visibleBrands.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Marka ara…',
            prefixIcon: const Icon(Icons.search, size: 18),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
        ),
        const SizedBox(height: 6),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '"$searchText" ile eşleşen marka yok.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          )
        else ...[
          ...visibleBrands.map((brand) {
            final selected = selectedBrands.contains(brand);
            return SizedBox(
              height: 40,
              child: CheckboxListTile(
                title: Text(brand, style: const TextStyle(fontSize: 13)),
                value: selected,
                onChanged: (_) => onBrandToggled(brand),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                controlAffinity: ListTileControlAffinity.leading,
                visualDensity: VisualDensity.compact,
              ),
            );
          }),
          if (!searching) ...[
            if (hiddenCount > 0)
              TextButton.icon(
                onPressed: onToggleShowAll,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text('Daha fazla marka göster ($hiddenCount)'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              )
            else if (showAll && filtered.length > 5)
              TextButton.icon(
                onPressed: onToggleShowAll,
                icon: const Icon(Icons.expand_less, size: 18),
                label: const Text('Daha az göster'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ],
      ],
    );
  }
}

// ── Nutrition section — bidirectional add-rule interface ──────────────────────

class _NutritionSection extends StatefulWidget {
  final NutritionFilter nutrition;
  final ValueChanged<NutritionFilter> onChanged;

  const _NutritionSection({required this.nutrition, required this.onChanged});

  @override
  State<_NutritionSection> createState() => _NutritionSectionState();
}

class _NutritionSectionState extends State<_NutritionSection> {
  String _pendingKey = 'energy';
  bool _pendingIsMax = true;
  double? _pendingThreshold;

  _BidiNutrientSpec get _currentSpec =>
      _kBidiSpecs.firstWhere((s) => s.key == _pendingKey);

  List<double> get _currentThresholds =>
      _currentSpec.thresholdsFor(_pendingIsMax);

  void _addRule() {
    if (_pendingThreshold == null) return;
    final updated = _setRule(
      widget.nutrition,
      _pendingKey,
      _pendingIsMax,
      _pendingThreshold,
    );
    widget.onChanged(updated);
    setState(() => _pendingThreshold = null);
  }

  void _removeRule(String key, bool isMax) {
    widget.onChanged(_setRule(widget.nutrition, key, isMax, null));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = _activeRules(widget.nutrition);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Active rules
        if (rules.isNotEmpty) ...[
          ...rules.map(
            (rule) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      rule.format(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _removeRule(rule.key, rule.isMax),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 16),
        ],
        // Add-rule controls
        Text(
          'Kural ekle',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Metric
            Expanded(
              flex: 3,
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: DropdownButton<String>(
                  value: _pendingKey,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: _kBidiSpecs
                      .map(
                        (s) => DropdownMenuItem(
                          value: s.key,
                          child: Text(
                            s.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _pendingKey = v;
                        _pendingThreshold = null;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Comparator
            Expanded(
              flex: 2,
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: DropdownButton<bool>(
                  value: _pendingIsMax,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                      value: true,
                      child: Text('En fazla', style: TextStyle(fontSize: 13)),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: Text('En az', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _pendingIsMax = v;
                        _pendingThreshold = null;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Threshold
            Expanded(
              flex: 3,
              child: InputDecorator(
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                ),
                child: DropdownButton<double?>(
                  value: _pendingThreshold,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: Text(
                    'Değer seçin',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  items: _currentThresholds.map((t) {
                    final label = t == t.truncateToDouble()
                        ? '${t.toInt()} ${_currentSpec.unit}'
                        : '$t ${_currentSpec.unit}';
                    return DropdownMenuItem<double?>(
                      value: t,
                      child: Text(label, style: const TextStyle(fontSize: 13)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _pendingThreshold = v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _pendingThreshold != null ? _addRule : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Ekle'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Ingredient section ────────────────────────────────────────────────────────

class _IngredientSection extends StatelessWidget {
  final IngredientFilterConfig ingredient;
  final ValueChanged<IngredientFilterConfig> onChanged;

  const _IngredientSection({required this.ingredient, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        FilterChip(
          label: const Text(
            'Palm yağı tespit edilmedi',
            style: TextStyle(fontSize: 12),
          ),
          selected: ingredient.excludePalmOil,
          onSelected: (v) => onChanged(ingredient.copyWith(excludePalmOil: v)),
        ),
        FilterChip(
          label: const Text(
            'Koruyucu tespit edilmedi',
            style: TextStyle(fontSize: 12),
          ),
          selected: ingredient.excludePreservatives,
          onSelected: (v) =>
              onChanged(ingredient.copyWith(excludePreservatives: v)),
        ),
        FilterChip(
          label: const Text(
            'Renklendirici tespit edilmedi',
            style: TextStyle(fontSize: 12),
          ),
          selected: ingredient.excludeArtificialColorants,
          onSelected: (v) =>
              onChanged(ingredient.copyWith(excludeArtificialColorants: v)),
        ),
        FilterChip(
          label: const Text(
            'Tatlandırıcı tespit edilmedi',
            style: TextStyle(fontSize: 12),
          ),
          selected: ingredient.excludeArtificialSweeteners,
          onSelected: (v) =>
              onChanged(ingredient.copyWith(excludeArtificialSweeteners: v)),
        ),
        FilterChip(
          label: const Text(
            'Şeker ilavesi tespit edilmedi',
            style: TextStyle(fontSize: 12),
          ),
          selected: ingredient.excludeAddedSugar,
          onSelected: (v) =>
              onChanged(ingredient.copyWith(excludeAddedSugar: v)),
        ),
      ],
    );
  }
}
