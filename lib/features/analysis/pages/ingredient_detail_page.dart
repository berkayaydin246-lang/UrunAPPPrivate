import 'package:flutter/material.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';
import 'package:food_analyzer_app/features/product/models/ingredient_detail.dart';

class IngredientDetailPage extends StatelessWidget {
  final IngredientDetail detail;

  const IngredientDetailPage({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final resolvedDetail = IngredientDetail(
      enrichIngredientKnowledge(detail.ingredient),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Bu içerik nedir?')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                resolvedDetail.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              if (resolvedDetail.shortDescription.isNotEmpty) ...[
                Text(
                  resolvedDetail.shortDescription,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.longDescription.isNotEmpty) ...[
                Text(
                  resolvedDetail.longDescription,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              // New explanation metadata sections
              if (resolvedDetail.ingredientType != null) ...[
                container(
                  context: context,
                  title: 'Tür / Kategorisi',
                  content: resolvedDetail.ingredientType!,
                  bgColor: Colors.blue[50]!,
                  borderColor: Colors.blue[200]!,
                  textColor: Colors.blue[900]!,
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.shortPurpose != null) ...[
                container(
                  context: context,
                  title: 'Kullanım Amacı',
                  content: resolvedDetail.shortPurpose!,
                  bgColor: Colors.teal[50]!,
                  borderColor: Colors.teal[200]!,
                  textColor: Colors.teal[900]!,
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.processingRole != null) ...[
                container(
                  context: context,
                  title: 'İşleme Rolü',
                  content: resolvedDetail.processingRole!,
                  bgColor: Colors.cyan[50]!,
                  borderColor: Colors.cyan[200]!,
                  textColor: Colors.cyan[900]!,
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.shortRiskSummary != null) ...[
                container(
                  context: context,
                  title: 'Önemli Bilgi',
                  content: resolvedDetail.shortRiskSummary!,
                  bgColor: Colors.amber[50]!,
                  borderColor: Colors.amber[200]!,
                  textColor: Colors.amber[900]!,
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.cautionGroups != null &&
                  resolvedDetail.cautionGroups!.isNotEmpty) ...[
                Text(
                  'Dikkat Edilmesi Gereken Gruplar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: resolvedDetail.cautionGroups!
                      .map(
                        (group) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            border: Border.all(color: Colors.orange[300]!),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            group,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: Colors.orange[900]),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.additiveGroup != null) ...[
                Text(
                  'Katkı Grubu',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  resolvedDetail.additiveGroup!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.aliases.isNotEmpty) ...[
                Text(
                  'Diğer İsimler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: resolvedDetail.aliases
                      .map((a) => Chip(label: Text(a)))
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.englishNames.isNotEmpty) ...[
                Text(
                  'İngilizce İsimler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: resolvedDetail.englishNames
                      .map((a) => Chip(label: Text(a)))
                      .toList(),
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.childWarning != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    border: Border.all(color: Colors.amber[200]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Çocuklara Dikkat',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: Colors.amber[800]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        resolvedDetail.childWarning!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (resolvedDetail.sourceReferences.isNotEmpty) ...[
                Text(
                  'Kaynaklar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...resolvedDetail.sourceReferences.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Text(
                      r,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.blue),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget container({
    required BuildContext context,
    required String title,
    required String content,
    required Color bgColor,
    required Color borderColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: textColor),
          ),
        ],
      ),
    );
  }
}
