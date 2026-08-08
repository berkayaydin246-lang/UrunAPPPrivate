import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_snapshot_builder.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';

class ProductScoreAuditEvaluation {
  const ProductScoreAuditEvaluation({
    required this.nutritionReady,
    required this.additiveReady,
    required this.finalScoreReady,
    required this.blockerReasons,
    this.snapshot,
  });

  final bool nutritionReady;
  final bool additiveReady;
  final bool finalScoreReady;
  final List<String> blockerReasons;
  final EtiketlyScoreAuditSnapshot? snapshot;
}

/// Builds the exact current score snapshot without reading or writing audit rows.
class ProductScoreAuditEvaluator {
  const ProductScoreAuditEvaluator({
    this.matcher = const IngredientMatcherService(),
    this.riskService = const CanonicalIngredientRiskService(),
    this.inputAdapter = const ProductScoringInputAdapter(),
    this.orchestrator = const ProductEtiketlyScoreOrchestrator(),
    this.builder = const EtiketlyScoreAuditSnapshotBuilder(),
    this.validator = const EtiketlyScoreAuditValidator(),
  });

  final IngredientMatcherService matcher;
  final CanonicalIngredientRiskService riskService;
  final ProductScoringInputAdapter inputAdapter;
  final ProductEtiketlyScoreOrchestrator orchestrator;
  final EtiketlyScoreAuditSnapshotBuilder builder;
  final EtiketlyScoreAuditValidator validator;

  Future<ProductScoreAuditEvaluation> evaluate(
    Product product,
    List<Ingredient> ingredientCatalogue,
  ) async {
    if (product.scoringEvidence == null) {
      return _blocked('missing_scoring_evidence');
    }

    final ingredientText = product.ingredientsText?.trim() ?? '';
    if (ingredientText.isEmpty) {
      return _blocked('missing_ingredients_text');
    }

    final tokens = matcher.parseIngredients(ingredientText);
    if (tokens.isEmpty) {
      return _blocked('unparseable_ingredients_text');
    }

    final matching = await matcher.matchIngredientTokens(
      tokens,
      ingredientCatalogue,
    );
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
    if (evaluation == null) {
      return _blocked('canonical_assessment_unavailable');
    }

    final nutritionReady = evaluation.nutritionReadiness.isScorable;
    final additiveBlockers = evaluation.finalReadiness.blockingReasons.where(
      (reason) => reason != EtiketlyScoreReadinessBlocker.nutritionNotReady,
    );
    final additiveReady = additiveBlockers.isEmpty;
    final blockers = <String>[
      ...evaluation.nutritionReadiness.blockingReasons.map(
        (reason) => 'nutrition:${reason.name}',
      ),
      ...additiveBlockers.map((reason) => 'additive:${reason.name}'),
    ];
    if (!evaluation.isCalculated) {
      return ProductScoreAuditEvaluation(
        nutritionReady: nutritionReady,
        additiveReady: additiveReady,
        finalScoreReady: false,
        blockerReasons: List.unmodifiable(blockers),
      );
    }

    final snapshot = builder.build(product: product, evaluation: evaluation);
    if (!validator.validate(snapshot).isValid) {
      throw StateError('Generated score audit snapshot failed validation.');
    }
    return ProductScoreAuditEvaluation(
      nutritionReady: nutritionReady,
      additiveReady: additiveReady,
      finalScoreReady: true,
      blockerReasons: const [],
      snapshot: snapshot,
    );
  }

  ProductScoreAuditEvaluation _blocked(String reason) {
    return ProductScoreAuditEvaluation(
      nutritionReady: false,
      additiveReady: false,
      finalScoreReady: false,
      blockerReasons: [reason],
    );
  }
}
