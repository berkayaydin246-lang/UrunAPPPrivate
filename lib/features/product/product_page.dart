import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/widgets/analysis_result_widget.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/product/controllers/product_analysis_controller.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/user_library/controllers/user_product_library_controller.dart';
import 'package:food_analyzer_app/features/product_reports/widgets/product_report_card.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';

class ProductScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  String? _recordedProductId;
  ProviderSubscription<AsyncValue<ProductDetailState>>?
  _productDetailSubscription;

  @override
  void initState() {
    super.initState();
    _listenForViewedProduct();
  }

  @override
  void didUpdateWidget(covariant ProductScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId) {
      _recordedProductId = null;
      _productDetailSubscription?.close();
      _listenForViewedProduct();
    }
  }

  @override
  void dispose() {
    _productDetailSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(productDetailByIdProvider(widget.productId));
    final analysisAsync = ref.watch(productAnalysisProvider(widget.productId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ürün Detayı'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [_ProductFavoriteAction(productId: widget.productId)],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.danger,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ürün yüklenemedi',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Yeniden Yükle'),
                  onPressed: () {
                    // ignore: unused_result
                    ref.refresh(productDetailByIdProvider(widget.productId));
                  },
                ),
              ],
            ),
          ),
        ),
        data: (detail) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProductHeader(product: detail.product!),
              const SizedBox(height: 14),
              _ComparisonEntryCard(
                product: detail.product!,
                onCompare: () => _startComparison(detail.product!),
              ),
              const SizedBox(height: 24),
              _AnalysisSection(
                analysisAsync: analysisAsync,
                productId: widget.productId,
                nutritionData: detail.product!.nutrition,
              ),
              const SizedBox(height: 24),
              ProductReportCard(product: detail.product!),
            ],
          ),
        ),
      ),
    );
  }

  void _listenForViewedProduct() {
    _productDetailSubscription = ref
        .listenManual<AsyncValue<ProductDetailState>>(
          productDetailByIdProvider(widget.productId),
          (previous, next) {
            next.whenData((detail) {
              final product = detail.product;
              if (product != null) {
                _recordViewedProduct(product);
              }
            });
          },
          fireImmediately: true,
        );
  }

  void _recordViewedProduct(Product product) {
    if (_recordedProductId == product.id) {
      return;
    }

    _recordedProductId = product.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      unawaited(
        ref
            .read(recentProductActivityProvider.notifier)
            .recordViewedProduct(localSnapshotFromProduct(product))
            .catchError((Object error, StackTrace stackTrace) {
              if (!kDebugMode) return;
              debugPrint(
                '[UserLibrary] failed to record viewed product ${product.id}: '
                '$error',
              );
            }),
      );
    });
  }

  Future<void> _startComparison(Product product) async {
    if (product.id.trim().isEmpty) {
      return;
    }

    final selected = await context.pushNamed<Product>(
      'comparison_picker',
      pathParameters: {'id': product.id},
      extra: ComparisonPickerRouteArgs(
        sourceProductId: product.id,
        sourceProduct: product,
      ),
    );
    if (!mounted || selected == null || selected.id == product.id) return;

    await context.pushNamed(
      'product_comparison',
      pathParameters: {'id': product.id, 'otherId': selected.id},
      extra: ProductComparisonRouteArgs(
        sourceProductId: product.id,
        comparedProductId: selected.id,
        sourceProduct: product,
        comparedProduct: selected,
      ),
    );
  }
}

class _ProductFavoriteAction extends ConsumerStatefulWidget {
  final String productId;

  const _ProductFavoriteAction({required this.productId});

  @override
  ConsumerState<_ProductFavoriteAction> createState() =>
      _ProductFavoriteActionState();
}

class _ProductFavoriteActionState
    extends ConsumerState<_ProductFavoriteAction> {
  bool _isSaving = false;
  bool? _optimisticFavorite;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(productDetailByIdProvider(widget.productId));
    final isFavorite = ref.watch(isProductFavoriteProvider(widget.productId));
    final resolvedIsFavorite = _optimisticFavorite ?? isFavorite;
    final semanticLabel = resolvedIsFavorite
        ? 'Favorilerden çıkar'
        : 'Favorilere ekle';

    return detailAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (detail) {
        final product = detail.product;
        if (product == null) {
          return const SizedBox.shrink();
        }

        return IconButton(
          key: const ValueKey('product-favorite-action'),
          tooltip: semanticLabel,
          onPressed: _isSaving
              ? null
              : () => _toggleFavorite(
                  product,
                  currentlyFavorite: resolvedIsFavorite,
                ),
          icon: Icon(
            resolvedIsFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: resolvedIsFavorite ? AppColors.danger : AppColors.primary,
          ),
        );
      },
    );
  }

  Future<void> _toggleFavorite(
    Product product, {
    required bool currentlyFavorite,
  }) async {
    final nextFavorite = !currentlyFavorite;

    setState(() {
      _isSaving = true;
      _optimisticFavorite = nextFavorite;
    });

    try {
      final finalState = await ref
          .read(favoriteProductsProvider.notifier)
          .toggleFavorite(localSnapshotFromProduct(product));

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _optimisticFavorite = null;
      });

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            finalState ? 'Favorilere eklendi' : 'Favorilerden çıkarıldı',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _optimisticFavorite = null;
      });

      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Değişiklik kaydedilemedi. Tekrar deneyin.'),
        ),
      );
    }
  }
}

class _ProductHeader extends StatelessWidget {
  final Product product;

  const _ProductHeader({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.32,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: product.imageUrl != null
                  ? Image.network(
                      product.imageUrl!,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => _imagePlaceholder(),
                    )
                  : _imagePlaceholder(),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            product.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(height: 1.08),
          ),
          if (product.brand != null && product.brand!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              product.brand!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: const Icon(
        Icons.image_not_supported,
        size: 48,
        color: AppColors.neutral,
      ),
    );
  }
}

class _ComparisonEntryCard extends StatelessWidget {
  const _ComparisonEntryCard({required this.product, required this.onCompare});

  final Product product;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    final enabled = product.id.trim().isNotEmpty;
    final button = OutlinedButton.icon(
      key: const ValueKey('product-compare-button'),
      onPressed: enabled ? onCompare : null,
      icon: const Icon(Icons.compare_arrows_rounded),
      label: const Text('Karşılaştır'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ürünü karşılaştır',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Aynı kategorideki benzer bir ürünle yan yana incele.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );

          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                textContent,
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: textContent),
              const SizedBox(width: 12),
              Flexible(fit: FlexFit.loose, child: button),
            ],
          );
        },
      ),
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  final AsyncValue<ProductAnalysisResult?> analysisAsync;
  final String productId;
  final NutritionData? nutritionData;

  const _AnalysisSection({
    required this.analysisAsync,
    required this.productId,
    this.nutritionData,
  });

  @override
  Widget build(BuildContext context) {
    return analysisAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.24)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Analiz yüklenemedi: ${error.toString()}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
      data: (result) {
        // Case (a): no analysis AND no nutrition → missing-data messages + OCR
        if (result == null &&
            (nutritionData == null || !nutritionData!.hasAnyData)) {
          return const _MissingDataCard();
        }

        // Case (b): no analysis BUT nutrition exists → nutrition-only view
        if (result == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.24),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.warningText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'İçindekiler bilgisi henüz eklenmemiş',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.warningText,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Besin değerleri aşağıda gösterilmektedir. '
                            'İçindekiler etiketini fotoğraflayarak içerik analizi yapabilirsiniz.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.warningText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              NutritionSectionCard(nutritionData: nutritionData!),
              const SizedBox(height: 10),
              _ConsumptionNoteCard(nutritionData: nutritionData),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('İçindekileri Fotoğrafla'),
                  onPressed: () => context.push('/ocr'),
                ),
              ),
            ],
          );
        }

        // Case (c): analysis exists → full widget + consumption note
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnalysisResultWidget(
              result: result,
              displayMode: AnalysisDisplayMode.barcode,
              nutritionData: nutritionData,
              onLowConfidenceDecision: null,
            ),
            const SizedBox(height: 10),
            _ConsumptionNoteCard(result: result, nutritionData: nutritionData),
          ],
        );
      },
    );
  }
}

/// Consumption note card built from deterministic ingredient + nutrition signals.
///
/// [result] may be null when only nutrition data is available (no ingredient
/// analysis). In that case notes are derived from nutrition signals only.
class _ConsumptionNoteCard extends StatelessWidget {
  final ProductAnalysisResult? result;
  final NutritionData? nutritionData;

  const _ConsumptionNoteCard({this.result, this.nutritionData});

  @override
  Widget build(BuildContext context) {
    final effectiveResult =
        result ??
        ProductAnalysisResult(scoreLabel: AnalysisScoreLabel.orta, summary: '');
    final notes = buildConsumptionNotes(effectiveResult, nutritionData);
    if (notes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.14)),
        boxShadow: AppShadows.soft(AppColors.info),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.tips_and_updates_outlined,
                  color: AppColors.info,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Tüketim Notu',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...notes.map(
            (note) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                note,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when a product has neither ingredient analysis nor nutrition data.
///
/// Displays specific "henüz eklenmemiş" messages for each missing field so
/// the user knows the product exists but data is incomplete, then offers the
/// OCR scan path to contribute the missing ingredients.
class _MissingDataCard extends StatelessWidget {
  const _MissingDataCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ürün bilgileri eksik',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.warningText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MissingRow(
            icon: Icons.list_alt_outlined,
            text: 'İçindekiler bilgisi henüz eklenmemiş',
            color: AppColors.warning,
          ),
          const SizedBox(height: 6),
          _MissingRow(
            icon: Icons.bar_chart_outlined,
            text: 'Besin değerleri henüz eklenmemiş',
            color: AppColors.warning,
          ),
          const SizedBox(height: 16),
          Text(
            'İçindekiler etiketini fotoğraflayarak analiz başlatabilirsiniz.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.warningText),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Fotoğrafla Tara'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white,
              ),
              onPressed: () => context.push('/ocr'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _MissingRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.warningText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
