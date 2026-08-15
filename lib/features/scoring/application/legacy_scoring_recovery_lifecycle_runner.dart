import 'dart:math' as math;

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
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

  Future<List<LegacyStagingScoringEvidence>> fetchStagingMatches(
    String? sourceUrl,
  );
}

/// Runner-level operational outcome for one product. This is deliberately
/// separate from [EtiketlyScoreReadinessBlocker]/[ScoringReadinessBlocker] —
/// it never re-implements or shadows the scoring readiness taxonomy, it only
/// classifies what the *recovery run* did.
enum LegacyScoringRecoveryOutcome {
  /// Dry-run only: recovery would produce a final-score-ready snapshot.
  recoverable,

  /// Dry-run or apply: blocked with existing blocker reasons, zero writes.
  blocked,

  /// Apply only: a current, publishable audit snapshot already existed;
  /// nothing was mutated.
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

  /// Apply only, targeted (`--product-id`) mode: the product already had
  /// non-null `scoring_evidence` before this run, so this run never called
  /// the recovery service and never wrote evidence — it is a purely
  /// read-only diagnostic report that no current publishable audit was
  /// found for the pre-existing evidence. Non-destructive: existing
  /// evidence (and any admin verification provenance on it) is guaranteed
  /// untouched.
  existingEvidenceAuditUnavailable,

  /// Any mode: an unexpected failure isolated to this one product.
  unexpectedError,
}

class LegacyScoringRecoveryProductResult {
  const LegacyScoringRecoveryProductResult({
    required this.productId,
    required this.productName,
    required this.dryRun,
    required this.outcome,
    required this.blockerReasons,
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
  final double? calculatedScore;
  final String? inputFingerprint;
  final String? snapshotId;
  final String? errorType;

  bool get wouldApply => outcome == LegacyScoringRecoveryOutcome.recoverable;
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
  int unexpectedErrors = 0;
  bool completed = false;
  bool reachedLimit = false;
  bool halted = false;
  String? lastExaminedCursor;
  String? safeResumeCursor;
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
      case LegacyScoringRecoveryOutcome.unexpectedError:
        unexpectedErrors++;
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
  Future<LegacyScoringRecoveryProductResult> _dryRunProduct(
    Product product,
    List<Ingredient> catalogue,
  ) async {
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
        outcome: result.finalScoreReady
            ? LegacyScoringRecoveryOutcome.recoverable
            : LegacyScoringRecoveryOutcome.blocked,
        blockerReasons: result.blockerReasons,
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
        return await _applyExistingEvidenceProduct(product, catalogue);
      }
      return await _applyRecoverableProduct(product, catalogue);
    } catch (error) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.unexpectedError,
        blockerReasons: const [],
        errorType: error.runtimeType.toString(),
      );
    }
  }

  /// Product already has non-null `scoring_evidence`. Read-only: evaluates
  /// the existing evidence exactly as the app would and reports whether a
  /// current publishable audit already exists for it, without ever calling
  /// the recovery service, `writeScoringEvidence`, or `insertSnapshot`.
  Future<LegacyScoringRecoveryProductResult> _applyExistingEvidenceProduct(
    Product product,
    List<Ingredient> catalogue,
  ) async {
    final evaluation = await evaluator.evaluate(product, catalogue);
    final current = evaluation.snapshot;
    if (current == null) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
        blockerReasons: evaluation.blockerReasons,
      );
    }
    final trusted = await dataSource.fetchMatchingSnapshot(current);
    final matches =
        trusted != null &&
        gate.evaluate(current: current, trusted: trusted).mayDisplayNumericScore;
    if (matches) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.alreadyCurrent,
        blockerReasons: const [],
        calculatedScore: current.finalScore,
        inputFingerprint: current.inputFingerprint,
      );
    }
    return LegacyScoringRecoveryProductResult(
      productId: product.id,
      productName: product.name,
      dryRun: false,
      outcome: LegacyScoringRecoveryOutcome.existingEvidenceAuditUnavailable,
      blockerReasons: const ['existing_evidence_audit_unavailable'],
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
    if (!readiness.finalScoreReady) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.blocked,
        blockerReasons: readiness.blockerReasons,
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
      );
    }
    if (result.auditStatus == ProductScoringAuditStatus.current) {
      return LegacyScoringRecoveryProductResult(
        productId: product.id,
        productName: product.name,
        dryRun: false,
        outcome: LegacyScoringRecoveryOutcome.alreadyCurrent,
        blockerReasons: const [],
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

  String formatSummary(LegacyScoringRecoveryBatchSummary summary) {
    final lines = <String>[
      '[summary]',
      'mode=${summary.dryRun ? 'dry_run' : 'apply'}',
      'total_examined=${summary.totalExamined}',
      if (summary.dryRun) 'recoverable=${summary.recoverable}',
      'blocked=${summary.blocked}',
      if (!summary.dryRun) 'already_current=${summary.alreadyCurrent}',
      if (!summary.dryRun)
        'recovered_and_current=${summary.recoveredAndCurrent}',
      if (!summary.dryRun)
        'audit_not_current_after_apply=${summary.auditNotCurrentAfterApply}',
      if (!summary.dryRun)
        'existing_evidence_audit_unavailable='
            '${summary.existingEvidenceAuditUnavailable}',
      'unexpected_errors=${summary.unexpectedErrors}',
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

  String _safe(String value) =>
      value.trim().replaceAll(RegExp(r'[\r\n\t]+'), ' ');
}
