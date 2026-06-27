import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';

/// A card with an icon header and arbitrary child content.
///
/// Used in product detail for consumption notes, missing-data messages, and
/// analysis info sections — replacing the ad-hoc Container+Row+icon patterns
/// duplicated across those widgets.
class FreshInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accentColor;
  final Widget child;

  const FreshInfoCard({
    super.key,
    required this.icon,
    required this.title,
    this.accentColor = AppColors.info,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
        boxShadow: AppShadows.soft(accentColor),
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
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
