import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';

/// Shared product image tile used in cards, detail page, and staging cards.
///
/// Always white/background-tinted with soft border and contained image.
/// Pass [accentColor] to tint the fallback placeholder with the category color.
class FreshProductImage extends StatelessWidget {
  final String productId;
  final String? imageUrl;
  final double size;
  final double padding;
  final Color? accentColor;

  const FreshProductImage({
    super.key,
    required this.productId,
    this.imageUrl,
    this.size = 72,
    this.padding = 5,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    const bg = AppColors.background;
    final color = accentColor ?? AppColors.primary;
    if (imageUrl == null || imageUrl!.trim().isEmpty) {
      return _placeholder(bg, color);
    }

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: ProductThumbnail(
          productId: productId,
          imageUrl: imageUrl,
          accentColor: color,
          iconSize: size * 0.38,
        ),
      ),
    );
  }

  Widget _placeholder(Color bg, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(
        Icons.shopping_bag_outlined,
        color: color.withValues(alpha: 0.7),
        size: size * 0.38,
      ),
    );
  }
}
