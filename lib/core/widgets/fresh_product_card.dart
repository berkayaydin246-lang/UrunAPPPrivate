import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_chip.dart';
import 'package:food_analyzer_app/core/widgets/fresh_product_image.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/search/services/canonical_category_mapper.dart';

/// Clean product card using the FreshScan design system.
///
/// Replaces ad-hoc card containers in search results, category lists, and
/// staging screens. Uses [FreshProductImage] for the thumbnail and [FreshChip]
/// for data-completeness badges — no overflow, no fixed-height issues.
class FreshProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final CategoryThemeData? categoryTheme;

  const FreshProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.categoryTheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedTheme = categoryTheme ?? getCategoryThemeForProduct(product);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Color.lerp(resolvedTheme.borderColor, AppColors.border, 0.65)!,
        ),
        boxShadow: AppShadows.soft(resolvedTheme.primaryColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                      if (product.brand != null && product.brand!.isNotEmpty)
                        Text(
                          product.brand!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
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
                      _DataChips(
                        product: product,
                        categoryTheme: resolvedTheme,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataChips extends StatelessWidget {
  final Product product;
  final CategoryThemeData categoryTheme;

  const _DataChips({required this.product, required this.categoryTheme});

  @override
  Widget build(BuildContext context) {
    final category = CanonicalCategoryMapper.map(
      categoryTags: product.categoryTags,
      name: product.name,
    );
    final categoryLabel = category.sub ?? category.main;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (category.main != CanonicalCategoryMapper.kDiger ||
            category.sub != null)
          FreshChip(label: categoryLabel, color: categoryTheme.badgeColor),
        FreshChip(
          label: product.hasIngredients ? 'İçerik ✓' : 'İçerik yok',
          color: product.hasIngredients ? AppColors.success : AppColors.warning,
        ),
        FreshChip(
          label: product.hasNutrition ? 'Besin ✓' : 'Besin yok',
          color: product.hasNutrition ? AppColors.success : AppColors.warning,
        ),
      ],
    );
  }
}
