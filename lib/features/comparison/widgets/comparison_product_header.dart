import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_product_image.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';

enum ComparisonProductHeaderLayout { summary, comparisonColumn }

class ComparisonProductHeader extends StatelessWidget {
  const ComparisonProductHeader({
    super.key,
    required this.productData,
    required this.layout,
    this.onChangeProduct,
    this.changeActionLabel = 'Ürünü değiştir',
    this.semanticLabel,
  });

  final ComparisonProductData productData;
  final ComparisonProductHeaderLayout layout;
  final VoidCallback? onChangeProduct;
  final String changeActionLabel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return switch (layout) {
      ComparisonProductHeaderLayout.summary => _SummaryLayout(
        productData: productData,
        semanticLabel: semanticLabel,
      ),
      ComparisonProductHeaderLayout.comparisonColumn => _ComparisonColumnLayout(
        productData: productData,
        onChangeProduct: onChangeProduct,
        changeActionLabel: changeActionLabel,
        semanticLabel: semanticLabel,
      ),
    };
  }
}

class _SummaryLayout extends StatelessWidget {
  const _SummaryLayout({required this.productData, this.semanticLabel});

  final ComparisonProductData productData;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final meta = _buildMetaLine(productData);

    return Semantics(
      container: true,
      label: semanticLabel ?? _semanticSummary(productData),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              image: true,
              label: '${productData.product.name} ürün görseli',
              child: FreshProductImage(
                productId: productData.product.id,
                imageUrl: productData.product.imageUrl,
                size: 68,
                padding: 6,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productData.product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.18,
                    ),
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonColumnLayout extends StatelessWidget {
  const _ComparisonColumnLayout({
    required this.productData,
    required this.changeActionLabel,
    this.onChangeProduct,
    this.semanticLabel,
  });

  final ComparisonProductData productData;
  final VoidCallback? onChangeProduct;
  final String changeActionLabel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final brand = productData.product.brand?.trim();
    final quantity = productData.quantityLabel?.trim();

    return Semantics(
      container: true,
      label: semanticLabel ?? _semanticSummary(productData),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            image: true,
            label: '${productData.product.name} ürün görseli',
            child: FreshProductImage(
              productId: productData.product.id,
              imageUrl: productData.product.imageUrl,
              size: 104,
              padding: 7,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            productData.product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.18,
            ),
          ),
          if (brand != null && brand.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              brand,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (quantity != null && quantity.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              quantity,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (onChangeProduct != null) ...[
            const SizedBox(height: 8),
            Semantics(
              button: true,
              label: '${productData.product.name} için $changeActionLabel',
              child: TextButton.icon(
                onPressed: onChangeProduct,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: Text(
                  changeActionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? _buildMetaLine(ComparisonProductData data) {
  final parts = <String>[];
  final brand = data.product.brand?.trim();
  final quantity = data.quantityLabel?.trim();
  if (brand != null && brand.isNotEmpty) {
    parts.add(brand);
  }
  if (quantity != null && quantity.isNotEmpty) {
    parts.add(quantity);
  }
  if (parts.isEmpty) {
    return null;
  }
  return parts.join(' • ');
}

String _semanticSummary(ComparisonProductData data) {
  final parts = <String>[data.product.name];
  final brand = data.product.brand?.trim();
  final quantity = data.quantityLabel?.trim();
  if (brand != null && brand.isNotEmpty) {
    parts.add('Marka $brand');
  }
  if (quantity != null && quantity.isNotEmpty) {
    parts.add('Miktar $quantity');
  }
  return parts.join('. ');
}
