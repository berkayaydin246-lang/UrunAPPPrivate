import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';
import 'package:food_analyzer_app/features/scoring/data/product_scoring_lifecycle_data_source.dart';

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
  ProductScoreAuditCaptureService({
    ProductRepository productRepository = const ProductRepository(),
    ScoreAuditSnapshotRepository auditRepository =
        const SupabaseScoreAuditSnapshotRepository(),
    ProductScoreAuditEvaluator evaluator = const ProductScoreAuditEvaluator(),
  }) : _lifecycle = ProductScoringLifecycleService(
         dataSource: SupabaseProductScoringLifecycleDataSource(
           productRepository: productRepository,
           auditRepository: auditRepository,
         ),
         evaluator: evaluator,
       );

  final ProductScoringLifecycleService _lifecycle;

  @override
  Future<ProductScoreAuditCaptureResult> captureCurrent(
    String productId, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    final result = await _lifecycle.processCurrent(
      productId,
      triggerSource: triggerSource,
    );
    if (result.auditStatus == ProductScoringAuditStatus.failed) {
      throw StateError(result.failureType ?? 'score audit capture failed');
    }
    if (!result.finalScoreReady) {
      return const ProductScoreAuditCaptureResult(
        status: ProductScoreAuditCaptureStatus.notScoringReady,
      );
    }
    return ProductScoreAuditCaptureResult(
      status: result.auditStatus == ProductScoringAuditStatus.inserted
          ? ProductScoreAuditCaptureStatus.inserted
          : ProductScoreAuditCaptureStatus.duplicate,
      snapshotId: result.snapshotId,
    );
  }
}
