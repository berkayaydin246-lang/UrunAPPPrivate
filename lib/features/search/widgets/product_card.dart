import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';
import 'package:food_analyzer_app/core/widgets/fresh_product_image.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/models/product_search_filter.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

const kCompactProductImageTextGap = 7.0;
const kCompactProductBrandAreaHeight = 16.0;
const kCompactProductBrandNameGap = 2.0;
const kCompactProductNameMinHeight = 42.0;
const kCompactProductNameBottomPadding = 4.0;
const kCompactProductTileGridSafetySlack = 2.0;

double compactProductTileHeight(double itemWidth) {
  return itemWidth +
      kCompactProductImageTextGap +
      kCompactProductBrandAreaHeight +
      kCompactProductBrandNameGap +
      kCompactProductNameMinHeight +
      kCompactProductNameBottomPadding +
      kCompactProductTileGridSafetySlack;
}

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  /// When set to a nutrition-based sort, the card shows the relevant value.
  final SearchSortOrder? sortOrder;
  final CategoryThemeData? categoryTheme;

  /// When true, hides data-completeness chips and the 2/2 badge.
  final bool simpleMode;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.sortOrder,
    this.categoryTheme,
    this.simpleMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTheme = categoryTheme ?? getCategoryThemeForProduct(product);

    if (simpleMode) {
      return _CompactProductTile(
        product: product,
        categoryTheme: resolvedTheme,
        onTap: onTap,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Color.lerp(resolvedTheme.borderColor, AppColors.border, 0.65)!,
        ),
        boxShadow: AppShadows.soft(resolvedTheme.primaryColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 14,
                bottom: 14,
                child: Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: resolvedTheme.selectedChipColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                right: -18,
                top: -16,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: resolvedTheme.primaryColor.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FreshProductImage(
                      productId: product.id,
                      imageUrl: product.imageUrl,
                      accentColor: resolvedTheme.filterButtonColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.brand != null &&
                              product.brand!.isNotEmpty)
                            Text(
                              product.brand!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _MetaRow(
                            product: product,
                            sortOrder: sortOrder,
                            categoryTheme: resolvedTheme,
                            simpleMode: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _CompletenessBadge(product: product),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Compact category grid tile ───────────────────────────────────────────────

class _CompactProductTile extends StatelessWidget {
  final Product product;
  final CategoryThemeData categoryTheme;
  final VoidCallback onTap;

  const _CompactProductTile({
    required this.product,
    required this.categoryTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = product.brand?.trim();

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('compact-product-tile-${product.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CompactProductImage(
              key: ValueKey('compact-product-image-${product.id}'),
              productId: product.id,
              imageUrl: product.imageUrl,
              categoryTheme: categoryTheme,
            ),
            const SizedBox(height: kCompactProductImageTextGap),
            SizedBox(
              height: kCompactProductBrandAreaHeight,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  (brand == null || brand.isEmpty) ? ' ' : brand,
                  key: ValueKey('compact-product-brand-${product.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            const SizedBox(height: kCompactProductBrandNameGap),
            Padding(
              key: ValueKey('compact-product-name-area-${product.id}'),
              padding: const EdgeInsets.only(
                bottom: kCompactProductNameBottomPadding,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: kCompactProductNameMinHeight,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    product.name,
                    key: ValueKey('compact-product-name-${product.id}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: true,
                      applyHeightToLastDescent: true,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.8,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.28,
                      leadingDistribution: TextLeadingDistribution.even,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactProductImage extends StatelessWidget {
  final String productId;
  final String? imageUrl;
  final CategoryThemeData categoryTheme;

  const _CompactProductImage({
    super.key,
    required this.productId,
    required this.imageUrl,
    required this.categoryTheme,
  });

  @override
  Widget build(BuildContext context) {
    final imageSurface = Color.lerp(
      Colors.white,
      categoryTheme.primaryColor,
      0.025,
    )!;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: imageSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: categoryTheme.primaryColor.withValues(alpha: 0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.028),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ProductThumbnail(
            productId: productId,
            imageUrl: imageUrl,
            accentColor: categoryTheme.primaryColor,
            iconSize: 30,
          ),
        ),
      ),
    );
  }
}

// ── Meta row (canonical category + data badges + optional nutrition hint) ─────

class _MetaRow extends StatelessWidget {
  final Product product;
  final SearchSortOrder? sortOrder;
  final CategoryThemeData categoryTheme;
  final bool simpleMode;

  const _MetaRow({
    required this.product,
    this.sortOrder,
    required this.categoryTheme,
    this.simpleMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final category = CanonicalCategoryMapper.map(
      categoryTags: product.categoryTags,
      name: product.name,
    );
    final categoryLabel = category.sub != null ? category.sub! : category.main;

    final nutritionBadge = _buildNutritionBadge(context);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (category.main != CanonicalCategoryMapper.kDiger ||
            category.sub != null)
          _Badge(
            label: categoryLabel,
            color: categoryTheme.badgeColor,
            background: categoryTheme.chipTint,
            border: categoryTheme.borderColor,
          ),
        if (!simpleMode) ...[
          if (nutritionBadge != null)
            nutritionBadge
          else ...[
            if (product.hasIngredients)
              _Badge(
                label: 'İçerik ✓',
                color: AppColors.successText,
                background: AppColors.successBg,
                border: AppColors.success.withValues(alpha: 0.28),
              )
            else
              _Badge(
                label: 'İçerik yok',
                color: AppColors.warningText,
                background: AppColors.warningBg,
                border: AppColors.warning.withValues(alpha: 0.26),
              ),
            if (product.hasNutrition)
              _Badge(
                label: 'Besin ✓',
                color: AppColors.successText,
                background: AppColors.successBg,
                border: AppColors.success.withValues(alpha: 0.28),
              )
            else
              _Badge(
                label: 'Besin yok',
                color: AppColors.warningText,
                background: AppColors.warningBg,
                border: AppColors.warning.withValues(alpha: 0.26),
              ),
          ],
        ],
      ],
    );
  }

  Widget? _buildNutritionBadge(BuildContext context) {
    if (sortOrder == null) return null;
    final n = product.nutrition;

    String? label;
    Color color = Colors.grey;

    switch (sortOrder!) {
      case SearchSortOrder.energyAsc:
      case SearchSortOrder.energyDesc:
        if (n?.energyKcal != null) {
          label = '${n!.energyKcal!.toStringAsFixed(0)} kcal';
          color = Colors.orange;
        } else {
          label = 'Besin verisi yok';
          color = Colors.grey;
        }
      case SearchSortOrder.proteinsDesc:
        if (n?.proteins != null) {
          label = 'Protein: ${_fmt(n!.proteins!)}g';
          color = Colors.purple;
        }
      case SearchSortOrder.sugarsAsc:
        if (n?.sugars != null) {
          label = 'Şeker: ${_fmt(n!.sugars!)}g';
          color = Colors.amber.shade700;
        }
      case SearchSortOrder.fatAsc:
        if (n?.fat != null) {
          label = 'Yağ: ${_fmt(n!.fat!)}g';
          color = Colors.red;
        }
      case SearchSortOrder.saltAsc:
        if (n?.salt != null) {
          label = 'Tuz: ${_fmt(n!.salt!)}g';
          color = Colors.blueGrey;
        }
      case SearchSortOrder.fiberDesc:
        if (n?.fiber != null) {
          label = 'Lif: ${_fmt(n!.fiber!)}g';
          color = Colors.green.shade700;
        }
      default:
        return null;
    }

    if (label == null) {
      return _Badge(
        label: 'Besin verisi yok',
        color: Colors.grey.shade700,
        background: Colors.grey.shade100,
        border: Colors.grey.shade300,
      );
    }
    return _Badge(
      label: label,
      color: color,
      background: color.withValues(alpha: 0.12),
      border: color.withValues(alpha: 0.24),
    );
  }

  static String _fmt(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _CompletenessBadge extends StatelessWidget {
  final Product product;

  const _CompletenessBadge({required this.product});

  @override
  Widget build(BuildContext context) {
    final available =
        (product.hasIngredients ? 1 : 0) + (product.hasNutrition ? 1 : 0);
    final color = switch (available) {
      2 => AppColors.success,
      1 => AppColors.warning,
      _ => AppColors.neutral,
    };
    final textColor = switch (available) {
      2 => AppColors.successText,
      1 => AppColors.warningText,
      _ => AppColors.neutralText,
    };

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.28), width: 2),
      ),
      child: Center(
        child: Text(
          '$available/2',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ── Badge ─────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color background;
  final Color border;

  const _Badge({
    required this.label,
    required this.color,
    required this.background,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
