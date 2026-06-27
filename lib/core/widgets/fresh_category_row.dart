import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/widgets/category_theme_artwork.dart';

/// Single-row category entry for the browse/search category list.
///
/// Replaces the 2-column grid that caused Turkish text overflow like
/// "Atıştır / malı...". Artwork on the left, title + subtitle in the
/// centre, chevron on the right.
class FreshCategoryRow extends StatelessWidget {
  final ProductCategory category;
  final String? subtitle;
  final VoidCallback onTap;

  const FreshCategoryRow({
    super.key,
    required this.category,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryTheme = getCategoryThemeForCategory(category);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Color.lerp(
                categoryTheme.borderColor,
                AppColors.border,
                0.6,
              )!,
            ),
          ),
          child: Row(
            children: [
              CategoryThemeArtwork(
                categoryTheme: categoryTheme,
                size: 52,
                emojiSize: 22,
                padding: const EdgeInsets.all(6),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
    );
  }
}
