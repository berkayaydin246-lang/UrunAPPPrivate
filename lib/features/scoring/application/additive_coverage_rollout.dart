import 'dart:math' as math;

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/additive_coverage_impact_report.dart';
import 'package:food_analyzer_app/features/scoring/application/legacy_scoring_evidence_recovery.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_backfill.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';

class AdditiveCoverageEvidencePersistenceResult {
  const AdditiveCoverageEvidencePersistenceResult({
    required this.product,
    required this.written,
  });

  final Product product;
  final bool written;
}

abstract interface class AdditiveCoverageRolloutDataSource
    implements AdditiveCoverageImpactDataSource {
  Future<Product?> fetchProductById(String productId);

  Future<AdditiveCoverageEvidencePersistenceResult>
  persistScoringEvidenceIfNull(
    String productId,
    ScoringEvidenceSnapshot evidence,
  );

  Future<ScoreAuditBackfillWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot,
  );
}

class AdditiveCoverageRolloutOptions {
  const AdditiveCoverageRolloutOptions({
    required this.dryRun,
    this.batchSize = 100,
    this.startAfterProductId,
    this.maxProducts,
  }) : assert(batchSize > 0 && batchSize <= 500),
       assert(maxProducts == null || maxProducts > 0),
       assert(dryRun || maxProducts != null);

  final bool dryRun;
  final int batchSize;
  final String? startAfterProductId;
  final int? maxProducts;
}

class AdditiveCoverageRolloutSummary {
  AdditiveCoverageRolloutSummary({
    required this.dryRun,
    required this.safeResumeCursor,
  });

  final bool dryRun;
  int candidateProductsExamined = 0;
  int finalScoreReady = 0;
  int existingScoringEvidence = 0;
  int evidenceWouldWrite = 0;
  int evidenceWritten = 0;
  int alreadyCurrentV2Audit = 0;
  int auditWouldInsert = 0;
  int auditInserted = 0;
  int notReady = 0;
  int errors = 0;
  bool completed = false;
  bool reachedLimit = false;
  String? lastExaminedCursor;
  String? safeResumeCursor;
  final Map<String, int> blockerReasons = {};
  final List<String> failedProductIds = [];

  List<MapEntry<String, int>> topBlockerReasons([int limit = 15]) {
    final entries = blockerReasons.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount != 0 ? byCount : left.key.compareTo(right.key);
      });
    return entries.take(limit).toList(growable: false);
  }
}

class AdditiveCoverageRolloutRunner {
  const AdditiveCoverageRolloutRunner({
    required this.dataSource,
    this.candidateEvaluator = const AdditiveCoverageCandidateEvaluator(),
    this.auditGate = const EtiketlyPublicScoreAuditGate(),
  });

  final AdditiveCoverageRolloutDataSource dataSource;
  final AdditiveCoverageCandidateEvaluator candidateEvaluator;
  final EtiketlyPublicScoreAuditGate auditGate;

  Future<AdditiveCoverageRolloutSummary> run(
    AdditiveCoverageRolloutOptions options,
  ) async {
    final summary = AdditiveCoverageRolloutSummary(
      dryRun: options.dryRun,
      safeResumeCursor: options.startAfterProductId,
    );
    final catalogue = await dataSource.fetchIngredientCatalogue();
    final seenProductIds = <String>{};
    var hasUnresolvedError = false;
    var cursor = options.startAfterProductId;

    while (true) {
      final remaining = options.maxProducts == null
          ? options.batchSize
          : options.maxProducts! - summary.candidateProductsExamined;
      if (remaining <= 0) {
        summary.reachedLimit = true;
        break;
      }
      final products = await dataSource.fetchCandidateProductsAfter(
        afterProductId: cursor,
        limit: math.min(options.batchSize, remaining),
      );
      if (products.isEmpty) {
        summary.completed = true;
        break;
      }
      cursor = products.last.id;
      final page = products
          .where((product) => seenProductIds.add(product.id))
          .toList(growable: false);
      final sourceUrls = page
          .where((product) => product.scoringEvidence == null)
          .map((product) => product.sourceUrl?.trim())
          .whereType<String>()
          .where((sourceUrl) => sourceUrl.isNotEmpty)
          .toSet();
      Map<String, List<LegacyStagingScoringEvidence>> staging = const {};
      Object? stagingError;
      if (sourceUrls.isNotEmpty) {
        try {
          staging = await dataSource.fetchStagingMatches(sourceUrls);
        } on Object catch (error) {
          stagingError = error;
        }
      }

      final concurrency = options.dryRun ? 8 : 1;
      for (var offset = 0; offset < page.length; offset += concurrency) {
        final end = (offset + concurrency).clamp(0, page.length);
        final chunk = page.sublist(offset, end);
        for (final product in chunk) {
          summary.candidateProductsExamined++;
          summary.lastExaminedCursor = product.id;
          if (product.scoringEvidence != null) {
            summary.existingScoringEvidence++;
          }
        }
        final results = await Future.wait(
          chunk.map((product) {
            if (product.scoringEvidence == null && stagingError != null) {
              _recordError(summary, product.id, 'staging_fetch_error');
              return Future.value(false);
            }
            return _processProduct(
              product: product,
              stagingMatches: staging[product.sourceUrl?.trim()] ?? const [],
              catalogue: catalogue,
              options: options,
              summary: summary,
            );
          }),
        );
        for (var index = 0; index < chunk.length; index++) {
          if (!results[index]) hasUnresolvedError = true;
          if (!hasUnresolvedError) {
            summary.safeResumeCursor = chunk[index].id;
          }
        }
      }
    }
    return summary;
  }

  Future<bool> _processProduct({
    required Product product,
    required List<LegacyStagingScoringEvidence> stagingMatches,
    required List<Ingredient> catalogue,
    required AdditiveCoverageRolloutOptions options,
    required AdditiveCoverageRolloutSummary summary,
  }) async {
    late AdditiveCoverageCandidateEvaluation evaluation;
    try {
      evaluation = await candidateEvaluator.evaluate(
        product: product,
        stagingMatches: stagingMatches,
        ingredientCatalogue: catalogue,
      );
    } on Object {
      _recordError(summary, product.id, 'inspection_error');
      return false;
    }
    if (!evaluation.finalScoreReady || evaluation.currentSnapshot == null) {
      summary.notReady++;
      for (final blocker in evaluation.blockers) {
        _countBlocker(summary, blocker);
      }
      return true;
    }

    summary.finalScoreReady++;
    var current = evaluation.currentSnapshot!;
    final recoveredEvidence = evaluation.recoveredEvidence;
    if (recoveredEvidence != null) {
      summary.evidenceWouldWrite++;
      if (!options.dryRun) {
        late final AdditiveCoverageEvidencePersistenceResult persisted;
        try {
          persisted = await dataSource.persistScoringEvidenceIfNull(
            product.id,
            recoveredEvidence,
          );
        } on Object {
          _recordError(summary, product.id, 'evidence_write_error');
          return false;
        }
        if (persisted.written) summary.evidenceWritten++;
        try {
          final persistedEvaluation = await candidateEvaluator.evaluate(
            product: persisted.product,
            stagingMatches: const [],
            ingredientCatalogue: catalogue,
          );
          if (!persistedEvaluation.finalScoreReady ||
              persistedEvaluation.currentSnapshot == null) {
            _recordError(summary, product.id, 'persisted_evidence_not_ready');
            return false;
          }
          current = persistedEvaluation.currentSnapshot!;
        } on Object {
          _recordError(
            summary,
            product.id,
            'persisted_evidence_validation_error',
          );
          return false;
        }
      }
    }

    late final EtiketlyScoreAuditSnapshot? trusted;
    try {
      trusted = await dataSource.fetchMatchingSnapshot(current);
    } on Object {
      _recordError(summary, product.id, 'audit_lookup_error');
      return false;
    }
    final decision = auditGate.evaluate(current: current, trusted: trusted);
    if (decision.status == PublicScoreAuditStatus.matching) {
      summary.alreadyCurrentV2Audit++;
      return true;
    }
    if (trusted != null && _sameUniqueKey(current, trusted)) {
      _recordError(summary, product.id, 'existing_current_key_requires_review');
      return false;
    }

    summary.auditWouldInsert++;
    if (options.dryRun) return true;
    try {
      final write = await dataSource.insertSnapshot(current);
      if (write.inserted) {
        summary.auditInserted++;
        return true;
      }
      final concurrent = await dataSource.fetchMatchingSnapshot(current);
      final concurrentDecision = auditGate.evaluate(
        current: current,
        trusted: concurrent,
      );
      if (concurrentDecision.status == PublicScoreAuditStatus.matching) {
        summary.alreadyCurrentV2Audit++;
        return true;
      }
      _recordError(summary, product.id, 'audit_insert_race_unresolved');
      return false;
    } on Object {
      _recordError(summary, product.id, 'audit_insert_error');
      return false;
    }
  }

  void _countBlocker(AdditiveCoverageRolloutSummary summary, String blocker) {
    summary.blockerReasons.update(
      blocker,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }

  void _recordError(
    AdditiveCoverageRolloutSummary summary,
    String productId,
    String reason,
  ) {
    summary.errors++;
    summary.failedProductIds.add(productId);
    _countBlocker(summary, reason);
  }

  bool _sameUniqueKey(
    EtiketlyScoreAuditSnapshot left,
    EtiketlyScoreAuditSnapshot right,
  ) {
    return left.productId == right.productId &&
        left.inputFingerprint == right.inputFingerprint &&
        left.scoreVersion == right.scoreVersion &&
        left.nutritionMethodologyVersion == right.nutritionMethodologyVersion &&
        left.nutritionTransformVersion == right.nutritionTransformVersion &&
        left.additiveTransformVersion == right.additiveTransformVersion;
  }
}

class AdditiveCoverageRolloutFormatter {
  const AdditiveCoverageRolloutFormatter();

  String format(AdditiveCoverageRolloutSummary summary) {
    final lines = <String>[
      '[SUMMARY]',
      'mode=${summary.dryRun ? 'dry_run' : 'apply'}',
      'candidate_products_examined=${summary.candidateProductsExamined}',
      'final_score_ready=${summary.finalScoreReady}',
      'existing_scoring_evidence=${summary.existingScoringEvidence}',
      'evidence_would_write=${summary.evidenceWouldWrite}',
      'evidence_written=${summary.evidenceWritten}',
      'already_current_v2_audit=${summary.alreadyCurrentV2Audit}',
      'audit_would_insert=${summary.auditWouldInsert}',
      'audit_inserted=${summary.auditInserted}',
      'not_ready=${summary.notReady}',
      'errors=${summary.errors}',
      'last_examined_cursor=${summary.lastExaminedCursor ?? '-'}',
      'safe_resume_cursor=${summary.safeResumeCursor ?? '-'}',
      'completed=${summary.completed}',
      'reached_limit=${summary.reachedLimit}',
      'failed_product_ids=${summary.failedProductIds.isEmpty ? 'none' : summary.failedProductIds.join(',')}',
      '',
      '[TOP BLOCKERS]',
    ];
    final blockers = summary.topBlockerReasons();
    if (blockers.isEmpty) {
      lines.add('none');
    } else {
      for (final blocker in blockers) {
        lines.add('${blocker.key}=${blocker.value}');
      }
    }
    return lines.join('\n');
  }
}
