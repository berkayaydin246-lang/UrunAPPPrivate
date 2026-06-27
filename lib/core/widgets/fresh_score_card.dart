import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';

/// Data completeness level for a product.
enum DataCompletenessLevel {
  /// Both ingredients text and nutrition data are present.
  full,

  /// Only one of ingredients or nutrition is present.
  partial,

  /// Neither ingredients nor nutrition is available.
  noData,
}

/// Displays a product's data-completeness status as a compact banner.
///
/// Distinct from a health/risk score — this reflects how much data the
/// app has for this product, not whether it is safe to eat.
class FreshScoreCard extends StatelessWidget {
  final DataCompletenessLevel level;
  final String? customLabel;
  final String? detail;

  const FreshScoreCard({
    super.key,
    required this.level,
    this.customLabel,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (level) {
      DataCompletenessLevel.full => (
        customLabel ?? 'Tam Veri',
        Icons.check_circle_outline_rounded,
        AppColors.success,
      ),
      DataCompletenessLevel.partial => (
        customLabel ?? 'Kısmi Veri',
        Icons.info_outline_rounded,
        AppColors.warning,
      ),
      DataCompletenessLevel.noData => (
        customLabel ?? 'Veri Eksik',
        Icons.block_outlined,
        AppColors.neutral,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color.withValues(alpha: 0.85),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
