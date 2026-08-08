import 'package:flutter/material.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';

/// Widget to display ingredient educational explanations
/// Shows: type, purpose, risk summary, and caution groups
class IngredientExplanationCard extends StatelessWidget {
  final IngredientMatch match;

  const IngredientExplanationCard({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    if (!match.hasExplanationMetadata()) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ingredient type and processing role (always visible)
        _buildTypeSection(context),
        const SizedBox(height: 8),
        // Short purpose
        if (match.getShortPurpose() != null) _buildPurposeSection(context),
        if (match.getShortPurpose() != null) const SizedBox(height: 8),
        // Short risk summary
        if (match.getShortRiskSummary() != null)
          _buildRiskSummarySection(context),
        if (match.getShortRiskSummary() != null) const SizedBox(height: 8),
        // Caution groups
        if ((match.getCautionGroups()?.isNotEmpty ?? false))
          _buildCautionGroupsSection(context),
        if ((match.getCautionGroups()?.isNotEmpty ?? false))
          const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTypeSection(BuildContext context) {
    final type = match.getIngredientType();
    final role = match.getProcessingRole();

    if (type == null && role == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border.all(color: Colors.blue[200]!),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (type != null)
            Text(
              type,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.blue[800],
                fontWeight: FontWeight.w600,
              ),
            ),
          if (type != null && role != null) const SizedBox(height: 4),
          if (role != null)
            Text(
              role,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.blue[700]),
            ),
        ],
      ),
    );
  }

  Widget _buildPurposeSection(BuildContext context) {
    final purpose = match.getShortPurpose();
    if (purpose == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.teal[50],
        border: Border.all(color: Colors.teal[200]!),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kullanım Amacı',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.teal[800],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            purpose,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.teal[900]),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskSummarySection(BuildContext context) {
    final summary = match.getShortRiskSummary();
    if (summary == null) return const SizedBox.shrink();

    final ingredient = match.matchedIngredient;
    final riskLevel = ingredient == null
        ? 'unknown'
        : const CanonicalIngredientRiskService()
              .assessIngredient(ingredient)
              .riskLevelName;
    Color bgColor;
    Color borderColor;
    Color textColor;

    switch (riskLevel) {
      case 'high':
        bgColor = Colors.red[50]!;
        borderColor = Colors.red[200]!;
        textColor = Colors.red[900]!;
        break;
      case 'medium':
        bgColor = Colors.amber[50]!;
        borderColor = Colors.amber[200]!;
        textColor = Colors.amber[900]!;
        break;
      case 'low':
      default:
        bgColor = Colors.green[50]!;
        borderColor = Colors.green[200]!;
        textColor = Colors.green[900]!;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Önemli Bilgi',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildCautionGroupsSection(BuildContext context) {
    final groups = match.getCautionGroups();
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border.all(color: Colors.orange[200]!),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dikkat Edilmesi Gereken Gruplar',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.orange[800],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: groups
                .map(
                  (group) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      border: Border.all(color: Colors.orange[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      group,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.orange[900],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
