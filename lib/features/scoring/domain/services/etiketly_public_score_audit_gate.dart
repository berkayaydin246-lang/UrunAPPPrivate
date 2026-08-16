import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';

enum PublicScoreAuditStatus {
  matching,
  missing,
  stale,
  invalid,

  /// Section E of the basis remediation pass: the score is otherwise
  /// structurally valid and fingerprint-matching, but at least one of the
  /// two snapshots being compared carries nutrition-basis evidence whose
  /// provenance is not independently trusted (never proven exactly, or a
  /// legacy pre-remediation snapshot with no provenance recorded at all —
  /// see [ScoreAuditResolvedInputSnapshot.nutritionBasisProvenance]). This
  /// is evidence currentness, not score mathematics: nothing about
  /// etiketly_score_v2/the transforms/the weighting changes here. Never
  /// mutates the historical snapshot — it simply may not be displayed as
  /// current until basis is independently revalidated.
  basisUnverified,
}

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

  // The only three provenance values that can ever mean "the exact g/mL
  // unit was genuinely proven or deterministically, controllably inferred"
  // — see legacy_scoring_evidence_recovery.dart (declaredLabel,
  // source-proven), scoring_evidence_admin_review_service.dart
  // (adminVerified, human-confirmed), and CategoryDerivedBasisResolver /
  // categoryDerived (product decision: a closed, explicit taxonomy-tag
  // allowlist, never AI, never product-name matching, never overriding
  // contradictory explicit evidence). `databaseImport` — the ONLY value
  // the pre-remediation `_basisForCategory` bug ever produced — and a
  // missing/null provenance (every snapshot written before this field
  // existed) are both deliberately excluded: both are indistinguishable
  // from legacy category-invented basis, so neither is ever trusted here.
  static const _trustedBasisProvenances = {
    'declaredLabel',
    'adminVerified',
    'categoryDerived',
  };

  bool _hasTrustedBasisProvenance(EtiketlyScoreAuditSnapshot snapshot) {
    final provenance = snapshot.resolvedInput.nutritionBasisProvenance;
    return provenance != null && _trustedBasisProvenances.contains(provenance);
  }

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
    if (!_hasTrustedBasisProvenance(current) ||
        !_hasTrustedBasisProvenance(trusted)) {
      return const PublicScoreAuditDecision(
        PublicScoreAuditStatus.basisUnverified,
      );
    }
    return PublicScoreAuditDecision(
      _structurallyCurrent(current: current, trusted: trusted)
          ? PublicScoreAuditStatus.matching
          : PublicScoreAuditStatus.stale,
    );
  }

  /// True when [current] and [trusted] are both structurally valid AND
  /// would be considered the SAME current audit — fingerprint, version
  /// tuple, and every score component agree — entirely IGNORING basis
  /// provenance trust. Never used to decide whether a score may currently
  /// DISPLAY: [evaluate] alone owns that decision, and its own
  /// basis-trust gate above is never bypassed or weakened by this method.
  /// This exists solely so a caller that needs to distinguish "this audit
  /// would be current except its basis provenance is untrusted" from
  /// "this audit genuinely isn't current, for unrelated reasons" (e.g.
  /// historical basis-revalidation candidate selection — see
  /// basis_revalidation_candidate_planner.dart) can do so without
  /// duplicating [evaluate]'s own structural comparison as a second,
  /// independently-maintained copy.
  bool wouldBeCurrentIgnoringBasisTrust({
    required EtiketlyScoreAuditSnapshot current,
    required EtiketlyScoreAuditSnapshot? trusted,
  }) {
    if (trusted == null) return false;
    if (!validator.validate(current).isValid ||
        !validator.validate(trusted).isValid) {
      return false;
    }
    return _structurallyCurrent(current: current, trusted: trusted);
  }

  bool _structurallyCurrent({
    required EtiketlyScoreAuditSnapshot current,
    required EtiketlyScoreAuditSnapshot trusted,
  }) {
    return trusted.productId == current.productId &&
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
  }

  bool _close(double left, double right) =>
      (left - right).abs() <= EtiketlyScoreAuditValidator.tolerance;
}
