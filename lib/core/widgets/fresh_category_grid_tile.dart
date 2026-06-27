import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart'
    show CategoryThemeData, getCategoryThemeForCategory;
import 'package:food_analyzer_app/features/search/models/product_category.dart';

/// Compact 3-column category tile for the home/search browse grid.
///
/// Replaces the single-column FreshCategoryRow list with a layout that matches
/// marketplace conventions (3 per row, icon + name, no overflow).
class FreshCategoryGridTile extends StatelessWidget {
  final ProductCategory category;
  final VoidCallback onTap;
  final double itemWidth;

  // Short display names that fit safely in the 3-column grid.
  static const _gridNames = <String, String>{
    'Atıştırmalıklar': 'Atıştırmalık',
    'Süt & Süt Ürünleri': 'Süt Ürünleri',
    'Makarna & Bakliyat': 'Makarna',
    'Bebek & Çocuk Ürünleri': 'Bebek',
    'Soslar & Ketçap/Mayonez': 'Soslar',
    'Ton Balığı & Konserve': 'Ton Balığı',
    'Hazır Yemekler': 'Hazır Yemek',
    'Kahvaltılıklar': 'Kahvaltılık',
  };

  const FreshCategoryGridTile({
    super.key,
    required this.category,
    required this.itemWidth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryTheme = getCategoryThemeForCategory(category);
    final displayName = _gridNames[category.title] ?? category.title;
    final hasImage = category.imageAsset != null;
    const imageTitleGap = 10.0;
    const titleHeight = 54.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image area: fixed square with rounded corners
            SizedBox.square(
              dimension: itemWidth,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: hasImage
                      ? Image.asset(
                          category.imageAsset!,
                          width: itemWidth,
                          height: itemWidth,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) =>
                              _buildFallback(categoryTheme),
                        )
                      : _buildFallback(categoryTheme),
                ),
              ),
            ),
            // Fixed gap between image and title
            SizedBox(height: imageTitleGap),
            // Title area: fixed height with top alignment.
            // "Atıştırmalık" is 12 chars and wraps at fontSize 15 in a narrow
            // column; FittedBox scales it down just enough to stay single-line.
            SizedBox(
              height: titleHeight,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: () {
                    final style = theme.textTheme.labelMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.15,
                    );
                    final prefersSingleLine = displayName == 'Atıştırmalık';
                    if (prefersSingleLine) {
                      return SizedBox(
                        width: double.infinity,
                        height: 24,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: Text(
                            displayName,
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: style,
                          ),
                        ),
                      );
                    }
                    return Text(
                      displayName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    );
                  }(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback(CategoryThemeData categoryTheme) {
    return Container(
      decoration: BoxDecoration(
        color: categoryTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Text(
          categoryTheme.fallbackIcon,
          style: const TextStyle(fontSize: 32),
        ),
      ),
    );
  }
}
