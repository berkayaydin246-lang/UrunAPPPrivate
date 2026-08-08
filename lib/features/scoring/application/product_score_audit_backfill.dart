import 'dart:math' as math;

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';

abstract interface class ScoreAuditBackfillDataSource {
  Future<List<Ingredient>> fetchIngredientCatalogue();

  Future<List<Product>> fetchProductsAfter({
    required String? afterProductId,
    required int limit,
  });

  Future<Product?> fetchProductById(String productId);

  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  );

  Future<ScoreAuditBackfillWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot,
  );
}

class ScoreAuditBackfillWriteResult {
  const ScoreAuditBackfillWriteResult({
    required this.snapshotId,
    required this.inserted,
  });

  final String snapshotId;
  final bool inserted;
}

class ScoreAuditBackfillOptions {
  const ScoreAuditBackfillOptions({
    required this.dryRun,
    this.batchSize = 100,
    this.startAfterProductId,
    this.maxProducts,
  }) : assert(batchSize > 0 && batchSize <= 500),
       assert(maxProducts == null || maxProducts > 0);

  final bool dryRun;
  final int batchSize;
  final String? startAfterProductId;
  final int? maxProducts;
}

class ScoreAuditBackfillSummary {
  ScoreAuditBackfillSummary({
    required this.dryRun,
    required this.safeResumeCursor,
  });

  final bool dryRun;
  int totalProductsExamined = 0;
  int nutritionReady = 0;
  int additiveReady = 0;
  int finalScoreReady = 0;
  int alreadyCurrentAudit = 0;
  int missingAudit = 0;
  int staleAudit = 0;
  int invalidAudit = 0;
  int existingAuditRequiresReview = 0;
  int wouldInsert = 0;
  int inserted = 0;
  int duplicateAtWrite = 0;
  int notScorable = 0;
  int errors = 0;
  int batchErrors = 0;
  int batchesFetched = 0;
  bool completed = false;
  bool reachedLimit = false;
  bool halted = false;
  String? lastExaminedCursor;
  String? safeResumeCursor;
  final Map<String, int> blockerReasons = {};
  final List<String> failedProductIds = [];

  List<MapEntry<String, int>> topBlockerReasons([int limit = 10]) {
    final entries = blockerReasons.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount != 0 ? byCount : left.key.compareTo(right.key);
      });
    return entries.take(limit).toList(growable: false);
  }
}

typedef ScoreAuditBackfillProgress =
    void Function(ScoreAuditBackfillSummary summary);

class ScoreAuditBackfillRunner {
  const ScoreAuditBackfillRunner({
    required this.dataSource,
    this.evaluator = const ProductScoreAuditEvaluator(),
    this.gate = const EtiketlyPublicScoreAuditGate(),
  });

  final ScoreAuditBackfillDataSource dataSource;
  final ProductScoreAuditEvaluator evaluator;
  final EtiketlyPublicScoreAuditGate gate;

  Future<ScoreAuditBackfillSummary> run(
    ScoreAuditBackfillOptions options, {
    ScoreAuditBackfillProgress? onBatchComplete,
  }) async {
    final summary = ScoreAuditBackfillSummary(
      dryRun: options.dryRun,
      safeResumeCursor: options.startAfterProductId,
    );
    late final List<Ingredient> catalogue;
    try {
      catalogue = await dataSource.fetchIngredientCatalogue();
    } catch (_) {
      summary.errors++;
      summary.batchErrors++;
      summary.halted = true;
      return summary;
    }

    var cursor = options.startAfterProductId;
    var hasUnresolvedError = false;
    while (true) {
      final remaining = options.maxProducts == null
          ? options.batchSize
          : options.maxProducts! - summary.totalProductsExamined;
      if (remaining <= 0) {
        summary.reachedLimit = true;
        break;
      }
      final pageLimit = math.min(options.batchSize, remaining);
      late final List<Product> products;
      try {
        products = await dataSource.fetchProductsAfter(
          afterProductId: cursor,
          limit: pageLimit,
        );
        summary.batchesFetched++;
      } catch (_) {
        summary.errors++;
        summary.batchErrors++;
        summary.halted = true;
        break;
      }
      if (products.isEmpty) {
        summary.completed = true;
        break;
      }

      for (final product in products) {
        summary.totalProductsExamined++;
        summary.lastExaminedCursor = product.id;
        final succeeded = await _processProduct(
          product,
          catalogue,
          options,
          summary,
        );
        if (!succeeded) hasUnresolvedError = true;
        if (!hasUnresolvedError) summary.safeResumeCursor = product.id;
        cursor = product.id;
      }
      onBatchComplete?.call(summary);
    }
    return summary;
  }

  Future<bool> _processProduct(
    Product product,
    List<Ingredient> catalogue,
    ScoreAuditBackfillOptions options,
    ScoreAuditBackfillSummary summary,
  ) async {
    late final ProductScoreAuditEvaluation evaluation;
    try {
      evaluation = await evaluator.evaluate(product, catalogue);
    } catch (_) {
      _recordError(summary, product.id);
      return false;
    }

    if (evaluation.nutritionReady) summary.nutritionReady++;
    if (evaluation.additiveReady) summary.additiveReady++;
    if (evaluation.finalScoreReady) summary.finalScoreReady++;
    final current = evaluation.snapshot;
    if (current == null) {
      summary.notScorable++;
      for (final reason in evaluation.blockerReasons) {
        summary.blockerReasons.update(
          reason,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
      return true;
    }

    late final EtiketlyScoreAuditSnapshot? trusted;
    try {
      trusted = await dataSource.fetchMatchingSnapshot(current);
    } catch (_) {
      _recordError(summary, product.id);
      return false;
    }
    final decision = gate.evaluate(current: current, trusted: trusted);
    if (decision.status == PublicScoreAuditStatus.matching) {
      summary.alreadyCurrentAudit++;
      return true;
    }
    if (decision.status == PublicScoreAuditStatus.missing) {
      summary.missingAudit++;
    } else if (decision.status == PublicScoreAuditStatus.stale) {
      summary.staleAudit++;
    } else {
      summary.invalidAudit++;
    }

    if (trusted != null && _sameUniqueKey(current, trusted)) {
      summary.existingAuditRequiresReview++;
      summary.blockerReasons.update(
        'existing_current_key_requires_review',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      _recordError(summary, product.id);
      return false;
    }

    summary.wouldInsert++;
    if (options.dryRun) return true;
    try {
      final write = await dataSource.insertSnapshot(current);
      if (write.inserted) {
        summary.inserted++;
      } else {
        summary.duplicateAtWrite++;
      }
      return true;
    } catch (_) {
      _recordError(summary, product.id);
      return false;
    }
  }

  void _recordError(ScoreAuditBackfillSummary summary, String productId) {
    summary.errors++;
    summary.failedProductIds.add(productId);
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

class ScoreAuditSampleInspection {
  const ScoreAuditSampleInspection({
    required this.productId,
    required this.barcode,
    required this.currentCalculatedScore,
    required this.snapshotScore,
    required this.fingerprintMatch,
    required this.currentVersions,
    required this.snapshotVersions,
    required this.validationStatus,
    required this.gateStatus,
    this.error,
  });

  final String productId;
  final String? barcode;
  final double? currentCalculatedScore;
  final double? snapshotScore;
  final bool fingerprintMatch;
  final String? currentVersions;
  final String? snapshotVersions;
  final String validationStatus;
  final String gateStatus;
  final String? error;
}

class ScoreAuditSampleInspector {
  const ScoreAuditSampleInspector({
    required this.dataSource,
    this.evaluator = const ProductScoreAuditEvaluator(),
    this.validator = const EtiketlyScoreAuditValidator(),
    this.gate = const EtiketlyPublicScoreAuditGate(),
  });

  final ScoreAuditBackfillDataSource dataSource;
  final ProductScoreAuditEvaluator evaluator;
  final EtiketlyScoreAuditValidator validator;
  final EtiketlyPublicScoreAuditGate gate;

  Future<List<ScoreAuditSampleInspection>> inspect(
    Iterable<String> productIds,
  ) async {
    final catalogue = await dataSource.fetchIngredientCatalogue();
    final results = <ScoreAuditSampleInspection>[];
    for (final productId in productIds) {
      try {
        final product = await dataSource.fetchProductById(productId);
        if (product == null) {
          results.add(_error(productId, 'product_not_found'));
          continue;
        }
        final evaluation = await evaluator.evaluate(product, catalogue);
        final current = evaluation.snapshot;
        final trusted = current == null
            ? null
            : await dataSource.fetchMatchingSnapshot(current);
        final validation = trusted == null ? null : validator.validate(trusted);
        final decision = current == null
            ? null
            : gate.evaluate(current: current, trusted: trusted);
        results.add(
          ScoreAuditSampleInspection(
            productId: product.id,
            barcode: product.barcode,
            currentCalculatedScore: current?.finalScore,
            snapshotScore: trusted?.finalScore,
            fingerprintMatch:
                current != null &&
                trusted != null &&
                current.inputFingerprint == trusted.inputFingerprint,
            currentVersions: _versions(current),
            snapshotVersions: _versions(trusted),
            validationStatus: trusted == null
                ? 'missing'
                : validation!.isValid
                ? 'valid'
                : 'invalid:${validation.issues.map((issue) => issue.name).join(',')}',
            gateStatus: decision?.status.name ?? 'current_not_scorable',
          ),
        );
      } catch (_) {
        results.add(_error(productId, 'inspection_error'));
      }
    }
    return results;
  }

  ScoreAuditSampleInspection _error(String productId, String reason) {
    return ScoreAuditSampleInspection(
      productId: productId,
      barcode: null,
      currentCalculatedScore: null,
      snapshotScore: null,
      fingerprintMatch: false,
      currentVersions: null,
      snapshotVersions: null,
      validationStatus: 'unavailable',
      gateStatus: 'unavailable',
      error: reason,
    );
  }

  String? _versions(EtiketlyScoreAuditSnapshot? snapshot) {
    if (snapshot == null) return null;
    return [
      'schema=${snapshot.schemaVersion}',
      'score=${snapshot.scoreVersion}',
      'nutrition=${snapshot.nutritionMethodologyVersion}',
      'nutrition_transform=${snapshot.nutritionTransformVersion}',
      'additive_transform=${snapshot.additiveTransformVersion}',
    ].join(';');
  }
}
