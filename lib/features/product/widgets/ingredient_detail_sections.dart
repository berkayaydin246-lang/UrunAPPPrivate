import 'package:flutter/material.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/ingredient_risk_reference.dart';

class IngredientDetailSections extends StatelessWidget {
  const IngredientDetailSections({
    super.key,
    required this.ingredient,
    this.spacing = 14,
    this.disclaimer = 'Bilgilendirme amaçlıdır; tıbbi tavsiye değildir.',
  });

  final Ingredient ingredient;
  final double spacing;
  final String disclaimer;

  @override
  Widget build(BuildContext context) {
    final resolvedIngredient = enrichIngredientKnowledge(ingredient);
    final hasMetadata = ingredientHasExplanationMetadata(resolvedIngredient);
    final references = _displayReferencesFor(resolvedIngredient);
    final displayCode = isValidFoodAdditiveCode(resolvedIngredient.eCode)
        ? resolvedIngredient.eCode!.trim().toUpperCase()
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasMetadata)
          Text(
            'Bu içerik için detaylı açıklama henüz eklenmedi.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        if (displayCode != null) ...[
          _DetailBlock(
            title: 'E-kodu',
            child: _CodeChip(code: displayCode),
          ),
          SizedBox(height: spacing),
        ],
        if (resolvedIngredient.shortPurpose?.trim().isNotEmpty ?? false) ...[
          _DetailBlock(
            title: 'Ne için kullanılır?',
            child: Text(
              resolvedIngredient.shortPurpose!.trim(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
          SizedBox(height: spacing),
        ],
        if (resolvedIngredient.shortRiskSummary?.trim().isNotEmpty ??
            false) ...[
          _DetailBlock(
            title: 'Neden dikkat edilmeli?',
            child: Text(
              resolvedIngredient.shortRiskSummary!.trim(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
          SizedBox(height: spacing),
        ],
        if (resolvedIngredient.cautionGroups?.isNotEmpty ?? false) ...[
          Text(
            'Dikkat grupları',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: resolvedIngredient.cautionGroups!
                .map((group) => _CautionChip(label: group))
                .toList(growable: false),
          ),
          SizedBox(height: spacing),
        ],
        if (resolvedIngredient.processingRole?.trim().isNotEmpty ?? false) ...[
          _DetailBlock(
            title: 'İşlenmişlik notu',
            child: Text(
              resolvedIngredient.processingRole!.trim(),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
          SizedBox(height: spacing),
        ],
        if (references.isNotEmpty) ...[
          Text(
            'Kaynaklar',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...references.map(
            (reference) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ReferenceCard(reference: reference),
            ),
          ),
          SizedBox(height: spacing - 2),
        ],
        Text(
          disclaimer,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  List<IngredientRiskReference> _displayReferencesFor(Ingredient ingredient) {
    final structured = ingredient.sourceReferenceEntries;
    if (structured != null && structured.isNotEmpty) {
      return structured;
    }

    final raw = ingredient.sourceReferences ?? const <String>[];
    return raw
        .where((value) => value.trim().isNotEmpty)
        .map((value) {
          final parts = value.split('—');
          if (parts.length >= 2) {
            return IngredientRiskReference(
              authority: parts.first.trim(),
              title: parts.sublist(1).join('—').trim(),
              url: ingredient.sourceUrl ?? '',
              accessedAt: DateTime.utc(1970),
            );
          }
          return IngredientRiskReference(
            authority: 'Kaynak',
            title: value.trim(),
            url: ingredient.sourceUrl ?? '',
            accessedAt: DateTime.utc(1970),
          );
        })
        .toList(growable: false);
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Text(
        code,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CautionChip extends StatelessWidget {
  const _CautionChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.24)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.reference});

  final IngredientRiskReference reference;

  @override
  Widget build(BuildContext context) {
    final hasMeta =
        (reference.documentCode?.trim().isNotEmpty ?? false) ||
        (reference.note?.trim().isNotEmpty ?? false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reference.authority,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            reference.title,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
          if (hasMeta) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (reference.documentCode?.trim().isNotEmpty ?? false)
                  _ReferenceMetaChip(label: reference.documentCode!.trim()),
                if (reference.note?.trim().isNotEmpty ?? false)
                  _ReferenceMetaChip(label: reference.note!.trim()),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReferenceMetaChip extends StatelessWidget {
  const _ReferenceMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
