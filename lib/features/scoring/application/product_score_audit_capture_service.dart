import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_snapshot_builder.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';

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
    this.matcher = const IngredientMatcherService(),
    this.riskService = const CanonicalIngredientRiskService(),
    this.inputAdapter = const ProductScoringInputAdapter(),
    this.orchestrator = const ProductEtiketlyScoreOrchestrator(),
    this.builder = const EtiketlyScoreAuditSnapshotBuilder(),
    this.validator = const EtiketlyScoreAuditValidator(),
  });

  final ProductRepository productRepository;
  final ScoreAuditSnapshotRepository auditRepository;
  final IngredientMatcherService matcher;
  final CanonicalIngredientRiskService riskService;
  final ProductScoringInputAdapter inputAdapter;
  final ProductEtiketlyScoreOrchestrator orchestrator;
  final EtiketlyScoreAuditSnapshotBuilder builder;
  final EtiketlyScoreAuditValidator validator;

  @override
  Future<ProductScoreAuditCaptureResult> captureCurrent(
    String productId, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    final product = await productRepository.getProductById(productId);
    final ingredientText = product?.ingredientsText?.trim() ?? '';
    if (product == null ||
        product.scoringEvidence == null ||
        ingredientText.isEmpty) {
      return const ProductScoreAuditCaptureResult(
        status: ProductScoreAuditCaptureStatus.notScoringReady,
      );
    }

    final tokens = matcher.parseIngredients(ingredientText);
    if (tokens.isEmpty) {
      return const ProductScoreAuditCaptureResult(
        status: ProductScoreAuditCaptureStatus.notScoringReady,
      );
    }
    final catalogue = await productRepository.getAllIngredients();
    final matching = await matcher.matchIngredientTokens(tokens, catalogue);
    final scoringCategory = inputAdapter
        .fromProduct(product)
        .categoryEvidence
        .resolvedCategory;
    final canonicalAssessment = riskService.assess(
      matching,
      scoringCategory: scoringCategory,
    );
    final evaluation = orchestrator.calculate(
      product: product,
      canonicalAssessment: canonicalAssessment,
    );
    if (evaluation == null || !evaluation.isCalculated) {
      return const ProductScoreAuditCaptureResult(
        status: ProductScoreAuditCaptureStatus.notScoringReady,
      );
    }

    final snapshot = builder.build(product: product, evaluation: evaluation);
    if (!validator.validate(snapshot).isValid) {
      throw StateError('Generated score audit snapshot failed validation.');
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
