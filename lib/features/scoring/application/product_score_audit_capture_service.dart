import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';

enum ProductScoreAuditCaptureStatus { inserted, duplicate, notScoringReady }

class ProductScoreAuditCaptureResult {
  const ProductScoreAuditCaptureResult({required this.status, this.snapshotId});

  final ProductScoreAuditCaptureStatus status;
  final String? snapshotId;
}

abstract interface class ProductScoreAuditCapture {
  Future<ProductScoreAuditCaptureResult> captureCurrent(
    String productId, {
    required ScoreAuditTriggerSource triggerSource,
  });
}

class ProductScoreAuditCaptureService implements ProductScoreAuditCapture {
  const ProductScoreAuditCaptureService({
    this.productRepository = const ProductRepository(),
    this.auditRepository = const SupabaseScoreAuditSnapshotRepository(),
    this.evaluator = const ProductScoreAuditEvaluator(),
  });

  final ProductRepository productRepository;
  final ScoreAuditSnapshotRepository auditRepository;
  final ProductScoreAuditEvaluator evaluator;

  @override
  Future<ProductScoreAuditCaptureResult> captureCurrent(
    String productId, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    final product = await productRepository.getProductById(productId);
    if (product == null ||
        product.scoringEvidence == null ||
        (product.ingredientsText?.trim().isEmpty ?? true)) {
      return const ProductScoreAuditCaptureResult(
        status: ProductScoreAuditCaptureStatus.notScoringReady,
      );
    }
    final catalogue = await productRepository.getAllIngredients();
    final evaluation = await evaluator.evaluate(product, catalogue);
    final snapshot = evaluation.snapshot;
    if (snapshot == null) {
      return const ProductScoreAuditCaptureResult(
        status: ProductScoreAuditCaptureStatus.notScoringReady,
      );
    }
    final write = await auditRepository.insertTrusted(
      snapshot,
      triggerSource: triggerSource,
    );
    return ProductScoreAuditCaptureResult(
      status: write.inserted
          ? ProductScoreAuditCaptureStatus.inserted
          : ProductScoreAuditCaptureStatus.duplicate,
      snapshotId: write.snapshotId,
    );
  }
}
