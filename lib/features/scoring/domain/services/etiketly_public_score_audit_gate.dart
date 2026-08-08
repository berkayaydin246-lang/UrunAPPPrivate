import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';

enum PublicScoreAuditStatus { matching, missing, stale, invalid }

class PublicScoreAuditDecision {
  const PublicScoreAuditDecision(this.status);

  final PublicScoreAuditStatus status;

  bool get mayDisplayNumericScore => status == PublicScoreAuditStatus.matching;
}

class EtiketlyPublicScoreAuditGate {
  const EtiketlyPublicScoreAuditGate({
    this.validator = const EtiketlyScoreAuditValidator(),
  });

  final EtiketlyScoreAuditValidator validator;

  PublicScoreAuditDecision evaluate({
    required EtiketlyScoreAuditSnapshot current,
    required EtiketlyScoreAuditSnapshot? trusted,
  }) {
    if (trusted == null) {
      return const PublicScoreAuditDecision(PublicScoreAuditStatus.missing);
    }
    if (!validator.validate(current).isValid ||
        !validator.validate(trusted).isValid) {
      return const PublicScoreAuditDecision(PublicScoreAuditStatus.invalid);
    }
    final matches =
        trusted.productId == current.productId &&
        trusted.inputFingerprint == current.inputFingerprint &&
        trusted.scoreVersion == current.scoreVersion &&
        trusted.nutritionMethodologyVersion ==
            current.nutritionMethodologyVersion &&
        trusted.nutritionTransformVersion ==
            current.nutritionTransformVersion &&
        trusted.additiveTransformVersion == current.additiveTransformVersion &&
        _close(
          trusted.nutritionResult.nutritionQuality,
          current.nutritionResult.nutritionQuality,
        ) &&
        _close(
          trusted.additiveResult.additiveQuality,
          current.additiveResult.additiveQuality,
        ) &&
        _close(trusted.nutritionContribution, current.nutritionContribution) &&
        _close(trusted.additiveContribution, current.additiveContribution) &&
        _close(trusted.finalScore, current.finalScore);
    return PublicScoreAuditDecision(
      matches ? PublicScoreAuditStatus.matching : PublicScoreAuditStatus.stale,
    );
  }

  bool _close(double left, double right) =>
      (left - right).abs() <= EtiketlyScoreAuditValidator.tolerance;
}
