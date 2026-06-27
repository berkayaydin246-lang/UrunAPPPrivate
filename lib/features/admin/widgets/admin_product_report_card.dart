import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/utils/turkish_date_time_formatter.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_summary.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

class AdminProductReportCard extends StatelessWidget {
  const AdminProductReportCard({
    super.key,
    required this.report,
    required this.onTap,
  });

  final AdminProductReportSummary report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final previewText = report.details?.trim();
    final statusStyle = _statusStyleFor(report.status);

    return Container(
      key: ValueKey('admin-report-card-${report.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft(),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ProductThumbnail(
                    productId: 'report-snapshot-${report.id}',
                    imageUrl: report.productImageSnapshot,
                    accentColor: AppColors.primary,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (report.productBrandSnapshot?.trim().isNotEmpty == true)
                      Text(
                        report.productBrandSnapshot!.trim().toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          letterSpacing: 0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      report.productNameSnapshot,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      report.type.labelTr,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (previewText != null && previewText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        previewText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusStyle.backgroundColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            report.status.labelTr,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: statusStyle.textColor),
                          ),
                        ),
                        Text(
                          formatTurkishRelativeDateTime(report.createdAt),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        if (report.evidenceImageCount > 0)
                          Text(
                            '${report.evidenceImageCount} görsel',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusStyle {
  const _StatusStyle({required this.backgroundColor, required this.textColor});

  final Color backgroundColor;
  final Color textColor;
}

_StatusStyle _statusStyleFor(ProductReportStatus status) {
  return switch (status) {
    ProductReportStatus.pending => const _StatusStyle(
      backgroundColor: AppColors.warningBg,
      textColor: AppColors.warningText,
    ),
    ProductReportStatus.reviewing => const _StatusStyle(
      backgroundColor: AppColors.infoBg,
      textColor: AppColors.infoText,
    ),
    ProductReportStatus.resolved => const _StatusStyle(
      backgroundColor: AppColors.successBg,
      textColor: AppColors.successText,
    ),
    ProductReportStatus.rejected => const _StatusStyle(
      backgroundColor: AppColors.dangerBg,
      textColor: AppColors.dangerText,
    ),
  };
}
