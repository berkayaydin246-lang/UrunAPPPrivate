import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_evaluation.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/validated_nutrition_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_readiness_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_raw_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

class ProductEtiketlyScoreOrchestrator {
  const ProductEtiketlyScoreOrchestrator({
    this.inputAdapter = const ProductScoringInputAdapter(),
    this.nutritionReadinessEvaluator = const ScoringReadinessEvaluator(),
    this.nutritionRawScoreCalculator = const NutritionRawScoreCalculator(),
    this.nutritionQualityTransformer = const NutritionQualityTransformer(),
    this.additiveQualityTransformer = const AdditiveQualityTransformer(),
    this.finalReadinessEvaluator = const EtiketlyScoreReadinessEvaluator(),
    this.finalScoreCalculator = const EtiketlyScoreCalculator(),
    this.presentationMapper = const EtiketlyScorePresentationMapper(),
  });

  final ProductScoringInputAdapter inputAdapter;
  final ScoringReadinessEvaluator nutritionReadinessEvaluator;
  final NutritionRawScoreCalculator nutritionRawScoreCalculator;
  final NutritionQualityTransformer nutritionQualityTransformer;
  final AdditiveQualityTransformer additiveQualityTransformer;
  final EtiketlyScoreReadinessEvaluator finalReadinessEvaluator;
  final EtiketlyScoreCalculator finalScoreCalculator;
  final EtiketlyScorePresentationMapper presentationMapper;

  ProductEtiketlyScoreState evaluate({
    required Product product,
    required CanonicalAdditiveAssessment? canonicalAssessment,
  }) {
    final evaluation = calculate(
      product: product,
      canonicalAssessment: canonicalAssessment,
    );
    if (evaluation == null) {
      return presentationMapper.missingCanonicalAssessment();
    }
    return presentationMapper.fromResult(evaluation.result);
  }

  ProductEtiketlyScoreEvaluation? calculate({
    required Product product,
    required CanonicalAdditiveAssessment? canonicalAssessment,
  }) {
    if (canonicalAssessment == null) {
      return null;
    }

    final input = inputAdapter.fromProduct(product);
    final nutritionReadiness = nutritionReadinessEvaluator.evaluate(input);
    final additiveQuality = additiveQualityTransformer.transform(
      canonicalAssessment,
    );
    final finalReadiness = finalReadinessEvaluator.evaluate(
      nutritionReadiness: nutritionReadiness,
      ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness,
      additiveQuality: additiveQuality,
    );

    NutritionRawScoreResult? rawNutrition;
    NutritionQualityResult? nutritionQuality;
    if (nutritionReadiness.isScorable) {
      final validatedInput = ValidatedNutritionScoringInput.validate(input);
      rawNutrition = nutritionRawScoreCalculator.calculate(validatedInput);
      nutritionQuality = nutritionQualityTransformer.transform(rawNutrition);
    }

    final result = finalScoreCalculator.calculate(
      nutritionQuality: nutritionQuality,
      additiveQuality: additiveQuality,
      readiness: finalReadiness,
    );
    return ProductEtiketlyScoreEvaluation(
      input: input,
      nutritionReadiness: nutritionReadiness,
      rawNutrition: rawNutrition,
      nutritionQuality: nutritionQuality,
      additiveQuality: additiveQuality,
      finalReadiness: finalReadiness,
      result: result,
    );
  }
}
