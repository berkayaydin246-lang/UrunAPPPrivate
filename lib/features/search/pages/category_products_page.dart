import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/models/product_list_context.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';
import 'package:food_analyzer_app/features/search/widgets/product_list_view.dart';

// Shortcut sub-category IDs are no longer included in ProductCategories.all
// but keep the set to guard against any legacy deep links.
const _subcategoryShortcutIds = <String>{
  'cikolata-gofret',
  'biskuvi-kek',
  'cips-kraker',
  'enerji-icecekleri',
};

// Short tab labels that fit the horizontal tab bar.
const _tabShortNames = <String, String>{
  'Süt & Kahvaltılık': 'Süt & Kahv.',
  'Et, Tavuk & Balık': 'Et & Balık',
  'Hazır & Donuk': 'Hazır',
  'Fırın & Pastane': 'Fırın',
  'Özel Beslenme': 'Özel',
  'Meyve & Sebze': 'Meyve',
  'Bebek Gıda': 'Bebek',
};

/// Category product browser with a scrollable main-category tab bar and
/// horizontal swipe between categories.
///
/// The [category] arg sets the initially selected tab. All main categories
/// are shown as tabs so the user can swipe or tap to jump between them.
class CategoryProductsPage extends StatefulWidget {
  final ProductCategory category;
  final ProductRepository productRepository;

  const CategoryProductsPage({
    super.key,
    required this.category,
    ProductRepository? productRepository,
  }) : productRepository = productRepository ?? const ProductRepository();

  @override
  State<CategoryProductsPage> createState() => _CategoryProductsPageState();
}

class _CategoryProductsPageState extends State<CategoryProductsPage>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  late final List<ProductCategory> _mainCategories;

  @override
  void initState() {
    super.initState();
    _mainCategories = ProductCategories.getVisible()
        .where((c) => !_subcategoryShortcutIds.contains(c.id))
        .toList();

    final initialIndex = _mainCategories
        .indexWhere((c) => c.id == widget.category.id)
        .clamp(0, _mainCategories.length - 1);

    _tabController = TabController(
      length: _mainCategories.length,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(onPressed: () => context.pop()),
        title: const Text('Ürünler'),
        bottom: _CategoryTabBar(
          categories: _mainCategories,
          controller: _tabController,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _mainCategories
            .map(
              (cat) => _CategoryTabPage(
                category: cat,
                productRepository: widget.productRepository,
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Main-category tab bar ─────────────────────────────────────────────────────

class _CategoryTabBar extends StatelessWidget implements PreferredSizeWidget {
  final List<ProductCategory> categories;
  final TabController controller;

  const _CategoryTabBar({required this.categories, required this.controller});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: AnimatedBuilder(
        animation: controller.animation ?? controller,
        builder: (context, child) {
          final clampedIndex = controller.index.clamp(0, categories.length - 1);
          final selectedTheme = getCategoryThemeForCategory(
            categories[clampedIndex],
          );

          return TabBar(
            key: const ValueKey('main-category-tab-bar'),
            controller: controller,
            isScrollable: true,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.label,
            indicator: UnderlineTabIndicator(
              borderSide: BorderSide(
                color: selectedTheme.selectedChipColor,
                width: 3,
              ),
              insets: const EdgeInsets.symmetric(horizontal: 12),
            ),
            indicatorColor: selectedTheme.selectedChipColor,
            labelColor: selectedTheme.selectedChipColor,
            unselectedLabelColor: AppColors.textSecondary,
            overlayColor: WidgetStatePropertyAll(
              selectedTheme.chipTint.withValues(alpha: 0.28),
            ),
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            labelStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            unselectedLabelStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            tabs: categories
                .map((cat) => Tab(text: _tabShortNames[cat.title] ?? cat.title))
                .toList(),
          );
        },
      ),
    );
  }
}

// ── Per-category tab page ─────────────────────────────────────────────────────

class _CategoryTabPage extends StatefulWidget {
  final ProductCategory category;
  final ProductRepository productRepository;

  const _CategoryTabPage({
    required this.category,
    required this.productRepository,
  });

  @override
  State<_CategoryTabPage> createState() => _CategoryTabPageState();
}

class _CategoryTabPageState extends State<_CategoryTabPage> {
  late final Override _providerOverride;
  late final ProductListContext _listContext;
  late final CategoryThemeData _categoryTheme;

  @override
  void initState() {
    super.initState();
    _listContext = _buildListContext(widget.category);
    _categoryTheme = getCategoryTheme(_listContext.lockedMainCategory);
    _providerOverride = filteredSearchProvider.overrideWith(
      (ref) => FilteredSearchNotifier(
        widget.productRepository,
        initialFilter: _listContext.initialFilter(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageBackground = Color.lerp(
      Colors.white,
      _categoryTheme.primaryColor,
      0.035,
    )!;

    return ProviderScope(
      overrides: [_providerOverride],
      child: ColoredBox(
        color: pageBackground,
        child: Column(
          children: [
            if (_listContext.lockedMainCategory != null)
              _SubCategoryQuickFilter(
                listContext: _listContext,
                categoryTheme: _categoryTheme,
              ),
            Expanded(
              child: ProductListView(
                searchHint: '${widget.category.title} içinde ara',
                listContext: _listContext,
                categoryTheme: _categoryTheme,
                simpleCards: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static ProductListContext _buildListContext(ProductCategory cat) {
    final canonical = CanonicalCategoryMapper.map(
      categoryTags: cat.databaseTags.isNotEmpty ? cat.databaseTags : null,
      name: cat.title,
    );

    if (_subcategoryShortcutIds.contains(cat.id) && canonical.sub != null) {
      return ProductListContext.subCategory(
        mainCategory: canonical.main,
        subCategory: canonical.sub!,
      );
    }

    return ProductListContext.mainCategory(mainCategory: canonical.main);
  }
}

// ── Subcategory quick-filter chip row ─────────────────────────────────────────

/// Horizontal chip row for quick subcategory filtering.
///
/// "Tümü" resets to the full main category. Each chip filters to a sub.
class _SubCategoryQuickFilter extends ConsumerWidget {
  final ProductListContext listContext;
  final CategoryThemeData categoryTheme;

  const _SubCategoryQuickFilter({
    required this.listContext,
    required this.categoryTheme,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filteredSearchProvider).filter;
    final subs = CanonicalCategoryMapper.subCategoriesFor(
      listContext.lockedMainCategory!,
    );

    if (subs.isEmpty) return const SizedBox.shrink();

    void setFilter(ProductSearchFilter f) {
      ref
          .read(filteredSearchProvider.notifier)
          .setFilter(listContext.normalizeFilter(f));
    }

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        children: [
          Center(
            child: _QuickChip(
              label: 'Tümü',
              selected: filter.subCategory == null,
              categoryTheme: categoryTheme,
              onTap: () => setFilter(filter.copyWith(subCategory: null)),
            ),
          ),
          ...subs.map(
            (sub) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Center(
                child: _QuickChip(
                  label: sub,
                  selected: filter.subCategory == sub,
                  categoryTheme: categoryTheme,
                  onTap: () => setFilter(filter.copyWith(subCategory: sub)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final bool selected;
  final CategoryThemeData categoryTheme;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.categoryTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = categoryTheme.selectedChipColor;
    final selectedBg = categoryTheme.selectedChipColor;
    const unselectedBg = AppColors.surface;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        key: ValueKey('subcategory-chip-${categoryTheme.mainCategory}-$label'),
        duration: const Duration(milliseconds: 160),
        height: 36,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? accent : categoryTheme.borderColor,
            width: selected ? 1.5 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                    color: accent.withValues(alpha: 0.18),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected
                  ? categoryTheme.selectedChipTextColor
                  : categoryTheme.badgeColor,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              height: 1.18,
            ),
          ),
        ),
      ),
    );
  }
}
