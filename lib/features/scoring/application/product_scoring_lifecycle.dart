import 'dart:convert';

import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

enum ProductScoringEvidenceStatus {
  existing,
  persisted,
  updated,
  concurrentExisting,
  unavailable,
}

enum ProductScoringAuditStatus {
  notReady,
  current,
  inserted,
  duplicate,
  failed,
}

class ProductScoringEvidenceResolution {
  const ProductScoringEvidenceResolution({
    required this.evidence,
    this.blockerReasons = const [],
  });

  final ScoringEvidenceSnapshot? evidence;
  final List<String> blockerReasons;
}

typedef ProductScoringEvidenceResolver =
    Future<ProductScoringEvidenceResolution> Function(
      Product product,
      List<Ingredient> ingredientCatalogue,
    );

class ProductScoringLifecycleResult {
  const ProductScoringLifecycleResult({
    required this.productId,
    required this.evidenceStatus,
    required this.auditStatus,
    required this.nutritionReady,
    required this.additiveReady,
    required this.finalScoreReady,
    required this.blockerReasons,
    this.calculatedScore,
    this.inputFingerprint,
    this.snapshotId,
    this.failureType,
  });

  final String productId;
  final ProductScoringEvidenceStatus evidenceStatus;
  final ProductScoringAuditStatus auditStatus;
  final bool nutritionReady;
  final bool additiveReady;
  final bool finalScoreReady;
  final List<String> blockerReasons;
  final double? calculatedScore;
  final String? inputFingerprint;
  final String? snapshotId;
  final String? failureType;

  bool get succeeded => auditStatus != ProductScoringAuditStatus.failed;
}

abstract interface class ProductScoringLifecycleDataSource {
  Future<Product?> fetchProduct(String productId);

  Future<List<Ingredient>> fetchIngredientCatalogue();

  /// Persists evidence produced from the current trusted ingestion input.
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence, {
    required ScoringEvidenceSnapshot? expectedCurrent,
  });

  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  );

  Future<ScoreAuditSnapshotWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  });
}

/// Source-neutral production boundary for persisted product scoring.
///
/// Ingestion adapters may provide trusted evidence or an evidence resolver, but
/// matching, readiness, score calculation, fingerprinting, and audit creation
/// always flow through [ProductScoreAuditEvaluator].
class ProductScoringLifecycleService {
  const ProductScoringLifecycleService({
    required this.dataSource,
    this.evaluator = const ProductScoreAuditEvaluator(),
  });

  final ProductScoringLifecycleDataSource dataSource;
  final ProductScoreAuditEvaluator evaluator;

  Future<ProductScoringLifecycleResult> processCurrent(
    String productId, {
    required ScoreAuditTriggerSource triggerSource,
    ProductScoringEvidenceResolver? evidenceResolver,
  }) async {
    var evidenceStatus = ProductScoringEvidenceStatus.unavailable;
    var recoveryBlockers = const <String>[];

    try {
      var product = await dataSource.fetchProduct(productId);
      if (product == null) {
        return _failed(
          productId,
          evidenceStatus: evidenceStatus,
          failureType: 'product_not_found',
        );
      }
      final catalogue = await dataSource.fetchIngredientCatalogue();

      final existingEvidence = product.scoringEvidence;
      if (existingEvidence != null) {
        evidenceStatus = ProductScoringEvidenceStatus.existing;
      }
      if (evidenceResolver != null) {
        final resolution = await evidenceResolver(product, catalogue);
        recoveryBlockers = List.unmodifiable(resolution.blockerReasons);
        final recovered = resolution.evidence;
        if (recovered == null) {
          return ProductScoringLifecycleResult(
            productId: productId,
            evidenceStatus: evidenceStatus,
            auditStatus: ProductScoringAuditStatus.notReady,
            nutritionReady: false,
            additiveReady: false,
            finalScoreReady: false,
            blockerReasons: _orderedUnique([
              ...recoveryBlockers,
              'current_ingestion_evidence_unavailable',
            ]),
          );
        }
        if (!_sameEvidence(existingEvidence, recovered)) {
          final written = await dataSource.writeScoringEvidence(
            productId,
            recovered,
            expectedCurrent: existingEvidence,
          );
          evidenceStatus = switch ((written, existingEvidence)) {
            (true, null) => ProductScoringEvidenceStatus.persisted,
            (true, _) => ProductScoringEvidenceStatus.updated,
            (false, _) => ProductScoringEvidenceStatus.concurrentExisting,
          };
          product = await dataSource.fetchProduct(productId);
          if (product == null) {
            return _failed(
              productId,
              evidenceStatus: evidenceStatus,
              failureType: 'product_disappeared_after_evidence_write',
            );
          }
        }
      }

      final evaluation = await evaluator.evaluate(product, catalogue);
      final snapshot = evaluation.snapshot;
      if (snapshot == null) {
        return ProductScoringLifecycleResult(
          productId: productId,
          evidenceStatus: evidenceStatus,
          auditStatus: ProductScoringAuditStatus.notReady,
          nutritionReady: evaluation.nutritionReady,
          additiveReady: evaluation.additiveReady,
          finalScoreReady: false,
          blockerReasons: _orderedUnique([
            ...recoveryBlockers,
            ...evaluation.blockerReasons,
          ]),
        );
      }

      final existing = await dataSource.fetchMatchingSnapshot(snapshot);
      if (existing != null) {
        if (!evaluator.validator.validate(existing).isValid) {
          throw StateError('Current score audit snapshot failed validation.');
        }
        return _ready(
          productId,
          snapshot,
          evidenceStatus: evidenceStatus,
          auditStatus: ProductScoringAuditStatus.current,
        );
      }

      final write = await dataSource.insertSnapshot(
        snapshot,
        triggerSource: triggerSource,
      );
      return _ready(
        productId,
        snapshot,
        evidenceStatus: evidenceStatus,
        auditStatus: write.inserted
            ? ProductScoringAuditStatus.inserted
            : ProductScoringAuditStatus.duplicate,
        snapshotId: write.snapshotId,
      );
    } on Object catch (error) {
      return _failed(
        productId,
        evidenceStatus: evidenceStatus,
        failureType: error.runtimeType.toString(),
      );
    }
  }

  ProductScoringLifecycleResult _ready(
    String productId,
    EtiketlyScoreAuditSnapshot snapshot, {
    required ProductScoringEvidenceStatus evidenceStatus,
    required ProductScoringAuditStatus auditStatus,
    String? snapshotId,
  }) {
    return ProductScoringLifecycleResult(
      productId: productId,
      evidenceStatus: evidenceStatus,
      auditStatus: auditStatus,
      nutritionReady: true,
      additiveReady: true,
      finalScoreReady: true,
      blockerReasons: const [],
      calculatedScore: snapshot.finalScore,
      inputFingerprint: snapshot.inputFingerprint,
      snapshotId: snapshotId,
    );
  }

  ProductScoringLifecycleResult _failed(
    String productId, {
    required ProductScoringEvidenceStatus evidenceStatus,
    required String failureType,
  }) {
    return ProductScoringLifecycleResult(
      productId: productId,
      evidenceStatus: evidenceStatus,
      auditStatus: ProductScoringAuditStatus.failed,
      nutritionReady: false,
      additiveReady: false,
      finalScoreReady: false,
      blockerReasons: const ['scoring_lifecycle_failed'],
      failureType: failureType,
    );
  }

  static List<String> _orderedUnique(Iterable<String> values) {
    final seen = <String>{};
    return List.unmodifiable(values.where(seen.add));
  }

  static bool _sameEvidence(
    ScoringEvidenceSnapshot? existing,
    ScoringEvidenceSnapshot recovered,
  ) {
    return existing != null &&
        jsonEncode(existing.toJson()) == jsonEncode(recovered.toJson());
  }
}
