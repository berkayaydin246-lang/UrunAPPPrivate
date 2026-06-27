import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/category_theme.dart';

class CategoryThemeArtwork extends StatelessWidget {
  final CategoryThemeData categoryTheme;
  final double size;
  final double emojiSize;
  final EdgeInsetsGeometry padding;

  const CategoryThemeArtwork({
    super.key,
    required this.categoryTheme,
    this.size = 82,
    this.emojiSize = 30,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: 0,
            bottom: 4,
            child: Container(
              width: size * 0.82,
              height: size * 0.82,
              decoration: BoxDecoration(
                color: categoryTheme.primaryColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(size * 0.28),
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: 8,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                color: categoryTheme.secondaryColor.withValues(alpha: 0.28),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    categoryTheme.chipTint.withValues(alpha: 0.92),
                    categoryTheme.cardTint.withValues(alpha: 0.82),
                  ],
                ),
                borderRadius: BorderRadius.circular(size * 0.28),
                border: Border.all(
                  color: categoryTheme.borderColor.withValues(alpha: 0.76),
                ),
              ),
              child: _AssetOrFallback(
                categoryTheme: categoryTheme,
                emojiSize: emojiSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetOrFallback extends StatelessWidget {
  final CategoryThemeData categoryTheme;
  final double emojiSize;

  const _AssetOrFallback({
    required this.categoryTheme,
    required this.emojiSize,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      categoryTheme.imageAssetPath,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stackTrace) => Center(
        child: Text(
          categoryTheme.fallbackIcon,
          style: TextStyle(fontSize: emojiSize),
        ),
      ),
    );
  }
}
