import 'dart:math' as math;

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';

/// Historical-recovery boundary. Extends the ordinary current-ingestion
/// lifecycle data source with the read-only candidate scan needed to find
/// rows that still need recovery, and the staging lookup the recovery
/// service depends on. Every write still flows through the inherited
/// [ProductScoringLifecycleDataSource] members — this runner never adds a
/// parallel write path.
abstract interface class LegacyScoringRecoveryLifecycleDataSource
    implements ProductScoringLifecycleDataSource {
  /// Server-side bounded candidates: `scoring_evidence IS NULL` and
  /// `source` exactly equal to [source] (never a wildcard/prefix match —
  /// LIKE/ILIKE metacharacters in caller input must never broaden the
  /// query). Never an unbounded scan — callers must supply a positive
  /// [limit].
  Future<List<Product>> fetchRecoveryCandidates({
    required String source,
    required String? afterProductId,
    required int limit,
  });

  /// Server-side bounded, unconditional catalogue page — every product
  /// regardless of `scoring_evidence` nullness, ordered by id. Used only by
  /// the final whole-catalogue closure pass (see
  /// [LegacyScoringRecoveryLifecycleRunner.runFullCatalogueClosure]), which
  /// must cover already-evidenced products too, not only
  /// `scoring_evidence IS NULL` rows. Never an unbounded scan — callers must
  /// supply a positive [limit].
  Future<List<Product>> fetchCataloguePage({
    required String? afterProductId,
    required int limit,
  });

  Future<List<LegacyStagingScoringEvidence>> fetchStagingMatches(
    String? sourceUrl,
  );
}

/// Runner-level operational outcome for one product. This is deliberately
/// separate from [EtiketlyScoreReadinessBlocker]/[ScoringReadinessBlocker] —
/// it never re-implements or shadows the scoring readiness taxonomy, it only
/// classifies what the *recovery run* did.
enum LegacyScoringRecoveryOutcome {
  /// Dry-run only: the product has no current evidence/audit yet, and
  /// recovery would produce a final-score-ready snapshot.
  recoverable,

  /// Dry-run or apply: blocked with existing blocker reasons, zero writes.
  blocked,

  /// Dry-run or apply: the product already has non-null `scoring_evidence`
  /// AND a matching, currently-publishable audit snapshot — there is
  /// nothing to recover. In apply mode nothing was mutated; in dry-run mode
  /// nothing was ever evaluated for mutation (the recovery service is never
  /// called for a product in this state, in either mode — see
  /// [_applyExistingEvidenceProduct]).
  alreadyCurrent,

  /// Apply only: evidence and a current, publishable audit snapshot were
  /// both independently verified after [ProductScoringLifecycleService]
  /// ran.
  recoveredAndCurrent,

  /// Apply only: [ProductScoringLifecycleService.processCurrent] reported
  /// success, but the independent postcondition re-check could not confirm
  /// a current publishable snapshot. Safe to retry — never reported as a
  /// success.
  auditNotCurrentAfterApply,

  /// Dry-run or apply: the product already had non-null `scoring_evidence`
  /// before this run, that evidence is not (or is no longer) independently
  /// score-ready, AND — see [existingEvidenceUpgradable]/
  /// [existingEvidenceUpgraded] for the case where it now is — fresh
  /// recovery from current trusted source data was either skipped (the
  /// existing evidence carries admin-verification provenance, which this
  /// runner never attempts to second-guess or replace with an automated
  /// pass) or was itself still insufficient. Non-destructive in every case:
  /// existing evidence (and any admin verification provenance on it) is
  /// guaranteed untouched; no write happens for this outcome.
  existingEvidenceAuditUnavailable,

  /// Dry-run only: the product already has non-null `scoring_evidence` that
  /// IS independently score-ready, but no current, publishable audit
  /// snapshot exists for it yet (missing or stale). Apply would repair this
  /// by inserting the matching current snapshot from the unchanged existing
  /// evidence — never by recovering or rewriting evidence.
  auditRepairable,

  /// Apply only: the product already had score-ready `scoring_evidence`
  /// with no current matching audit; [ProductScoringLifecycleService.
  /// processCurrent] was invoked with an identity evidence resolver
  /// (returns the existing evidence completely unchanged) purely to insert
  /// the missing/stale current snapshot, and the postcondition re-check
  /// independently confirmed a current publishable snapshot now exists.
  /// Evidence itself was never touched.
  auditRepairedCurrent,

  /// Any mode: an unexpected failure isolated to this one product.
  unexpectedError,

  /// Dry-run or apply: the product was determined out of the scoring
  /// perimeter entirely (ScoringCategory.outOfScope, from a trusted
  /// classification fact — food supplement / infant food / medical food /
  /// sports nutrition / meal replacement). This is NOT a failure and must
  /// never be counted alongside [blocked] — a not-score-eligible product
  /// has no numeric score by design, not because evidence is missing. Zero
  /// writes in either mode.
  notScoreEligible,

  /// Dry-run only: the product already has non-null `scoring_evidence`
  /// that is NOT currently score-ready (see [existingEvidenceAuditUnavailable]),
  /// but re-running recovery from CURRENT trusted staging source data (the
  /// exact same deterministic process used for a never-recovered product)
  /// now produces a final-score-ready result — because retained source
  /// evidence can now be reconstructed more completely than it could be
  /// when this evidence was originally written (e.g. the ingredient-quality
  /// provenance/recomputation fix). Only ever considered when the existing
  /// evidence carries no admin-verification provenance — this runner never
  /// attempts to second-guess or silently replace evidence a human
  /// reviewed. Zero writes in dry-run.
  existingEvidenceUpgradable,

  /// Apply only: the upgrade predicted by [existingEvidenceUpgradable] was
  /// actually performed — [ProductScoringLifecycleService.processCurrent]
  /// was invoked with the REAL recovery resolver (not an identity
  /// resolver), producing a new, more complete evidence object and a new
  /// current audit snapshot, independently verified. The product's prior
  /// evidence and every audit snapshot ever recorded for it remain
  /// immutable history — this only ever changes what `products
  /// .scoring_evidence` currently points to (via the same
  /// optimistic-concurrency `writeScoringEvidence` write path every other
  /// evidence write in this system already uses) and inserts one new,
  /// additional audit row. Never reachable when the prior evidence carries
  /// admin-verification provenance.
  existingEvidenceUpgraded,
}

class LegacyScoringRecoveryProductResult {
  const LegacyScoringRecoveryProductResult({
    required this.productId,
    required this.productName,
    required this.dryRun,
    required this.outcome,
    required this.blockerReasons,
    this.resolvedCategory,
    this.calculatedScore,
    this.inputFingerprint,
    this.snapshotId,
    this.errorType,
  });

  final String productId;
  final String productName;
  final bool dryRun;
  final LegacyScoringRecoveryOutcome outcome;
  final List<String> blockerReasons;
  // Null only when the category genuinely could not be determined for this
  // result (e.g. the product/staging fetch itself failed, or recovery
  // blocked before any category resolution ran) — reported as "unknown" in
  // category-grouped output rather than silently dropped.
  final ScoringCategory? resolvedCategory;
  final double? calculatedScore;
  final String? inputFingerprint;
  final String? snapshotId;
  final String? errorType;

  bool get wouldApply =>
      outcome == LegacyScoringRecoveryOutcome.recoverable ||
      outcome == LegacyScoringRecoveryOutcome.auditRepairable;
}

class LegacyScoringRecoveryBatchSummary {
  LegacyScoringRecoveryBatchSummary({
    required this.dryRun,
    required this.safeResumeCursor,
  });

  final bool dryRun;
  int totalExamined = 0;
  int recoverable = 0;
  int blocked = 0;
  int alreadyCurrent = 0;
  int recoveredAndCurrent = 0;
  int auditNotCurrentAfterApply = 0;
  int existingEvidenceAuditUnavailable = 0;
  int auditRepairable = 0;
  int auditRepairedCurrent = 0;
  int unexpectedErrors = 0;
  bool completed = false;
  bool reachedLimit = false;
  bool halted = false;
  String? lastExaminedCursor;
  String? safeResumeCursor;
  int notScoreEligible = 0;
  int existingEvidenceUpgradable = 0;
  int existingEvidenceUpgraded = 0;
  final Map<String, int> blockerReasons = {};
  final List<String> failedProductIds = [];
  final List<LegacyScoringRecoveryProductResult> results = [];

  void record(LegacyScoringRecoveryProductResult result) {
    results.add(result);
    switch (result.outcome) {
      case LegacyScoringRecoveryOutcome.recoverable:
        recoverable++;
      case LegacyScoringRecoveryOutcome.blocked:
        blocked++;
      case LegacyScoringRecoveryOutcome.alreadyCurrent:
        alreadyCurrent++;
      case LegacyScoringRecoveryOutcome.recoveredAndCurrent:
        recoveredAndCurrent++;
      case LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply:
        auditNotCurrentAfterApply++;
      case LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable:
        existingEvidenceAuditUnavailable++;
      case LegacyScoringRecoveryOutcome.auditRepairable:
        auditRepairable++;
      case LegacyScoringRecoveryOutcome.auditRepairedCurrent:
        auditRepairedCurrent++;
      case LegacyScoringRecoveryOutcome.unexpectedError:
        unexpectedErrors++;
      case LegacyScoringRecoveryOutcome.notScoreEligible:
        notScoreEligible++;
      case LegacyScoringRecoveryOutcome.existingEvidenceUpgradable:
        existingEvidenceUpgradable++;
      case LegacyScoringRecoveryOutcome.existingEvidenceUpgraded:
        existingEvidenceUpgraded++;
    }
    for (final blocker in result.blockerReasons) {
      blockerReasons.update(blocker, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  List<MapEntry<String, int>> topBlockerReasons([int limit = 15]) {
    final entries = blockerReasons.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount != 0 ? byCount : left.key.compareTo(right.key);
      });
    return entries.take(limit).toList(growable: false);
  }

  /// Sum of every mutually-exclusive terminal outcome counter — every
  /// recorded result increments exactly one of these twelve counters (see
  /// the exhaustive switch in [record]), so this must always equal
  /// [totalExamined]. Used as a hard internal-accounting assertion, not a
  /// diagnostic: if this ever disagrees with [totalExamined], the report is
  /// not trustworthy regardless of what [ClosurePostcondition] says.
  int get outcomeCountsSum =>
      recoverable +
      blocked +
      alreadyCurrent +
      recoveredAndCurrent +
      auditNotCurrentAfterApply +
      existingEvidenceAuditUnavailable +
      auditRepairable +
      auditRepairedCurrent +
      unexpectedErrors +
      notScoreEligible +
      existingEvidenceUpgradable +
      existingEvidenceUpgraded;

  bool get outcomeCountsAreConsistent => outcomeCountsSum == totalExamined;
}

/// Historical-recovery runner.
///
/// Dry-run only ever calls the read-only
/// [LegacyScoringEvidenceRecoveryService.recover] evaluation — never
/// [ProductScoringLifecycleService]. It is structurally incapable of
/// writing.
///
/// Apply first re-runs the identical [LegacyScoringEvidenceRecoveryService.
/// recover] full-readiness check dry-run used (so apply can never accept a
/// product dry-run would have blocked), and only then routes through
/// [ProductScoringLifecycleService.processCurrent] with
/// [ScoreAuditTriggerSource.controlledBackfill], using [recoverEvidence] as
/// the evidence resolver purely to persist the already-proven-ready
/// snapshot. This runner never calls `writeScoringEvidence`/`insertSnapshot`
/// directly and never fabricates a `ScoringEvidenceSnapshot` itself.
///
/// If a targeted product already has non-null `scoring_evidence`, apply
/// never calls the recovery service for it and never writes — see
/// [_applyExistingEvidenceProduct].
class LegacyScoringRecoveryLifecycleRunner {
  const LegacyScoringRecoveryLifecycleRunner({
    required this.dataSource,
    this.recovery = const LegacyScoringEvidenceRecoveryService(),
    this.evaluator = const ProductScoreAuditEvaluator(),
    this.gate = const EtiketlyPublicScoreAuditGate(),
  });

  final LegacyScoringRecoveryLifecycleDataSource dataSource;
  final LegacyScoringEvidenceRecoveryService recovery;
  final ProductScoreAuditEvaluator evaluator;
  final EtiketlyPublicScoreAuditGate gate;

  /// Bounded batch by exact `source` match. [limit] must be positive —
  /// there is no unbounded mode.
  Future<LegacyScoringRecoveryBatchSummary> runForSource({
    required bool dryRun,
    required String source,
    required int limit,
    int batchSize = 50,
    String? startAfterProductId,
  }) async {
    assert(source.trim().isNotEmpty);
    assert(limit > 0);
    assert(batchSize > 0 && batchSize <= 100);

    final summary = LegacyScoringRecoveryBatchSummary(
      dryRun: dryRun,
      safeResumeCursor: startAfterProductId,
    );
    late final List<Ingredient> catalogue;
    try {
      catalogue = await dataSource.fetchIngredientCatalogue();
    } catch (_) {
      summary.unexpectedErrors++;
      summary.halted = true;
      return summary;
    }

    var cursor = startAfterProductId;
    var hasUnresolvedError = false;
    while (true) {
      final remaining = limit - summary.totalExamined;
      if (remaining <= 0) {
        summary.reachedLimit = true;
        break;
      }
      final pageLimit = math.min(batchSize, remaining);
      late final List<Product> candidates;
      try {
        candidates = await dataSource.fetchRecoveryCandidates(
          source: source,
          afterProductId: cursor,
          limit: pageLimit,
        );
      } catch (_) {
        summary.unexpectedErrors++;
        summary.halted = true;
        break;
      }
      if (candidates.isEmpty) {
        summary.completed = true;
        break;
      }

      for (final product in candidates) {
        summary.totalExamined++;
        summary.lastExaminedCursor = product.id;
        final result = await _processProduct(
          product,
          catalogue,
          dryRun: dryRun,
        );
        summary.record(result);
        if (result.outcome == LegacyScoringRecoveryOutcome.unexpectedError) {
          hasUnresolvedError = true;
          summary.failedProductIds.add(product.id);
        }
        if (!hasUnresolvedError) summary.safeResumeCursor = product.id;
        cursor = product.id;
      }
    }
    return summary;
  }

  /// Whole-catalogue final closure pass. Unlike [runForSource] and
  /// [runForProductIds], this covers EVERY product regardless of
  /// `scoring_evidence` nullness via [LegacyScoringRecoveryLifecycleDataSource
  /// .fetchCataloguePage] — closing both never-recovered products (CASE 1)
  /// and already-evidenced products whose audit may be missing/stale (CASE
  /// 2), using exactly the same per-product decision logic as the other
  /// entry points ([_dryRunProduct]/[_applyProduct]). [limit] must be
  /// positive — there is no unbounded mode.
  Future<LegacyScoringRecoveryBatchSummary> runFullCatalogueClosure({
    required bool dryRun,
    required int limit,
    int batchSize = 50,
    String? startAfterProductId,
  }) async {
    assert(limit > 0);
    assert(batchSize > 0 && batchSize <= 100);

    final summary = LegacyScoringRecoveryBatchSummary(
      dryRun: dryRun,
      safeResumeCursor: startAfterProductId,
    );
    late final List<Ingredient> catalogue;
    try {
      catalogue = await dataSource.fetchIngredientCatalogue();
    } catch (_) {
      summary.unexpectedErrors++;
      summary.halted = true;
      return summary;
    }

    var cursor = startAfterProductId;
    var hasUnresolvedError = false;
    while (true) {
      final remaining = limit - summary.totalExamined;
      if (remaining <= 0) {
        summary.reachedLimit = true;
        break;
      }
      final pageLimit = math.min(batchSize, remaining);
      late final List<Product> page;
      try {
        page = await dataSource.fetchCataloguePage(
          afterProductId: cursor,
          limit: pageLimit,
        );
      } catch (_) {
        summary.unexpectedErrors++;
        summary.halted = true;
        break;
      }
      if (page.isEmpty) {
        summary.completed = true;
        break;
      }

      for (final product in page) {
        summary.totalExamined++;
        summary.lastExaminedCursor = product.id;
        final result = await _processProduct(
          product,
          catalogue,
          dryRun: dryRun,
        );
        summary.record(result);
        if (result.outcome == LegacyScoringRecoveryOutcome.unexpectedError) {
          hasUnresolvedError = true;
          summary.failedProductIds.add(product.id);
        }
        if (!hasUnresolvedError) summary.safeResumeCursor = product.id;
        cursor = product.id;
      }
    }
    return summary;
  }

  /// Targeted recovery by explicit product ID. Never scans the catalogue.
  Future<LegacyScoringRecoveryBatchSummary> runForProductIds({
    required bool dryRun,
    required List<String> productIds,
  }) async {
    final summary = LegacyScoringRecoveryBatchSummary(
      dryRun: dryRun,
      safeResumeCursor: null,
    );
    late final List<Ingredient> catalogue;
    try {
      catalogue = await dataSource.fetchIngredientCatalogue();
    } catch (_) {
      summary.unexpectedErrors++;
      summary.halted = true;
      return summary;
    }

    for (final productId in productIds) {
      summary.totalExamined++;
      Product? product;
      try {
        product = await dataSource.fetchProduct(productId);
      } catch (_) {
        product = null;
      }
      if (product == null) {
        summary.unexpectedErrors++;
        summary.failedProductIds.add(productId);
        summary.record(
          LegacyScoringRecoveryProductResult(
            productId: productId,
            productName: '(bulunamadı)',
            dryRun: dryRun,
            outcome: LegacyScoringRecoveryOutcome.unexpectedError,
            blockerReasons: const ['product_not_found'],
          ),
        );
        continue;
      }
      final result = await _processProduct(product, catalogue, dryRun: dryRun);
      summary.record(result);
      if (result.outcome == LegacyScoringRecoveryOutcome.unexpectedError) {
        summary.failedProductIds.add(productId);
      }
    }
    return summary;
  }

  Future<LegacyScoringRecoveryProductResult> _processProduct(
    Product product,
    List<Ingredient> catalogue, {
    required bool dryRun,
  }) {
    return dryRun
        ? _dryRunProduct(product, catalogue)
        : _applyProduct(product, catalogue);
  }

  /// Read-only preview. Never touches [ProductScoringLifecycleService] and
  /// therefore can never write.
  ///
  /// A product that already has non-null `scoring_evidence` is never passed
  /// to [LegacyScoringEvidenceRecoveryService.recover] here — that check
  /// only evaluates whether *this product's own current source data* would
  /// satisfy readiness from scratch, which says nothing about whether
  /// evidence already on file is current. Without this branch, an
  /// already-fully-current product (real source data genuinely is
  /// readiness-complete, since that is exactly why it was recovered
  /// before) is misreported as `recoverable`, even though there is nothing
  /// left to recover.
  Future<LegacyScoringRecoveryProductResult> _dryRunProduct(
    Product product,
    List<Ingredient> catalogue,
  ) async {
    if (product.scoringEvidence != null) {
      try {
        return await _applyExistingEvidenceProduct(
          product,
          catalogue,
          dryRun: true,
        );
      } catch (error) {
        return LegacyScoringRecoveryProductResult(
          productId: product.id,
          productName: product.name,
          dryRun: true,
          outcome: LegacyScoringRecoveryOutcome.unexpectedError,
          blockerReasons: const [],
          resolvedCategory:
              product.scoringEvidence?.categoryEvidence.resolvedCategory,
          errorType: error.runtimeType.toString(),
        );
      }
    }
    try {
      final stagingMatches = await dataSource.fetchStagingMatches(
        product.sourceUrl,
      );
      final result = await recovery.recover(
        product: product,
        stagingMatches: stagingMatches,
        ingredientCatalogue: catalogue,
      );
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: true,
        outcome: result.notScoreEligible
            ? LegacyScoringRecoveryOutcome.notScoreEligible
            : result.finalScoreReady
            ? LegacyScoringRecoveryOutcome.recoverable
            : LegacyScoringRecoveryOutcome.blocked,
        blockerReasons: result.blockerReasons,
        resolvedCategory: result.evidence?.categoryEvidence.resolvedCategory,
      );
    } catch (error) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: true,
        outcome: LegacyScoringRecoveryOutcome.unexpectedError,
        blockerReasons: const [],
        errorType: error.runtimeType.toString(),
      );
    }
  }

  Future<LegacyScoringRecoveryProductResult> _applyProduct(
    Product product,
    List<Ingredient> catalogue,
  ) async {
    try {
      // Never call the recovery service, and never write, for a product
      // that already has trusted evidence — that evidence (and any
      // adminVerification provenance on it) must never be replaced by this
      // P0 patch. This is a purely read-only diagnostic path.
      if (product.scoringEvidence != null) {
        return await _applyExistingEvidenceProduct(
          product,
          catalogue,
          dryRun: false,
        );
      }
      return await _applyRecoverableProduct(product, catalogue);
    } catch (error) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.unexpectedError,
        blockerReasons: const [],
        resolvedCategory:
            product.scoringEvidence?.categoryEvidence.resolvedCategory,
        errorType: error.runtimeType.toString(),
      );
    }
  }

  /// Product already has non-null `scoring_evidence`. Never calls the
  /// recovery service, never calls `writeScoringEvidence` — existing
  /// evidence (and any admin verification provenance on it) is never
  /// touched, in either mode.
  ///
  /// In dry-run mode this is purely read-only: it evaluates the existing
  /// evidence exactly as the app would and reports whether a current
  /// publishable audit already exists for it.
  ///
  /// In apply mode, when the evidence is independently score-ready but no
  /// current matching audit exists yet (missing or stale), this repairs
  /// only the audit: it calls [ProductScoringLifecycleService.processCurrent]
  /// with an evidence resolver that returns the product's own existing
  /// evidence completely unchanged, so `processCurrent`'s own
  /// evidence-unchanged path (`_sameEvidence`) never issues a write to
  /// `scoring_evidence` and only inserts the missing current snapshot.
  Future<LegacyScoringRecoveryProductResult> _applyExistingEvidenceProduct(
    Product product,
    List<Ingredient> catalogue, {
    required bool dryRun,
  }) async {
    final resolvedCategory =
        product.scoringEvidence?.categoryEvidence.resolvedCategory;
    final evaluation = await evaluator.evaluate(product, catalogue);
    final current = evaluation.snapshot;
    if (current == null) {
      // Section 8 of the coverage/readiness closure pass: existing,
      // non-score-ready evidence must not be a permanent dead end when
      // fresher, more complete trusted source data is now available (e.g.
      // the ingredient-quality retained-source recomputation fix). Never
      // attempted for admin-verified evidence — this runner never
      // second-guesses or silently replaces a human review.
      if (product.scoringEvidence?.adminVerification == null) {
        final upgrade = await _attemptExistingEvidenceUpgrade(
          product,
          catalogue,
          dryRun: dryRun,
          resolvedCategory: resolvedCategory,
        );
        if (upgrade != null) return upgrade;
      }
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: dryRun,
        outcome: LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
        blockerReasons: evaluation.blockerReasons,
        resolvedCategory: resolvedCategory,
      );
    }
    final trusted = await dataSource.fetchMatchingSnapshot(current);
    final decision = trusted == null
        ? null
        : gate.evaluate(current: current, trusted: trusted);
    if (decision != null && decision.mayDisplayNumericScore) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: dryRun,
        outcome: LegacyScoringRecoveryOutcome.alreadyCurrent,
        blockerReasons: const [],
        resolvedCategory: resolvedCategory,
        calculatedScore: current.finalScore,
        inputFingerprint: current.inputFingerprint,
      );
    }

    // Evidence is score-ready (a snapshot WAS built) but no current
    // publishable audit exists — missing or stale. Dry-run can only predict
    // this; apply performs the audit-only repair.
    if (dryRun) {
      // Basis-revalidation candidate-selection circular-dependency fix:
      // distinguish "this audit would be current — fingerprint, version,
      // and every score component agree — except its basis provenance is
      // legacy/untrusted" from "this audit genuinely isn't current, for
      // unrelated reasons". Both still hit the SAME `auditRepairable`
      // outcome and the public gate's own display decision above is
      // completely unchanged either way — this only changes which
      // blocker string is reported, so
      // basis_revalidation_candidate_planner.dart can tell the two apart
      // and prioritize the first as "already public, basis needs
      // revalidating" rather than silently dropping it.
      final basisUnverifiedButOtherwiseCurrent =
          trusted != null &&
          decision?.status == PublicScoreAuditStatus.basisUnverified &&
          gate.wouldBeCurrentIgnoringBasisTrust(
            current: current,
            trusted: trusted,
          );
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: true,
        outcome: LegacyScoringRecoveryOutcome.auditRepairable,
        blockerReasons: [
          basisUnverifiedButOtherwiseCurrent
              ? 'current_public_basis_unverified'
              : 'audit_missing_or_stale',
        ],
        resolvedCategory: resolvedCategory,
        calculatedScore: current.finalScore,
        inputFingerprint: current.inputFingerprint,
      );
    }

    final existingEvidence = product.scoringEvidence!;
    final lifecycle = ProductScoringLifecycleService(
      dataSource: dataSource,
      evaluator: evaluator,
    );
    final repairResult = await lifecycle.processCurrent(
      product.id,
      triggerSource: ScoreAuditTriggerSource.controlledBackfill,
      // Identity resolver: returns the SAME evidence already on the product,
      // never recovered/fabricated/modified. processCurrent's own
      // _sameEvidence check then skips the writeScoringEvidence call
      // entirely — only insertSnapshot can run.
      evidenceResolver: (currentProduct, ingredientCatalogue) async {
        return ProductScoringEvidenceResolution(
          evidence: currentProduct.scoringEvidence ?? existingEvidence,
          blockerReasons: const [],
        );
      },
    );

    if (!repairResult.succeeded) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
        blockerReasons: const ['audit_repair_failed'],
        resolvedCategory: resolvedCategory,
        errorType: repairResult.failureType,
      );
    }
    if (repairResult.evidenceStatus == ProductScoringEvidenceStatus.updated ||
        repairResult.evidenceStatus == ProductScoringEvidenceStatus.persisted) {
      // Defensive: the identity resolver must never cause an evidence
      // write. If it somehow did (e.g. a future processCurrent change),
      // treat this as a failed repair rather than silently accept a
      // mutation to evidence this method promised never to touch.
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
        blockerReasons: const ['audit_repair_unexpectedly_wrote_evidence'],
        resolvedCategory: resolvedCategory,
      );
    }

    final verified = await _verifyCurrentPublishableSnapshot(
      product.id,
      catalogue,
    );
    if (!verified) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply,
        blockerReasons: const ['audit_not_current_after_apply'],
        resolvedCategory: resolvedCategory,
        calculatedScore: repairResult.calculatedScore,
        inputFingerprint: repairResult.inputFingerprint,
      );
    }
    return LegacyScoringRecoveryProductResult(
      productId: product.id,
      productName: product.name,
      dryRun: false,
      outcome: LegacyScoringRecoveryOutcome.auditRepairedCurrent,
      blockerReasons: const [],
      resolvedCategory: resolvedCategory,
      calculatedScore: repairResult.calculatedScore,
      inputFingerprint: repairResult.inputFingerprint,
      snapshotId: repairResult.snapshotId,
    );
  }

  /// Product has no evidence yet. Gates apply eligibility with the exact
  /// same [LegacyScoringEvidenceRecoveryService.recover] full-readiness
  /// check dry-run uses, before ever invoking
  /// [ProductScoringLifecycleService.processCurrent] — so apply can never
  /// accept a product dry-run would have reported blocked.
  Future<LegacyScoringRecoveryProductResult> _applyRecoverableProduct(
    Product product,
    List<Ingredient> catalogue,
  ) async {
    final stagingMatches = await dataSource.fetchStagingMatches(
      product.sourceUrl,
    );
    final readiness = await recovery.recover(
      product: product,
      stagingMatches: stagingMatches,
      ingredientCatalogue: catalogue,
    );
    final resolvedCategory =
        readiness.evidence?.categoryEvidence.resolvedCategory;
    if (readiness.notScoreEligible) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.notScoreEligible,
        blockerReasons: readiness.blockerReasons,
        resolvedCategory: resolvedCategory,
      );
    }
    if (!readiness.finalScoreReady) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.blocked,
        blockerReasons: readiness.blockerReasons,
        resolvedCategory: resolvedCategory,
      );
    }

    // Full readiness already proven above. This call routes through the
    // trusted lifecycle purely to persist that already-proven-ready
    // evidence (via recoverEvidence, reusing the identical wiring
    // production ingestion uses) and produce the audit snapshot.
    final lifecycle = ProductScoringLifecycleService(
      dataSource: dataSource,
      evaluator: evaluator,
    );
    final result = await lifecycle.processCurrent(
      product.id,
      triggerSource: ScoreAuditTriggerSource.controlledBackfill,
      evidenceResolver: (currentProduct, ingredientCatalogue) async {
        final resolverStagingMatches = await dataSource.fetchStagingMatches(
          currentProduct.sourceUrl,
        );
        final recovered = await recovery.recoverEvidence(
          product: currentProduct,
          stagingMatches: resolverStagingMatches,
          ingredientCatalogue: ingredientCatalogue,
        );
        return ProductScoringEvidenceResolution(
          evidence: recovered.evidence,
          blockerReasons: recovered.blockerReasons,
        );
      },
    );

    if (!result.succeeded) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.unexpectedError,
        blockerReasons: result.blockerReasons,
        resolvedCategory: resolvedCategory,
        errorType: result.failureType,
      );
    }
    if (!result.finalScoreReady) {
      // Defensive only: the pre-check above already proved readiness, so
      // this should not normally trigger (e.g. a concurrent evidence
      // change between the pre-check and processCurrent's own read).
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.blocked,
        blockerReasons: result.blockerReasons,
        resolvedCategory: resolvedCategory,
      );
    }
    if (result.auditStatus == ProductScoringAuditStatus.current) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.alreadyCurrent,
        blockerReasons: const [],
        resolvedCategory: resolvedCategory,
        calculatedScore: result.calculatedScore,
        inputFingerprint: result.inputFingerprint,
      );
    }

    // processCurrent reported inserted/duplicate. Do not treat that as
    // proof of success: independently rebuild "current" from a fresh
    // product fetch (the re-read, persisted representation) and re-check
    // it against the same trusted-snapshot lookup the app uses to decide
    // whether to publish a score.
    final verified = await _verifyCurrentPublishableSnapshot(
      product.id,
      catalogue,
    );
    if (!verified) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply,
        blockerReasons: const ['audit_not_current_after_apply'],
        resolvedCategory: resolvedCategory,
        calculatedScore: result.calculatedScore,
        inputFingerprint: result.inputFingerprint,
      );
    }
    return LegacyScoringRecoveryProductResult(
      productId: product.id,
      productName: product.name,
      dryRun: false,
      outcome: LegacyScoringRecoveryOutcome.recoveredAndCurrent,
      blockerReasons: const [],
      resolvedCategory: resolvedCategory,
      calculatedScore: result.calculatedScore,
      inputFingerprint: result.inputFingerprint,
      snapshotId: result.snapshotId,
    );
  }

  /// Section 8: attempts to upgrade a product whose EXISTING evidence is
  /// not currently score-ready, by re-running the identical deterministic
  /// recovery process used for a never-recovered product against CURRENT
  /// trusted staging source data. Returns null (never a result) when the
  /// upgrade cannot proceed — the caller falls back to
  /// [LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable]
  /// unchanged in that case. Never called for admin-verified evidence (see
  /// the caller) and never itself checks that — this method assumes the
  /// caller has already excluded that case.
  ///
  /// Mirrors [_applyRecoverableProduct]'s apply-time structure exactly
  /// (same pre-check-then-processCurrent-then-independently-verify shape),
  /// differing only in which outcome values it reports, so the two paths
  /// stay trivially easy to compare for behavioral parity.
  Future<LegacyScoringRecoveryProductResult?> _attemptExistingEvidenceUpgrade(
    Product product,
    List<Ingredient> catalogue, {
    required bool dryRun,
    required ScoringCategory? resolvedCategory,
  }) async {
    final stagingMatches = await dataSource.fetchStagingMatches(
      product.sourceUrl,
    );
    final readiness = await recovery.recover(
      product: product,
      stagingMatches: stagingMatches,
      ingredientCatalogue: catalogue,
    );
    if (readiness.notScoreEligible || !readiness.finalScoreReady) {
      return null;
    }
    final freshCategory =
        readiness.evidence?.categoryEvidence.resolvedCategory ??
        resolvedCategory;

    if (dryRun) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: true,
        outcome: LegacyScoringRecoveryOutcome.existingEvidenceUpgradable,
        blockerReasons: const [],
        resolvedCategory: freshCategory,
      );
    }

    final lifecycle = ProductScoringLifecycleService(
      dataSource: dataSource,
      evaluator: evaluator,
    );
    final result = await lifecycle.processCurrent(
      product.id,
      triggerSource: ScoreAuditTriggerSource.controlledBackfill,
      evidenceResolver: (currentProduct, ingredientCatalogue) async {
        final resolverStagingMatches = await dataSource.fetchStagingMatches(
          currentProduct.sourceUrl,
        );
        final recovered = await recovery.recoverEvidence(
          product: currentProduct,
          stagingMatches: resolverStagingMatches,
          ingredientCatalogue: ingredientCatalogue,
        );
        return ProductScoringEvidenceResolution(
          evidence: recovered.evidence,
          blockerReasons: recovered.blockerReasons,
        );
      },
    );

    if (!result.succeeded || !result.finalScoreReady) {
      // The pre-check above already proved readiness from the same source
      // data processCurrent itself re-reads, so this should not normally
      // trigger (e.g. a concurrent change between the pre-check and
      // processCurrent's own read). Fall back to the caller's
      // existingEvidenceAuditUnavailable rather than report a false
      // upgrade — never an unexpectedError for a condition this method can
      // legitimately hit without anything actually being broken.
      return null;
    }
    if (result.auditStatus == ProductScoringAuditStatus.current) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.existingEvidenceUpgraded,
        blockerReasons: const [],
        resolvedCategory: freshCategory,
        calculatedScore: result.calculatedScore,
        inputFingerprint: result.inputFingerprint,
      );
    }

    final verified = await _verifyCurrentPublishableSnapshot(
      product.id,
      catalogue,
    );
    if (!verified) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply,
        blockerReasons: const ['audit_not_current_after_apply'],
        resolvedCategory: freshCategory,
        calculatedScore: result.calculatedScore,
        inputFingerprint: result.inputFingerprint,
      );
    }
    return LegacyScoringRecoveryProductResult(
      productId: product.id,
      productName: product.name,
      dryRun: false,
      outcome: LegacyScoringRecoveryOutcome.existingEvidenceUpgraded,
      blockerReasons: const [],
      resolvedCategory: freshCategory,
      calculatedScore: result.calculatedScore,
      inputFingerprint: result.inputFingerprint,
      snapshotId: result.snapshotId,
    );
  }

  /// Re-fetches the product fresh (the persisted, re-read representation —
  /// never the in-memory value from before the write) and independently
  /// re-evaluates it, rather than trusting [ProductScoringLifecycleService]
  /// processCurrent's own return value.
  ///
  /// KNOWN PERFORMANCE NOTE: this still triggers one additional full
  /// ingredient-catalogue fetch inside processCurrent itself (that fetch is
  /// internal to the frozen ProductScoringLifecycleService and is out of
  /// scope to change here). This method reuses the caller's already-fetched
  /// [catalogue] rather than fetching a second time, so the only remaining
  /// redundancy is that one unavoidable internal fetch. Left as an accepted
  /// MEDIUM issue rather than caching across calls, which could let scoring
  /// use stale catalogue data.
  Future<bool> _verifyCurrentPublishableSnapshot(
    String productId,
    List<Ingredient> catalogue,
  ) async {
    final freshProduct = await dataSource.fetchProduct(productId);
    if (freshProduct == null) return false;
    final evaluation = await evaluator.evaluate(freshProduct, catalogue);
    final current = evaluation.snapshot;
    if (current == null) return false;
    final trusted = await dataSource.fetchMatchingSnapshot(current);
    if (trusted == null) return false;
    return gate
        .evaluate(current: current, trusted: trusted)
        .mayDisplayNumericScore;
  }
}

class LegacyScoringRecoveryReportFormatter {
  const LegacyScoringRecoveryReportFormatter();

  String formatProduct(LegacyScoringRecoveryProductResult result) {
    return [
      'product_id=${result.productId}',
      'product_name=${_safe(result.productName)}',
      'mode=${result.dryRun ? 'dry_run' : 'apply'}',
      'outcome=${result.outcome.name}',
      if (result.dryRun) 'would_apply=${result.wouldApply}',
      'blockers=${result.blockerReasons.isEmpty ? '-' : result.blockerReasons.join(',')}',
      'calculated_score=${result.calculatedScore ?? '-'}',
      'input_fingerprint=${result.inputFingerprint ?? '-'}',
      'snapshot_id=${result.snapshotId ?? '-'}',
      if (result.errorType != null) 'error_type=${result.errorType}',
    ].join(' ');
  }

  /// Every one of the ten mutually-exclusive terminal outcome counters is
  /// always printed, in both modes. Earlier revisions gated most of them
  /// behind `if (!summary.dryRun)`/`if (summary.dryRun)`, on the assumption
  /// that only apply-relevant counters mattered per mode — but
  /// `alreadyCurrent` and `existingEvidenceAuditUnavailable` are genuinely
  /// populated in dry-run too (a product can already be current, or already
  /// have evidence that is simply not score-ready, without ever calling
  /// [ProductScoringLifecycleService]). Hiding them from the dry-run
  /// `[summary]` silently dropped real counts from the report — the exact
  /// production discrepancy this fixes (`catalogue_total - already_current -
  /// audit_repairable - blocked` did not equal zero because
  /// `existing_evidence_audit_unavailable` was never printed to explain the
  /// remainder). Printing all nine, always, makes
  /// `sum(all nine) == total_examined` directly checkable from the report
  /// text itself, in either mode.
  String formatSummary(LegacyScoringRecoveryBatchSummary summary) {
    final lines = <String>[
      '[summary]',
      'mode=${summary.dryRun ? 'dry_run' : 'apply'}',
      'total_examined=${summary.totalExamined}',
      'recoverable=${summary.recoverable}',
      'audit_repairable=${summary.auditRepairable}',
      'already_current=${summary.alreadyCurrent}',
      'recovered_and_current=${summary.recoveredAndCurrent}',
      'audit_repaired_current=${summary.auditRepairedCurrent}',
      'audit_not_current_after_apply=${summary.auditNotCurrentAfterApply}',
      'existing_evidence_audit_unavailable='
          '${summary.existingEvidenceAuditUnavailable}',
      'existing_evidence_upgradable=${summary.existingEvidenceUpgradable}',
      'existing_evidence_upgraded=${summary.existingEvidenceUpgraded}',
      'blocked=${summary.blocked}',
      'unexpected_errors=${summary.unexpectedErrors}',
      'not_score_eligible=${summary.notScoreEligible}',
      'outcome_counts_sum=${summary.outcomeCountsSum}',
      'outcome_counts_consistent=${summary.outcomeCountsAreConsistent}',
      'completed=${summary.completed}',
      'reached_limit=${summary.reachedLimit}',
      'halted=${summary.halted}',
      'last_examined_cursor=${summary.lastExaminedCursor ?? '-'}',
      'safe_resume_cursor=${summary.safeResumeCursor ?? '-'}',
      '[top_blocker_reasons]',
      ...summary.topBlockerReasons().map(
        (entry) => '${entry.key}=${entry.value}',
      ),
    ];
    if (summary.failedProductIds.isNotEmpty) {
      lines.add('[failed_product_ids]');
      lines.addAll(summary.failedProductIds);
    }
    return lines.join('\n');
  }

  /// Groups a completed run's results by resolved scoring category — a
  /// single catalogue-wide blocker count can hide a broken category
  /// resolver (e.g. nearly every product in one category blocked), so this
  /// must be visible per category, not only in aggregate.
  ///
  /// Prints the exact same ten mutually-exclusive outcome fields as
  /// [formatSummary], in the same order — per-category `blocked` here means
  /// only [LegacyScoringRecoveryOutcome.blocked], never a bucket that also
  /// silently absorbs `audit_repairable`/`existing_evidence_audit_unavailable`,
  /// so summing any field across categories always reproduces the matching
  /// global `[summary]` count.
  String formatCategoryBreakdown(Map<String, CategoryClosureStats> byCategory) {
    final lines = <String>['[category_breakdown]'];
    final categories = byCategory.keys.toList()..sort();
    for (final category in categories) {
      final stats = byCategory[category]!;
      lines.add(
        [
          'category=$category',
          'total=${stats.totalProducts}',
          'recoverable=${stats.recoverable}',
          'audit_repairable=${stats.auditRepairable}',
          'already_current=${stats.alreadyCurrent}',
          'recovered_and_current=${stats.recoveredAndCurrent}',
          'audit_repaired_current=${stats.auditRepairedCurrent}',
          'audit_not_current_after_apply=${stats.auditNotCurrentAfterApply}',
          'existing_evidence_audit_unavailable='
              '${stats.existingEvidenceAuditUnavailable}',
          'existing_evidence_upgradable=${stats.existingEvidenceUpgradable}',
          'existing_evidence_upgraded=${stats.existingEvidenceUpgraded}',
          'blocked=${stats.blocked}',
          'unexpected_errors=${stats.unexpectedErrors}',
          'not_score_eligible=${stats.notScoreEligible}',
          'outcome_counts_consistent=${stats.outcomeCountsAreConsistent}',
        ].join(' '),
      );
      for (final entry in stats.topBlockerReasons(5)) {
        lines.add('  top_blocker: ${entry.key}=${entry.value}');
      }
    }
    return lines.join('\n');
  }

  /// The mandatory closure postcondition. Never omit this from a closure
  /// report — a clean-looking summary can still hide a nonzero
  /// scoreable_but_not_current or unexpected_errors count.
  String formatPostcondition(ClosurePostcondition postcondition) {
    final lines = <String>[
      '[postcondition]',
      'catalogue_total=${postcondition.catalogueTotal}',
      'current_public_scores=${postcondition.currentPublicScores}',
      'scoreable_but_not_current=${postcondition.scoreableButNotCurrent}',
      'unexpected_errors=${postcondition.unexpectedErrors}',
      'not_score_eligible=${postcondition.notScoreEligible}',
      'eligible_total=${postcondition.eligibleTotal}',
      'eligible_current=${postcondition.eligibleCurrent}',
      'eligible_recoverable=${postcondition.eligibleRecoverable}',
      'eligible_blocked=${postcondition.eligibleBlocked}',
      'closure_clean=${postcondition.isClean}',
    ];
    if (postcondition.scoreableButNotCurrentProductIds.isNotEmpty) {
      lines.add('[scoreable_but_not_current_product_ids]');
      lines.addAll(postcondition.scoreableButNotCurrentProductIds);
    }
    if (postcondition.unexpectedErrorProductIds.isNotEmpty) {
      lines.add('[unexpected_error_product_ids]');
      lines.addAll(postcondition.unexpectedErrorProductIds);
    }
    return lines.join('\n');
  }

  /// Section K: the six-state final model, computed once directly from
  /// [LegacyScoringRecoveryBatchSummary.results] — always sums to
  /// `total_examined` by construction (see [summarizeFinalStates]).
  String formatFinalStateSummary(List<LegacyScoringRecoveryProductResult> results) {
    final counts = summarizeFinalStates(results);
    final sum = counts.values.fold(0, (a, b) => a + b);
    final lines = <String>[
      '[final_state_model]',
      for (final state in ScoringFinalState.values)
        '${state.name}=${counts[state]}',
      'final_state_counts_sum=$sum',
      'final_state_counts_consistent=${sum == results.length}',
    ];
    return lines.join('\n');
  }

  String _safe(String value) =>
      value.trim().replaceAll(RegExp(r'[\r\n\t]+'), ' ');
}

/// Per-category rollup of a completed run's results. Built purely from
/// [LegacyScoringRecoveryBatchSummary.results] after the run — no
/// additional service calls, no re-evaluation.
///
/// Carries the exact same ten mutually-exclusive outcome counters as
/// [LegacyScoringRecoveryBatchSummary] — a category-level bucket that
/// lumps several distinct outcomes together (e.g. a generic "blocked" that
/// silently also counted `auditRepairable`/`existingEvidenceAuditUnavailable`)
/// makes the category breakdown disagree with the global summary's own
/// `blocked` count, which is exactly the accounting gap this fixes.
class CategoryClosureStats {
  int totalProducts = 0;
  int recoverable = 0;
  int blocked = 0;
  int alreadyCurrent = 0;
  int recoveredAndCurrent = 0;
  int auditNotCurrentAfterApply = 0;
  int existingEvidenceAuditUnavailable = 0;
  int auditRepairable = 0;
  int auditRepairedCurrent = 0;
  int unexpectedErrors = 0;
  int notScoreEligible = 0;
  int existingEvidenceUpgradable = 0;
  int existingEvidenceUpgraded = 0;
  final Map<String, int> blockerReasons = {};

  void record(LegacyScoringRecoveryProductResult result) {
    totalProducts++;
    switch (result.outcome) {
      case LegacyScoringRecoveryOutcome.recoverable:
        recoverable++;
      case LegacyScoringRecoveryOutcome.blocked:
        blocked++;
      case LegacyScoringRecoveryOutcome.alreadyCurrent:
        alreadyCurrent++;
      case LegacyScoringRecoveryOutcome.recoveredAndCurrent:
        recoveredAndCurrent++;
      case LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply:
        auditNotCurrentAfterApply++;
      case LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable:
        existingEvidenceAuditUnavailable++;
      case LegacyScoringRecoveryOutcome.auditRepairable:
        auditRepairable++;
      case LegacyScoringRecoveryOutcome.auditRepairedCurrent:
        auditRepairedCurrent++;
      case LegacyScoringRecoveryOutcome.unexpectedError:
        unexpectedErrors++;
      case LegacyScoringRecoveryOutcome.notScoreEligible:
        notScoreEligible++;
      case LegacyScoringRecoveryOutcome.existingEvidenceUpgradable:
        existingEvidenceUpgradable++;
      case LegacyScoringRecoveryOutcome.existingEvidenceUpgraded:
        existingEvidenceUpgraded++;
    }
    for (final blocker in result.blockerReasons) {
      blockerReasons.update(blocker, (count) => count + 1, ifAbsent: () => 1);
    }
  }

  List<MapEntry<String, int>> topBlockerReasons([int limit = 10]) {
    final entries = blockerReasons.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount != 0 ? byCount : left.key.compareTo(right.key);
      });
    return entries.take(limit).toList(growable: false);
  }

  /// Mirrors [LegacyScoringRecoveryBatchSummary.outcomeCountsSum] at the
  /// category level — must always equal [totalProducts].
  int get outcomeCountsSum =>
      recoverable +
      blocked +
      alreadyCurrent +
      recoveredAndCurrent +
      auditNotCurrentAfterApply +
      existingEvidenceAuditUnavailable +
      auditRepairable +
      auditRepairedCurrent +
      unexpectedErrors +
      notScoreEligible +
      existingEvidenceUpgradable +
      existingEvidenceUpgraded;

  bool get outcomeCountsAreConsistent => outcomeCountsSum == totalProducts;
}

/// Groups completed results by resolved scoring category name (or
/// `"unknown"` when a result genuinely has none — never silently dropped).
Map<String, CategoryClosureStats> groupResultsByCategory(
  List<LegacyScoringRecoveryProductResult> results,
) {
  final grouped = <String, CategoryClosureStats>{};
  for (final result in results) {
    final key = result.resolvedCategory?.name ?? 'unknown';
    grouped.putIfAbsent(key, () => CategoryClosureStats()).record(result);
  }
  return grouped;
}

/// The final catalogue closure invariant.
///
/// [scoreableButNotCurrent] counts two outcomes, mode-exclusive with each
/// other so only one is ever nonzero on a given run:
///   - [LegacyScoringRecoveryOutcome.auditRepairable] (dry-run only): by
///     definition the product already has score-ready existing evidence —
///     [ProductScoreAuditEvaluator] independently built a snapshot from
///     it — but no current, publishable audit exists for it yet. That
///     evidence genuinely IS scoreable; it is simply not current. Treating
///     this as anything other than "scoreable but not current" is the
///     exact accounting bug this fixes.
///   - [LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply] (apply
///     only): the apply-time equivalent — readiness/repair was proven,
///     `processCurrent` ran, but independent postcondition verification
///     could not confirm a current publishable snapshot afterwards.
///
/// [LegacyScoringRecoveryOutcome.recoverable] is deliberately NOT included:
/// that outcome means no evidence exists yet at all (CASE 1) — the
/// underlying source data would *allow* evidence to be built, but nothing
/// is scoreable yet, so it is a backlog count, not a "scoreable but stuck"
/// defect. `blocked` and `existingEvidenceAuditUnavailable` are also
/// excluded — both mean the evidence itself is not (or is no longer)
/// score-ready, a genuine data blocker rather than an audit-only gap.
class ClosurePostcondition {
  const ClosurePostcondition({
    required this.catalogueTotal,
    required this.currentPublicScores,
    required this.scoreableButNotCurrent,
    required this.unexpectedErrors,
    required this.scoreableButNotCurrentProductIds,
    required this.unexpectedErrorProductIds,
    required this.notScoreEligible,
    required this.eligibleTotal,
    required this.eligibleCurrent,
    required this.eligibleRecoverable,
    required this.eligibleBlocked,
  });

  final int catalogueTotal;
  final int currentPublicScores;
  final int scoreableButNotCurrent;
  final int unexpectedErrors;
  final List<String> scoreableButNotCurrentProductIds;
  final List<String> unexpectedErrorProductIds;

  // Section A eligibility model: notScoreEligible products are excluded
  // from catalogueTotal to form eligibleTotal, which then partitions
  // cleanly into exactly three buckets — current (already publishable),
  // recoverable (on a path to becoming current: recoverable + the
  // scoreable-but-not-current outcomes), and blocked (the remainder —
  // genuine evidence blockers). eligibleBlocked is deliberately computed as
  // a remainder so eligibleTotal == eligibleCurrent + eligibleRecoverable +
  // eligibleBlocked always holds by construction, mirroring the same
  // closed-accounting discipline as outcomeCountsSum.
  final int notScoreEligible;
  final int eligibleTotal;
  final int eligibleCurrent;
  final int eligibleRecoverable;
  final int eligibleBlocked;

  bool get isClean => scoreableButNotCurrent == 0 && unexpectedErrors == 0;
}

ClosurePostcondition computeClosurePostcondition(
  List<LegacyScoringRecoveryProductResult> results,
) {
  final scoreableButNotCurrentIds = <String>[];
  final unexpectedErrorIds = <String>[];
  var currentPublicScores = 0;
  var recoverableCount = 0;
  var notScoreEligibleCount = 0;
  for (final result in results) {
    switch (result.outcome) {
      case LegacyScoringRecoveryOutcome.alreadyCurrent:
      case LegacyScoringRecoveryOutcome.recoveredAndCurrent:
      case LegacyScoringRecoveryOutcome.auditRepairedCurrent:
      case LegacyScoringRecoveryOutcome.existingEvidenceUpgraded:
        currentPublicScores++;
      case LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply:
      case LegacyScoringRecoveryOutcome.auditRepairable:
      case LegacyScoringRecoveryOutcome.existingEvidenceUpgradable:
        scoreableButNotCurrentIds.add(result.productId);
      case LegacyScoringRecoveryOutcome.recoverable:
        recoverableCount++;
      case LegacyScoringRecoveryOutcome.unexpectedError:
        unexpectedErrorIds.add(result.productId);
      case LegacyScoringRecoveryOutcome.notScoreEligible:
        notScoreEligibleCount++;
      case LegacyScoringRecoveryOutcome.blocked:
      case LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable:
        break;
    }
  }
  final catalogueTotal = results.length;
  final eligibleTotal = catalogueTotal - notScoreEligibleCount;
  final eligibleRecoverable = scoreableButNotCurrentIds.length + recoverableCount;
  final eligibleBlocked =
      eligibleTotal - currentPublicScores - eligibleRecoverable;
  return ClosurePostcondition(
    catalogueTotal: catalogueTotal,
    currentPublicScores: currentPublicScores,
    scoreableButNotCurrent: scoreableButNotCurrentIds.length,
    unexpectedErrors: unexpectedErrorIds.length,
    scoreableButNotCurrentProductIds: scoreableButNotCurrentIds,
    unexpectedErrorProductIds: unexpectedErrorIds,
    notScoreEligible: notScoreEligibleCount,
    eligibleTotal: eligibleTotal,
    eligibleCurrent: currentPublicScores,
    eligibleRecoverable: eligibleRecoverable,
    eligibleBlocked: eligibleBlocked,
  );
}

/// Section K final state model: every product occupies exactly one of six
/// mutually-exclusive states. No catch-all — [classifyFinalState] is total
/// over [LegacyScoringRecoveryOutcome] and, for the two outcomes that can
/// still mean either "we don't have the evidence yet" or "the evidence we
/// have is contradictory", it inspects [LegacyScoringRecoveryProductResult
/// .blockerReasons] against a closed, principled classification of every
/// blocker string this codebase actually produces (see
/// [_invalidSourceDataBlockerTokens] — derived directly from the exhaustive,
/// compiler-checked switches over the frozen [ScoringReadinessBlocker] and
/// [EtiketlyScoreReadinessBlocker] enums, never guessed ad hoc).
enum ScoringFinalState {
  /// Outside the scoring perimeter entirely (ScoringCategory.outOfScope) —
  /// never a failure.
  notScoreEligible,

  /// Has a current, publishable score right now.
  current,

  /// Scoreable (evidence exists or would exist) but not yet current.
  scoreableNotCurrent,

  /// Evidence is genuinely absent/unknown — nothing contradictory, simply
  /// not yet proven.
  blockedInsufficientEvidence,

  /// Evidence is present but contradictory, out-of-range, conflicting, or
  /// in an unsupported/mismatched form.
  blockedInvalidSourceData,

  /// An unexpected failure isolated to one product. Always zero in a clean
  /// closure run.
  unexpectedError,
}

/// Every [ScoringReadinessBlocker] this codebase can raise (aside from
/// [ScoringReadinessBlocker.outOfScopeProduct], handled upstream as
/// [ScoringFinalState.notScoreEligible] before this classification ever
/// runs), expressed as every string form it can appear in inside
/// [LegacyScoringRecoveryProductResult.blockerReasons]:
///   - the snake_case ad-hoc token legacy_scoring_evidence_recovery.dart's
///     own `_recover()`/`_addCrossFieldNutritionBlockers` emit for it, and
///   - the `nutrition:${blocker.name}` form product_score_audit_evaluator
///     .dart emits for the existing-evidence re-audit path.
/// Classified INVALID_SOURCE_DATA only when the underlying signal is a
/// genuine contradiction, out-of-range value, conflict, or unsupported
/// declared form — never merely "not yet known". Everything else (the
/// remaining ScoringReadinessBlocker values, plus every
/// EtiketlyScoreReadinessBlocker value except additiveRiskConflict) is
/// INSUFFICIENT_EVIDENCE by omission from this set.
const _invalidSourceDataBlockerTokens = {
  // ScoringReadinessBlocker.nutritionBasisDoesNotMatchCategory
  'nutrition:nutritionBasisDoesNotMatchCategory',
  // ScoringReadinessBlocker.unsupportedPerServingOnly — a basis IS
  // declared, just in a form this methodology cannot use.
  'nutrition:unsupportedPerServingOnly',
  'basis_per_serving',
  // ScoringReadinessBlocker.conflictingCategoryEvidence
  'nutrition:conflictingCategoryEvidence',
  // ScoringReadinessBlocker.invalidEvidenceValue
  'nutrition:invalidEvidenceValue',
  // ScoringReadinessBlocker.rejectedEvidence
  'nutrition:rejectedEvidence',
  // ScoringReadinessBlocker.saturatedFatExceedsTotalFat
  'nutrition:saturatedFatExceedsTotalFat',
  'saturated_fat_exceeds_total_fat',
  // ScoringReadinessBlocker.nonPositiveTotalFatForFatCategory
  'nutrition:nonPositiveTotalFatForFatCategory',
  'non_positive_total_fat_for_fat_category',
  // ScoringReadinessBlocker.plainWaterCategoryMismatch
  'nutrition:plainWaterCategoryMismatch',
  'plain_water_category_mismatch',
  // Ad-hoc recovery-path tokens with no direct ScoringReadinessBlocker
  // counterpart, but the same "signal present and contradictory" shape:
  // multiple staging rows disagree, or a basis was declared but flagged
  // unreliable/unrecognized.
  'ambiguous_staging_match',
  'basis_unknown_assumed_per100',
  'basis_unsupported',
  // EtiketlyScoreReadinessBlocker.additiveRiskConflict — conflicting risk
  // assessments for the same canonical additive, a genuine conflict, not
  // an absence.
  'additive:additiveRiskConflict',
};

/// Total classifier — see [ScoringFinalState].
ScoringFinalState classifyFinalState(LegacyScoringRecoveryProductResult result) {
  switch (result.outcome) {
    case LegacyScoringRecoveryOutcome.notScoreEligible:
      return ScoringFinalState.notScoreEligible;
    case LegacyScoringRecoveryOutcome.alreadyCurrent:
    case LegacyScoringRecoveryOutcome.recoveredAndCurrent:
    case LegacyScoringRecoveryOutcome.auditRepairedCurrent:
    case LegacyScoringRecoveryOutcome.existingEvidenceUpgraded:
      return ScoringFinalState.current;
    case LegacyScoringRecoveryOutcome.recoverable:
    case LegacyScoringRecoveryOutcome.auditRepairable:
    case LegacyScoringRecoveryOutcome.auditNotCurrentAfterApply:
    case LegacyScoringRecoveryOutcome.existingEvidenceUpgradable:
      return ScoringFinalState.scoreableNotCurrent;
    case LegacyScoringRecoveryOutcome.unexpectedError:
      return ScoringFinalState.unexpectedError;
    case LegacyScoringRecoveryOutcome.blocked:
    case LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable:
      final hasInvalidSourceSignal = result.blockerReasons.any(
        _invalidSourceDataBlockerTokens.contains,
      );
      return hasInvalidSourceSignal
          ? ScoringFinalState.blockedInvalidSourceData
          : ScoringFinalState.blockedInsufficientEvidence;
  }
}

/// Tallies every result into exactly one [ScoringFinalState] bucket. The sum
/// of every value always equals `results.length` by construction —
/// [classifyFinalState] is total and each result contributes to exactly one
/// bucket, so there is no separate "consistency" check to run here (unlike
/// [LegacyScoringRecoveryBatchSummary.outcomeCountsAreConsistent], which
/// exists only because that count is accumulated incrementally during a
/// long-running scan rather than derived in one pass at the end).
Map<ScoringFinalState, int> summarizeFinalStates(
  List<LegacyScoringRecoveryProductResult> results,
) {
  final counts = {for (final state in ScoringFinalState.values) state: 0};
  for (final result in results) {
    final state = classifyFinalState(result);
    counts[state] = counts[state]! + 1;
  }
  return counts;
}
