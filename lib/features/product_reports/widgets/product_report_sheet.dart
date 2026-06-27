import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product_reports/controllers/product_report_form_controller.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

class ProductReportSheet extends ConsumerStatefulWidget {
  final Product product;

  const ProductReportSheet({super.key, required this.product});

  @override
  ConsumerState<ProductReportSheet> createState() => _ProductReportSheetState();
}

class _ProductReportSheetState extends ConsumerState<ProductReportSheet> {
  late final TextEditingController _detailsController;

  @override
  void initState() {
    super.initState();
    _detailsController = TextEditingController();
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = productReportFormProvider(widget.product.id);
    final formState = ref.watch(provider);

    ref.listen<ReportFormState>(provider, (previous, next) {
      if (next.status == ReportSubmissionStatus.success && mounted) {
        Navigator.pop(context, true);
      }
    });

    final isSubmitting = formState.status == ReportSubmissionStatus.submitting;

    return Semantics(
      label: 'Bildirim formu',
      child: Container(
        key: const Key('report-sheet'),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

                // Sheet header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ürün bilgisi bildir',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Hangi bilginin hatalı veya güncel olmadığını seç.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: 'Bildirim formunu kapat',
                      button: true,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        color: AppColors.textSecondary,
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Compact product header
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.neutralBg,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: ColoredBox(
                            color: AppColors.surface,
                            child: ProductThumbnail(
                              productId: widget.product.id,
                              imageUrl: widget.product.imageUrl,
                              accentColor: AppColors.primary,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.product.brand?.isNotEmpty == true)
                              Text(
                                widget.product.brand!,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            Text(
                              widget.product.name,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Report type list
                Text(
                  'Hata türü',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ...ProductReportType.values.map(
                  (type) => _ReportTypeRow(
                    type: type,
                    selected: formState.selectedType == type,
                    onTap: isSubmitting
                        ? null
                        : () => ref.read(provider.notifier).selectType(type),
                  ),
                ),

                const SizedBox(height: 16),

                // Details field
                TextField(
                  key: const Key('report-details-field'),
                  controller: _detailsController,
                  onChanged: (v) =>
                      ref.read(provider.notifier).updateDetails(v),
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 1000,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    labelText: 'Açıklama (isteğe bağlı)',
                    hintText: 'Hatanın ne olduğunu kısaca açıklayabilirsin.',
                    alignLabelWithHint: true,
                    counterStyle: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                    helperText:
                        formState.selectedType == ProductReportType.other
                        ? 'Diğer seçeneğinde açıklama zorunludur.'
                        : null,
                    helperStyle: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.warning),
                  ),
                ),

                // Error message
                if (formState.errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.dangerBg,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.24),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: AppColors.danger,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            formState.errorMessage!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.dangerText),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 18),

                // Submit button
                Semantics(
                  label: 'Bildirim gönder',
                  child: ElevatedButton(
                    key: const Key('report-submit-button'),
                    onPressed: formState.canSubmit ? _submit : null,
                    child: isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Bildirim gönder'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    await ref
        .read(productReportFormProvider(widget.product.id).notifier)
        .submit();
  }
}

class _ReportTypeRow extends StatelessWidget {
  final ProductReportType type;
  final bool selected;
  final VoidCallback? onTap;

  const _ReportTypeRow({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.primary : AppColors.neutral,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                type.labelTr,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
