import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';
import 'package:food_analyzer_app/features/search/models/product_category.dart';
import 'package:food_analyzer_app/features/search/widgets/category_theme_artwork.dart';

enum CategoryCardVariant { featured, compact }

class CategoryCard extends StatelessWidget {
  final ProductCategory category;
  final VoidCallback onTap;
  final CategoryCardVariant variant;
  final String? subtitle;
  final String? badgeLabel;

  const CategoryCard({
    super.key,
    required this.category,
    required this.onTap,
    this.variant = CategoryCardVariant.featured,
    this.subtitle,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryTheme = getCategoryThemeForCategory(category);
    final compact = variant == CategoryCardVariant.compact;
    final radius = compact ? 20.0 : 24.0;
    final displayTitle = compact
        ? category.title
        : _displayTitle(category.title);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Color.lerp(
                  categoryTheme.borderColor,
                  AppColors.border,
                  0.55,
                )!,
              ),
              boxShadow: AppShadows.soft(categoryTheme.primaryColor),
            ),
            child: LayoutBuilder(
              builder: (context, _) {
                final artworkSize = compact ? 56.0 : 68.0;
                final horizontalPadding = compact ? 14.0 : 16.0;
                final topPadding = compact ? 14.0 : 16.0;
                final badgeBottomGap = badgeLabel == null ? 0.0 : 10.0;
                final iconBottomInset = compact ? 10.0 : 12.0;
                final iconRightInset = compact ? 10.0 : 12.0;

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      right: compact ? -12 : -10,
                      top: compact ? -10 : -8,
                      child: Container(
                        width: compact ? 52 : 60,
                        height: compact ? 52 : 60,
                        decoration: BoxDecoration(
                          color: categoryTheme.primaryColor.withValues(
                            alpha: 0.04,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      right: iconRightInset + artworkSize - 8,
                      bottom: iconBottomInset + 10,
                      child: Container(
                        width: compact ? 14 : 18,
                        height: compact ? 14 : 18,
                        decoration: BoxDecoration(
                          color: categoryTheme.secondaryColor.withValues(
                            alpha: 0.14,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        topPadding,
                        horizontalPadding + artworkSize + 8,
                        topPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (badgeLabel != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: categoryTheme.primaryColor.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: categoryTheme.primaryColor.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: Text(
                                badgeLabel!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: categoryTheme.badgeColor,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (badgeLabel != null)
                            SizedBox(height: badgeBottomGap),
                          Container(
                            width: compact ? 42 : 46,
                            height: 6,
                            decoration: BoxDecoration(
                              color: categoryTheme.primaryColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style:
                                (compact
                                        ? theme.textTheme.titleSmall
                                        : theme.textTheme.titleMedium)
                                    ?.copyWith(
                                      fontSize: compact ? 15 : 18,
                                      color: theme.colorScheme.onSurface,
                                      fontWeight: FontWeight.w800,
                                      height: 1.12,
                                    ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: compact ? 12.5 : 13,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                              ),
                            ),
                          ],
                          SizedBox(height: artworkSize + 8),
                        ],
                      ),
                    ),
                    Positioned(
                      right: iconRightInset,
                      bottom: iconBottomInset,
                      child: CategoryThemeArtwork(
                        categoryTheme: categoryTheme,
                        size: artworkSize,
                        emojiSize: compact ? 22 : 28,
                        padding: EdgeInsets.all(compact ? 7 : 8),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String _displayTitle(String title) {
  const labels = {
    'Soslar & Ketçap/Mayonez': 'Soslar',
    'Ton Balığı & Konserve': 'Ton Balığı',
    'Bebek & Çocuk Ürünleri': 'Bebek Ürünleri',
    'Makarna & Bakliyat': 'Makarna',
    'Süt & Süt Ürünleri': 'Süt Ürünleri',
    'Peynir & Yoğurt': 'Peynir & Yoğurt',
    'Hazır Yemekler': 'Hazır Yemekler',
    'Et & Şarküteri': 'Et & Şarküteri',
    'Atıştırmalıklar': 'Atıştırmalıklar',
    'İçecekler': 'İçecekler',
    'Kahvaltılıklar': 'Kahvaltılık',
    'Diğer': 'Diğer',
  };

  return labels[title] ?? title;
}
