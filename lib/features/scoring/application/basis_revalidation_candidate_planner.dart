import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_recovery_lifecycle_runner.dart';

/// Section J of the basis remediation pass: deterministically selects which
/// products are worth spending a network fetch on, from a completed
/// full-catalogue closure dry-run pass (see
/// tool/final_scoring_catalogue_closure.dart) — never a blind refetch of
/// the whole catalogue.
enum BasisRevalidationCandidateReason {
  /// Priority 1: the product is CURRENTLY reported as a public, current
  /// score (see [ScoringFinalState.current]), but its basis provenance is
  /// not independently trusted — see EtiketlyPublicScoreAuditGate's
  /// basisUnverified check. These are the highest-priority candidates:
  /// they are ALREADY being shown to end users on evidence that may be
  /// legacy category-invented.
  currentPublicBasisUnverified,

  /// Priority 2/3: the product is blocked, but EVERY blocker present is
  /// basis-related — nothing else stands between it and becoming
  /// score-ready. Revalidating basis alone could make this product
  /// current; anything else blocking it makes a fetch pointless until
  /// that other evidence exists too.
  otherwiseReadyExceptBasis,
}

class BasisRevalidationCandidate {
  const BasisRevalidationCandidate({
    required this.productId,
    required this.reason,
    required this.resolvedCategory,
  });

  final String productId;
  final BasisRevalidationCandidateReason reason;
  final String? resolvedCategory;
}

// The exact, closed set of blocker strings that mean "basis specifically",
// across BOTH code paths that can produce them:
//  - 'basis_unit_ambiguous' / 'basis_generic_ambiguous_exact_unit_unproven',
//    produced by legacy_scoring_evidence_recovery.dart's fresh-recovery
//    path (no existing scoring_evidence yet) — the latter is strictly more
//    specific and always accompanies the former, never appears alone.
//  - 'nutrition:unknownNutritionBasis', produced by the EXISTING-evidence
//    path (ScoringReadinessEvaluator, via ProductScoreAuditEvaluator) for
//    a product that already has scoring_evidence whose nutrition basis is
//    NutritionBasis.unknown — which, after the pre-APPLY trust
//    correction, is exactly what an untrusted-provenance basis (missing,
//    or the historical databaseImport signature) degrades to. Same
//    underlying problem — basis is not independently proven — surfaced
//    through a different blocker vocabulary depending on which path the
//    product takes; both belong in this set for the SAME reason.
const _basisOnlyBlockers = {
  'basis_unit_ambiguous',
  'basis_generic_ambiguous_exact_unit_unproven',
  'nutrition:unknownNutritionBasis',
};

// Emitted ONLY by legacy_scoring_recovery_lifecycle_runner.dart's dry-run
// `_applyExistingEvidenceProduct` path, and ONLY when
// EtiketlyPublicScoreAuditGate.wouldBeCurrentIgnoringBasisTrust confirmed
// the persisted audit's fingerprint/version/score components otherwise
// agree — i.e. this product WAS already displaying a current public score
// until the basis-safety gate started blocking it. Never emitted for a
// genuinely stale/missing audit (that case keeps the generic
// 'audit_missing_or_stale' token and is correctly excluded from this
// planner's candidate population below, matching pre-existing behavior).
const _currentPublicBasisUnverifiedBlocker = 'current_public_basis_unverified';

// Provenance values EtiketlyPublicScoreAuditGate trusts for basis — kept
// in sync with that gate's own _trustedBasisProvenances deliberately (a
// single source of truth would require exporting it publicly; duplicated
// here as a tiny, easily-audited constant rather than widening that
// gate's API surface for one internal caller). Used only by the
// defensive fallback below.
const _trustedBasisProvenances = {'declaredLabel', 'adminVerified'};

/// Pure, deterministic planner — given a completed closure dry-run's
/// results and the corresponding product rows, returns exactly the
/// candidates worth a live fetch. Never includes a product blocked by
/// unrelated genuine missing evidence (missing fibre, unresolved
/// additives, unknown classification, etc.) — proving basis for those
/// would not make them scoreable/current, so no fetch is spent on them.
List<BasisRevalidationCandidate> planBasisRevalidationCandidates({
  required List<LegacyScoringRecoveryProductResult> closureResults,
  required Map<String, Product> productsById,
}) {
  final candidates = <BasisRevalidationCandidate>[];
  for (final result in closureResults) {
    final blockers = result.blockerReasons.toSet();

    // Priority 1: the lifecycle runner has already independently confirmed
    // (via EtiketlyPublicScoreAuditGate.wouldBeCurrentIgnoringBasisTrust)
    // that this audit is otherwise current — fingerprint, version, and
    // score components all agree — and ONLY basis provenance is untrusted.
    // Checked before [ScoringFinalState] classification: a product in this
    // situation is deliberately never [ScoringFinalState.current] (the
    // gate itself still blocks display — see
    // EtiketlyPublicScoreAuditGate.evaluate — so its outcome is
    // auditRepairable/scoreableNotCurrent instead), which is exactly the
    // circular-dependency gap this blocker token exists to close.
    if (blockers.contains(_currentPublicBasisUnverifiedBlocker)) {
      candidates.add(
        BasisRevalidationCandidate(
          productId: result.productId,
          reason: BasisRevalidationCandidateReason.currentPublicBasisUnverified,
          resolvedCategory: result.resolvedCategory?.name,
        ),
      );
      continue;
    }

    final state = classifyFinalState(result);
    if (state == ScoringFinalState.current) {
      // Defensive fallback, expected to be a no-op in practice:
      // EtiketlyPublicScoreAuditGate requires trusted basis provenance on
      // BOTH sides before ANY "current" outcome (alreadyCurrent/
      // recoveredAndCurrent/auditRepairedCurrent/existingEvidenceUpgraded)
      // can ever be produced — see gate.evaluate() — so a `current`
      // result should never itself carry untrusted basis provenance; the
      // real Priority 1 signal is the blocker token handled above. Kept
      // so this planner still catches the gap if that gate invariant is
      // ever weakened without this file being updated to match.
      final product = productsById[result.productId];
      final provenance =
          product?.scoringEvidence?.nutritionBasisEvidence?.provenance.name;
      final trusted =
          provenance != null && _trustedBasisProvenances.contains(provenance);
      if (!trusted) {
        candidates.add(
          BasisRevalidationCandidate(
            productId: result.productId,
            reason: BasisRevalidationCandidateReason.currentPublicBasisUnverified,
            resolvedCategory: result.resolvedCategory?.name,
          ),
        );
      }
      continue;
    }

    final hasBasisBlocker = blockers.any(_basisOnlyBlockers.contains);
    final onlyBasisBlockers = blockers.every(_basisOnlyBlockers.contains);
    if (hasBasisBlocker && onlyBasisBlockers) {
      candidates.add(
        BasisRevalidationCandidate(
          productId: result.productId,
          reason: BasisRevalidationCandidateReason.otherwiseReadyExceptBasis,
          resolvedCategory: result.resolvedCategory?.name,
        ),
      );
    }
  }
  return candidates;
}
