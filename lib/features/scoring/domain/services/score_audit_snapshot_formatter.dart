import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';

class ScoreAuditSnapshotFormatter {
  const ScoreAuditSnapshotFormatter();

  String format(EtiketlyScoreAuditSnapshot snapshot) {
    final captured =
        snapshot.capturedAt?.toUtc().toIso8601String() ??
        'persistence timestamp unavailable';
    final additives = snapshot.canonicalAdditives.isEmpty
        ? 'none'
        : snapshot.canonicalAdditives
              .map(
                (item) =>
                    '${item.canonicalName} (${item.canonicalKey}): '
                    '${item.riskLevelAtCalculationTime}, '
                    'penalty=${item.penaltyContribution}',
              )
              .join('; ');
    return [
      'Product: ${snapshot.productId}',
      'Snapshot date: $captured',
      'Score: ${snapshot.finalScore}',
      'Display: ${snapshot.displayScore}',
      'Nutrition quality: ${snapshot.nutritionResult.nutritionQuality}',
      'Additive quality: ${snapshot.additiveResult.additiveQuality}',
      'Versions: ${snapshot.scoreVersion}, '
          '${snapshot.nutritionMethodologyVersion}, '
          '${snapshot.nutritionTransformVersion}, '
          '${snapshot.additiveTransformVersion}',
      'Canonical additives at time: $additives',
      'Input fingerprint: ${snapshot.inputFingerprint}',
    ].join('\n');
  }
}
