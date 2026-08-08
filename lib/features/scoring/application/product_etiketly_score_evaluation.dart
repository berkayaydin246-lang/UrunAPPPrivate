import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';

/// Complete deterministic calculation state used to build an audit snapshot.
class ProductEtiketlyScoreEvaluation {
  const ProductEtiketlyScoreEvaluation({
    required this.input,
    required this.nutritionReadiness,
    required this.rawNutrition,
    required this.nutritionQuality,
    required this.additiveQuality,
    required this.finalReadiness,
    required this.result,
  });

  final EtiketlyScoringInput input;
  final ScoringReadinessResult nutritionReadiness;
  final NutritionRawScoreResult? rawNutrition;
  final NutritionQualityResult? nutritionQuality;
  final AdditiveQualityResult additiveQuality;
  final EtiketlyScoreReadinessResult finalReadiness;
  final EtiketlyScoreResult result;

  bool get isCalculated => result.isCalculated;
}
