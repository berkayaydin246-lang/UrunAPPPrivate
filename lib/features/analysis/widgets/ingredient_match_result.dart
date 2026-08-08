import 'package:flutter/material.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient_detail.dart';
import 'package:food_analyzer_app/features/analysis/pages/ingredient_detail_page.dart';
import 'package:food_analyzer_app/shared/widgets/ingredient_explanation_card.dart';

/// Widget to display a single ingredient match result
class IngredientMatchItem extends StatelessWidget {
  final IngredientMatch match;
  final bool showConfidence;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  const IngredientMatchItem({
    super.key,
    required this.match,
    this.showConfidence = true,
    this.onApprove,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final canonicalIngredient = match.matchedIngredient == null
        ? null
        : const CanonicalIngredientRiskService()
              .assessIngredient(match.matchedIngredient!)
              .ingredient;
    // Determine confidence category
    Color confidenceColor() {
      final c = match.confidenceScore;
      if (c >= 0.9) return Colors.green[700]!;
      if (c >= 0.7) return Colors.orange[700]!;
      return Colors.red[600]!;
    }

    return Container(
      padding: const EdgeInsets.all(12.0),
      margin: const EdgeInsets.only(bottom: 8.0),
      decoration: BoxDecoration(
        color: match.isConfirmed
            ? Colors.green[50]
            : match.needsUserConfirmation
            ? Colors.amber[50]
            : Colors.grey[50],
        border: Border.all(
          color: match.isConfirmed
              ? Colors.green[300]!
              : match.needsUserConfirmation
              ? Colors.amber[300]!
              : Colors.grey[300]!,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Original text and match status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      match.originalToken,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: match.isConfirmed
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (match.normalizedText != match.originalToken)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          '→ ${match.normalizedText}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ),
                  ],
                ),
              ),
              // Match status icon
              if (match.isConfirmed)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green[600],
                    size: 20,
                  ),
                )
              else if (match.needsUserConfirmation)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(
                    Icons.help_outline,
                    color: Colors.amber[700],
                    size: 20,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(
                    Icons.help_outline,
                    color: Colors.amber[600],
                    size: 20,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Matched ingredient info
          if (match.matchedIngredient != null) ...[
            Text(
              'OCR: ${match.originalToken}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            if (match.matchedToken != null)
              Text(
                'Matched token: ${match.matchedToken}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
              ),
            if (match.matchedToken != null) const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                // Open detail page
                final detail = IngredientDetail(match.matchedIngredient!);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => IngredientDetailPage(detail: detail),
                  ),
                );
              },
              child: Text(
                'Matched: ${match.matchedIngredient!.name}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: match.isConfirmed
                      ? Colors.green[700]
                      : Colors.orange[700],
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Risk level badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: canonicalIngredient?.getRiskLevelColor().withAlpha(51),
                border: Border.all(
                  color:
                      canonicalIngredient?.getRiskLevelColor() ?? Colors.grey,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Risk: ${canonicalIngredient?.getRiskLevelTurkish() ?? 'Bilinmiyor'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: canonicalIngredient?.getRiskLevelColor(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Ingredient explanation metadata
            IngredientExplanationCard(match: match),
            const SizedBox(height: 4),
            // E-code if exists
            if (match.matchedIngredient!.eCode != null)
              Text(
                'E-Kodu: ${match.matchedIngredient!.eCode}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
          ],
          // Confidence score
          if (showConfidence)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: confidenceColor(),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Confidence: %${(match.confidenceScore * 100).toStringAsFixed(0)}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          if (match.needsUserConfirmation &&
              (onApprove != null || onReject != null)) ...[
            const SizedBox(height: 10),
            Text(
              'Bu içerik etikette net okunamadı. Lütfen kontrol edin.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.amber[900]),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (onApprove != null)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onApprove,
                      child: const Text('Onayla'),
                    ),
                  ),
                if (onApprove != null && onReject != null)
                  const SizedBox(width: 8),
                if (onReject != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text('Reddet'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Widget to display ingredient matching results
class IngredientMatchResultView extends StatelessWidget {
  final IngredientMatchingResult result;
  final VoidCallback? onRetry;
  final void Function(String originalToken, bool approved)? onDecision;

  const IngredientMatchResultView({
    super.key,
    required this.result,
    this.onRetry,
    this.onDecision,
  });

  @override
  Widget build(BuildContext context) {
    final matched = result.getConfirmedMatches();
    final review = result.getLowConfidenceMatches();
    final unmatched = result.getUnmatched();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary stats
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              border: Border.all(color: Colors.blue[200]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Toplam İçerik',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      result.totalIngredients.toString(),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: Colors.blue[700]),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tanınan %',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      '${result.getMatchPercentage()}%',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: Colors.green[700]),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ort. Güven',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      '${(result.averageConfidence * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: Colors.orange[700]),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Matched ingredients section
          if (matched.isNotEmpty) ...[
            Text(
              'Tespit Edilen Önemli İçerikler (${matched.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.green[700]),
            ),
            const SizedBox(height: 12),
            ...matched.map(
              (m) => IngredientMatchItem(match: m, showConfidence: true),
            ),
            const SizedBox(height: 24),
          ],
          if (review.isNotEmpty) ...[
            Text(
              'Kontrol Edilmesi Gereken Eşleşmeler (${review.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.amber[800]),
            ),
            const SizedBox(height: 12),
            ...review.map(
              (m) => IngredientMatchItem(
                match: m,
                showConfidence: true,
                onApprove: onDecision == null
                    ? null
                    : () => onDecision!(m.originalToken, true),
                onReject: onDecision == null
                    ? null
                    : () => onDecision!(m.originalToken, false),
              ),
            ),
            const SizedBox(height: 24),
          ],
          // Unmatched ingredients section
          if (unmatched.isNotEmpty) ...[
            Text(
              'Bilinmeyen İçerikler (${unmatched.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.amber[700]),
            ),
            const SizedBox(height: 12),
            ...unmatched.map(
              (m) => IngredientMatchItem(match: m, showConfidence: true),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Bu içerikler veritabanımızda bulunmamaktadır. Daha sonra eklenebilir.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.amber[900]),
              ),
            ),
          ],
          const SizedBox(height: 24),
          // Action buttons
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Analizi Başlat'),
              onPressed: () {
                // Continue to analysis/scoring (Task 12)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ürün analizi özelliği yakında açılacak'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
