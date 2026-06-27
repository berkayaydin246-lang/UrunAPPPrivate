import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_product_image.dart';
import 'package:food_analyzer_app/features/comparison/controllers/product_comparison_controller.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/comparison/widgets/comparison_product_header.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';

class ComparisonProductPickerPage extends ConsumerWidget {
  const ComparisonProductPickerPage({super.key, required this.routeArgs});

  final ComparisonPickerRouteArgs routeArgs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceProduct = routeArgs.sourceProduct;
    if (sourceProduct != null) {
      return _ComparisonProductPickerLoaded(sourceProduct: sourceProduct);
    }

    final sourceAsync = ref.watch(
      productDetailByIdProvider(routeArgs.sourceProductId),
    );
    return sourceAsync.when(
      loading: () => const _PickerScaffoldBody(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) =>
          const _PickerScaffoldBody(child: _ProductResolutionError()),
      data: (detail) {
        final product = detail.product;
        if (product == null) {
          return const _PickerScaffoldBody(child: _ProductResolutionError());
        }
        return _ComparisonProductPickerLoaded(sourceProduct: product);
      },
    );
  }
}

class _ComparisonProductPickerLoaded extends ConsumerStatefulWidget {
  const _ComparisonProductPickerLoaded({required this.sourceProduct});

  final Product sourceProduct;

  @override
  ConsumerState<_ComparisonProductPickerLoaded> createState() =>
      _ComparisonProductPickerLoadedState();
}

class _ComparisonProductPickerLoadedState
    extends ConsumerState<_ComparisonProductPickerLoaded> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ComparisonPickerConfig(sourceProduct: widget.sourceProduct);
    final state = ref.watch(comparisonPickerControllerProvider(config));
    final controller = ref.read(
      comparisonPickerControllerProvider(config).notifier,
    );

    return _PickerScaffoldBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ComparisonProductHeader(
            productData: ComparisonProductData(
              product: widget.sourceProduct,
              quantityLabel: extractProductQuantityLabel(widget.sourceProduct),
              nutritionBasis: inferNutritionBasis(widget.sourceProduct),
            ),
            layout: ComparisonProductHeaderLayout.summary,
            semanticLabel: 'Karşılaştırılacak kaynak ürün özeti',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('comparison-picker-search'),
            controller: _searchController,
            onChanged: controller.setSearchQuery,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Karşılaştırılacak ürün ara',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                state.usesCategoryOverlap
                    ? 'Benzer ürünler'
                    : 'Arama sonuçları',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (state.isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _buildBody(
              context,
              state: state,
              onRetry: controller.retry,
              onSelect: (product) {
                final selected = controller.selectCandidate(product);
                if (!selected) {
                  return;
                }
                Navigator.of(context).pop(product);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required ComparisonPickerState state,
    required Future<void> Function() onRetry,
    required ValueChanged<Product> onSelect,
  }) {
    if (state.error != null && state.candidates.isEmpty) {
      return _PickerMessageState(
        message: state.error!,
        actionLabel: 'Tekrar dene',
        icon: Icons.refresh_rounded,
        onAction: onRetry,
      );
    }

    if (state.isLoading && state.candidates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.candidates.isEmpty) {
      return _PickerMessageState(
        message: state.searchQuery.trim().isNotEmpty
            ? 'Aramanla eşleşen ürün bulunamadı.'
            : state.usesCategoryOverlap
            ? 'Benzer ürün bulunamadı.'
            : 'Aramanla eşleşen ürün bulunamadı.',
        icon: Icons.inventory_2_outlined,
      );
    }

    return ListView.separated(
      itemCount: state.candidates.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = state.candidates[index];
        return _ComparisonCandidateCard(
          product: product,
          onTap: () => onSelect(product),
        );
      },
    );
  }
}

class _PickerScaffoldBody extends StatelessWidget {
  const _PickerScaffoldBody({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Karşılaştır')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: child,
        ),
      ),
    );
  }
}

class _ComparisonCandidateCard extends StatelessWidget {
  const _ComparisonCandidateCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = _buildMetaLine(product);
    final preview = _buildPreviewLine(product);

    return Semantics(
      button: true,
      label:
          '${product.name}${meta != null ? '. $meta' : ''}${preview != null ? '. $preview' : ''}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FreshProductImage(
                  productId: product.id,
                  imageUrl: product.imageUrl,
                  size: 64,
                  padding: 6,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.18,
                        ),
                      ),
                      if (meta != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                      if (preview != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Padding(
                  padding: EdgeInsets.only(top: 22),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _buildMetaLine(Product product) {
    final parts = <String>[];
    final brand = product.brand?.trim();
    final quantity = extractProductQuantityLabel(product)?.trim();
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

  String? _buildPreviewLine(Product product) {
    final nutrition = product.nutrition;
    if (nutrition == null) {
      return null;
    }

    final parts = <String>[];
    if (nutrition.energyKcal != null) {
      parts.add('${nutrition.energyKcal!.toStringAsFixed(0)} kcal');
    }
    if (nutrition.sugars != null) {
      parts.add('Şeker ${_fmt(nutrition.sugars!)} g');
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' • ');
  }

  String _fmt(double value) {
    return value == value.truncateToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }
}

class _PickerMessageState extends StatelessWidget {
  const _PickerMessageState({
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => onAction!.call(),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductResolutionError extends StatelessWidget {
  const _ProductResolutionError();

  @override
  Widget build(BuildContext context) {
    return const _PickerMessageState(
      message: 'Ürünler yüklenemedi. Tekrar dene.',
      icon: Icons.error_outline,
    );
  }
}
