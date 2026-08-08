import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/comparison/controllers/product_comparison_controller.dart';
import 'package:food_analyzer_app/features/comparison/domain/comparison_metric.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/comparison/widgets/comparison_metric_row.dart';
import 'package:food_analyzer_app/features/comparison/widgets/comparison_product_header.dart';
import 'package:food_analyzer_app/features/comparison/widgets/comparison_section.dart';
import 'package:food_analyzer_app/features/product/controllers/product_analysis_controller.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/widgets/product_detail_shared.dart';

class ProductComparisonPage extends ConsumerWidget {
  const ProductComparisonPage({super.key, required this.routeArgs});

  final ProductComparisonRouteArgs routeArgs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceProduct = routeArgs.sourceProduct;
    final comparedProduct = routeArgs.comparedProduct;
    if (sourceProduct != null && comparedProduct != null) {
      return _ProductComparisonLoaded(
        sourceProduct: sourceProduct,
        comparedProduct: comparedProduct,
      );
    }

    final sourceAsync = ref.watch(
      productDetailByIdProvider(routeArgs.sourceProductId),
    );
    final comparedAsync = ref.watch(
      productDetailByIdProvider(routeArgs.comparedProductId),
    );

    if (sourceAsync.isLoading || comparedAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (sourceAsync.hasError || comparedAsync.hasError) {
      return _ComparisonErrorScaffold(
        onRetry: () {
          ref.invalidate(productDetailByIdProvider(routeArgs.sourceProductId));
          ref.invalidate(
            productDetailByIdProvider(routeArgs.comparedProductId),
          );
        },
      );
    }

    final resolvedSource = sourceAsync.value?.product;
    final resolvedCompared = comparedAsync.value?.product;
    if (resolvedSource == null || resolvedCompared == null) {
      return _ComparisonErrorScaffold(onRetry: () {});
    }

    return _ProductComparisonLoaded(
      sourceProduct: resolvedSource,
      comparedProduct: resolvedCompared,
    );
  }
}

class _ProductComparisonLoaded extends ConsumerStatefulWidget {
  const _ProductComparisonLoaded({
    required this.sourceProduct,
    required this.comparedProduct,
  });

  final Product sourceProduct;
  final Product comparedProduct;

  @override
  ConsumerState<_ProductComparisonLoaded> createState() =>
      _ProductComparisonLoadedState();
}

class _ProductComparisonLoadedState
    extends ConsumerState<_ProductComparisonLoaded> {
  @override
  Widget build(BuildContext context) {
    final config = ProductComparisonConfig(
      sourceProduct: widget.sourceProduct,
      comparedProduct: widget.comparedProduct,
    );
    final state = ref.watch(productComparisonControllerProvider(config));
    final controller = ref.read(
      productComparisonControllerProvider(config).notifier,
    );
    final comparison = state.comparison;
    final analysisA = comparison == null
        ? null
        : ref.watch(productAnalysisProvider(comparison.productA.product.id));
    final analysisB = comparison == null
        ? null
        : ref.watch(productAnalysisProvider(comparison.productB.product.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Ürün Karşılaştırma')),
      body: SafeArea(
        child: state.error != null && comparison == null
            ? _ComparisonErrorBody(
                onRetry: controller.retry,
                message: state.error!,
              )
            : comparison == null
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.isLoading) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                    ],
                    _ComparisonProductPairCard(
                      comparison: comparison,
                      onChangeProductB: _changeProductB,
                    ),
                    const SizedBox(height: 16),
                    ComparisonSection(
                      title: 'Besin değerleri',
                      icon: Icons.bar_chart_rounded,
                      accentColor: AppColors.primary,
                      child: _ComparisonNutritionSection(
                        comparison: comparison,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ComparisonSection(
                      title: 'İçindekiler ve riskler',
                      icon: Icons.restaurant_outlined,
                      accentColor: Colors.deepOrange,
                      child: _IngredientComparisonSection(
                        comparison: comparison,
                        leftAnalysis: analysisA?.valueOrNull,
                        rightAnalysis: analysisB?.valueOrNull,
                        leftIsLoading: analysisA?.isLoading ?? false,
                        rightIsLoading: analysisB?.isLoading ?? false,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ComparisonSection(
                      title: 'Alerjenler',
                      icon: Icons.warning_amber_outlined,
                      accentColor: Colors.amber,
                      child: _AllergenComparisonSection(
                        comparison: comparison,
                        leftAnalysis: analysisA?.valueOrNull,
                        rightAnalysis: analysisB?.valueOrNull,
                        leftIsLoading: analysisA?.isLoading ?? false,
                        rightIsLoading: analysisB?.isLoading ?? false,
                      ),
                    ),
                    if (analysisA?.hasError == true ||
                        analysisB?.hasError == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Bazı içerik özetleri hazırlanamadı; mevcut ürün verileri gösteriliyor.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _changeProductB() async {
    final selected = await context.pushNamed<Product>(
      'comparison_picker',
      pathParameters: {'id': widget.sourceProduct.id},
      extra: ComparisonPickerRouteArgs(
        sourceProductId: widget.sourceProduct.id,
        sourceProduct: widget.sourceProduct,
      ),
    );
    if (!mounted || selected == null) {
      return;
    }

    final config = ProductComparisonConfig(
      sourceProduct: widget.sourceProduct,
      comparedProduct: widget.comparedProduct,
    );
    await ref
        .read(productComparisonControllerProvider(config).notifier)
        .changeComparedProduct(selected);
  }
}

class _ComparisonProductPairCard extends StatelessWidget {
  const _ComparisonProductPairCard({
    required this.comparison,
    required this.onChangeProductB,
  });

  final ProductComparison comparison;
  final VoidCallback onChangeProductB;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ComparisonProductHeader(
                productData: comparison.productA,
                layout: ComparisonProductHeaderLayout.comparisonColumn,
                semanticLabel: 'Sol ürün özeti',
              ),
            ),
            const SizedBox(width: 14),
            VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
            const SizedBox(width: 14),
            Expanded(
              child: ComparisonProductHeader(
                productData: comparison.productB,
                layout: ComparisonProductHeaderLayout.comparisonColumn,
                onChangeProduct: onChangeProductB,
                semanticLabel: 'Sağ ürün özeti',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonNutritionSection extends StatelessWidget {
  const _ComparisonNutritionSection({required this.comparison});

  final ProductComparison comparison;

  @override
  Widget build(BuildContext context) {
    final basisA = comparison.productA.nutritionBasis.label;
    final basisB = comparison.productB.nutritionBasis.label;
    final sharesBasis =
        comparison.productA.nutritionBasis ==
        comparison.productB.nutritionBasis;
    final hasIncompatibleMetrics = comparison.metrics.any(
      (metric) => metric.outcome == ComparisonOutcome.notComparable,
    );
    final hasUnknownBasis = comparison.metrics.any(
      (metric) => metric.reason == kComparisonUnknownBasisReason,
    );
    final warningText = hasUnknownBasis
        ? 'Bazı değerlerin ölçüm temeli doğrulanamadığı için doğrudan karşılaştırma yapılamıyor.'
        : 'Bazı değerler farklı ölçüm temelleri nedeniyle doğrudan karşılaştırılamıyor.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sharesBasis)
          Text(
            basisA,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          )
        else
          Row(
            children: [
              const Expanded(flex: 14, child: SizedBox()),
              const SizedBox(width: 8),
              Expanded(
                flex: 9,
                child: Text(
                  basisA,
                  textAlign: TextAlign.left,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 9,
                child: Text(
                  basisB,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        if (hasIncompatibleMetrics) ...[
          const SizedBox(height: 4),
          Text(
            warningText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 6),
        for (var index = 0; index < comparison.metrics.length; index++)
          ComparisonMetricRow(
            metric: comparison.metrics[index],
            showDivider: index != comparison.metrics.length - 1,
          ),
      ],
    );
  }
}

class _IngredientComparisonSection extends StatelessWidget {
  const _IngredientComparisonSection({
    required this.comparison,
    required this.leftAnalysis,
    required this.rightAnalysis,
    required this.leftIsLoading,
    required this.rightIsLoading,
  });

  final ProductComparison comparison;
  final ProductAnalysisResult? leftAnalysis;
  final ProductAnalysisResult? rightAnalysis;
  final bool leftIsLoading;
  final bool rightIsLoading;

  @override
  Widget build(BuildContext context) {
    return _ComparisonColumns(
      leftChild: _IngredientPreviewColumn(
        productData: comparison.productA,
        analysisResult: leftAnalysis,
        isLoading: leftIsLoading,
        sheetTitle: comparison.productA.product.name,
      ),
      rightChild: _IngredientPreviewColumn(
        productData: comparison.productB,
        analysisResult: rightAnalysis,
        isLoading: rightIsLoading,
        sheetTitle: comparison.productB.product.name,
      ),
    );
  }
}

class _AllergenComparisonSection extends StatelessWidget {
  const _AllergenComparisonSection({
    required this.comparison,
    required this.leftAnalysis,
    required this.rightAnalysis,
    required this.leftIsLoading,
    required this.rightIsLoading,
  });

  final ProductComparison comparison;
  final ProductAnalysisResult? leftAnalysis;
  final ProductAnalysisResult? rightAnalysis;
  final bool leftIsLoading;
  final bool rightIsLoading;

  @override
  Widget build(BuildContext context) {
    return _ComparisonColumns(
      leftChild: _AllergenPreviewColumn(
        productData: comparison.productA,
        analysisResult: leftAnalysis,
        isLoading: leftIsLoading,
        sheetTitle: comparison.productA.product.name,
      ),
      rightChild: _AllergenPreviewColumn(
        productData: comparison.productB,
        analysisResult: rightAnalysis,
        isLoading: rightIsLoading,
        sheetTitle: comparison.productB.product.name,
      ),
    );
  }
}

class _ComparisonColumns extends StatelessWidget {
  const _ComparisonColumns({required this.leftChild, required this.rightChild});

  final Widget leftChild;
  final Widget rightChild;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: leftChild),
          const SizedBox(width: 14),
          VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
          const SizedBox(width: 14),
          Expanded(child: rightChild),
        ],
      ),
    );
  }
}

class _IngredientPreviewColumn extends StatelessWidget {
  const _IngredientPreviewColumn({
    required this.productData,
    required this.analysisResult,
    required this.isLoading,
    required this.sheetTitle,
  });

  final ComparisonProductData productData;
  final ProductAnalysisResult? analysisResult;
  final bool isLoading;
  final String sheetTitle;

  static const _previewCount = 5;

  @override
  Widget build(BuildContext context) {
    final items = buildComparisonRiskPreviewItems(
      analysisResult: analysisResult,
      fallbackIngredients: productData.ingredients,
    );
    final previewItems = items.take(_previewCount).toList(growable: false);
    final fallbackText = normalizeIngredientTextForDisplay(
      productData.product.ingredientsText,
    );
    final hasFallbackText = fallbackText != 'Bilgi yok';

    if (previewItems.isEmpty) {
      if (isLoading) {
        return _LoadingHint(text: 'İçerik özeti hazırlanıyor...');
      }
      return _FallbackTextColumn(
        text: fallbackText,
        showExpand: hasFallbackText && fallbackText.length > 160,
        onExpand: hasFallbackText
            ? () => _showRawTextSheet(
                context,
                title: sheetTitle,
                text: fallbackText,
              )
            : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in previewItems)
          _IngredientRiskRow(
            item: item,
            onTap: item.ingredient == null
                ? null
                : () => showIngredientDetailSheet(context, item.ingredient!),
          ),
        if (items.length > _previewCount) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => _showIngredientListSheet(
              context,
              title: sheetTitle,
              items: items,
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Tümünü gör'),
          ),
        ],
      ],
    );
  }

  void _showIngredientListSheet(
    BuildContext context, {
    required String title,
    required List<ProductRiskPreviewItem> items,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.82;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'İçindekiler ve riskler',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final summary = item.summary;
                      final riskMeta = [
                        riskLabelForUser(item.riskLevel),
                        if (item.categoryLabel != null) item.categoryLabel!,
                      ].join(' · ');
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: item.ingredient == null
                            ? null
                            : () => showIngredientDetailSheet(
                                context,
                                item.ingredient!,
                              ),
                        leading: Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: riskColorForUser(item.riskLevel),
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(
                          item.name,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (item.categoryIcon != null) ...[
                                  Icon(
                                    item.categoryIcon,
                                    size: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    riskMeta,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            if (summary != null && summary.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                summary,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                        trailing: item.ingredient == null
                            ? null
                            : const Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.textSecondary,
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRawTextSheet(
    BuildContext context, {
    required String title,
    required String text,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'İçindekiler metni',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.45),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IngredientRiskRow extends StatelessWidget {
  const _IngredientRiskRow({required this.item, required this.onTap});

  final ProductRiskPreviewItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final riskColor = riskColorForUser(item.riskLevel);
    final riskLabel = riskLabelForUser(item.riskLevel);
    final subtitleParts = [
      riskLabel,
      if (item.categoryLabel != null) item.categoryLabel!,
    ];

    return Semantics(
      button: onTap != null,
      label: onTap == null
          ? '${item.name}, $riskLabel.'
          : '${item.name}, $riskLabel. Detayları görmek için dokunun.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: riskColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.categoryIcon != null) ...[
                          Icon(
                            item.categoryIcon,
                            size: 13,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            subtitleParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
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

class _FallbackTextColumn extends StatelessWidget {
  const _FallbackTextColumn({
    required this.text,
    required this.showExpand,
    this.onExpand,
  });

  final String text;
  final bool showExpand;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    if (text == 'Bilgi yok') {
      return Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'İçindekiler metni',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text,
          maxLines: showExpand ? 6 : null,
          overflow: showExpand ? TextOverflow.ellipsis : null,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
        if (showExpand && onExpand != null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: onExpand,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Tümünü gör'),
          ),
        ],
      ],
    );
  }
}

class _AllergenPreviewColumn extends StatelessWidget {
  const _AllergenPreviewColumn({
    required this.productData,
    required this.analysisResult,
    required this.isLoading,
    required this.sheetTitle,
  });

  final ComparisonProductData productData;
  final ProductAnalysisResult? analysisResult;
  final bool isLoading;
  final String sheetTitle;

  static const _previewCount = 4;

  @override
  Widget build(BuildContext context) {
    final allergens = buildComparisonAllergenLabels(
      analysisResult: analysisResult,
      fallbackIngredients: productData.ingredients,
      rawIngredientText: productData.product.ingredientsText,
    );

    if (allergens == null) {
      if (isLoading) {
        return _LoadingHint(text: 'Alerjen özeti hazırlanıyor...');
      }
      return Text(
        'Bilgi yok',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    if (allergens.isEmpty) {
      return Text(
        'Etiket metninde alerjen eşleşmesi tespit edilmedi. Güncel ambalajı kontrol edin.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    final preview = allergens.take(_previewCount).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: preview
              .map((allergen) => _AllergenChip(label: allergen))
              .toList(growable: false),
        ),
        if (allergens.length > _previewCount) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _showAllergenSheet(
              context,
              title: sheetTitle,
              allergens: allergens,
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Tümünü gör'),
          ),
        ],
      ],
    );
  }

  void _showAllergenSheet(
    BuildContext context, {
    required String title,
    required List<String> allergens,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Etikette tespit edilen alerjenler',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: allergens
                    .map((allergen) => _AllergenChip(label: allergen))
                    .toList(growable: false),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AllergenChip extends StatelessWidget {
  const _AllergenChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Alerjen: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.amber[50],
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.amber[200]!),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.amber[900],
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _LoadingHint extends StatelessWidget {
  const _LoadingHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ComparisonErrorScaffold extends StatelessWidget {
  const _ComparisonErrorScaffold({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Ürün Karşılaştırma')),
      body: _ComparisonErrorBody(
        onRetry: onRetry,
        message: 'Ürünler yüklenemedi. Tekrar dene.',
      ),
    );
  }
}

class _ComparisonErrorBody extends StatelessWidget {
  const _ComparisonErrorBody({required this.onRetry, required this.message});

  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.danger, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Tekrar dene'),
            ),
          ],
        ),
      ),
    );
  }
}
