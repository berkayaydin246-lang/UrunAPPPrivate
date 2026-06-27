import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_category_grid_tile.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/widgets/product_list_view.dart';

// Shortcut sub-category IDs excluded from the main grid.
const _subcategoryShortcutIds = {
  'cikolata-gofret',
  'biskuvi-kek',
  'cips-kraker',
  'enerji-icecekleri',
};

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Etiketly'),
        actions: [
          IconButton(
            tooltip: 'Kitaplığım',
            icon: const Icon(Icons.bookmarks_outlined),
            onPressed: () => context.pushNamed('history'),
          ),
          IconButton(
            tooltip: 'Hakkında',
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => context.pushNamed('settings'),
          ),
        ],
      ),
      body: ProductListView(
        showFilterButton: false,
        idleContent: _BrowseView(
          onCategoryTap: (cat) =>
              context.push('/category/${cat.id}', extra: cat),
        ),
      ),
    );
  }
}

// ── Browse view (shown when no query and no active filter) ────────────────────

class _BrowseView extends StatelessWidget {
  final ValueChanged<ProductCategory> onCategoryTap;
  const _BrowseView({required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    final categories = ProductCategories.getVisible()
        .where((c) => !_subcategoryShortcutIds.contains(c.id))
        .toList();
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.background, AppColors.surface],
        ),
      ),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Kategoriler',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Ürünleri kategoriye göre keşfet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              const horizontalPadding = 28.0;
              const crossAxisSpacing = 16.0;
              const mainAxisSpacing = 18.0;
              const imageTitleGap = 10.0;
              const titleHeight = 54.0;
              const crossAxisCount = 3;

              final usableWidth =
                  constraints.crossAxisExtent - (horizontalPadding * 2);
              final itemWidth =
                  (usableWidth - (crossAxisSpacing * (crossAxisCount - 1))) /
                  crossAxisCount;
              final itemHeight = itemWidth + imageTitleGap + titleHeight;

              return SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  22,
                  horizontalPadding,
                  120 + bottomInset,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: mainAxisSpacing,
                    crossAxisSpacing: crossAxisSpacing,
                    mainAxisExtent: itemHeight,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => FreshCategoryGridTile(
                      category: categories[index],
                      itemWidth: itemWidth,
                      onTap: () => onCategoryTap(categories[index]),
                    ),
                    childCount: categories.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
