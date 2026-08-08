import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

const nutritionQualityTransformVersion = 'nutrition_quality_transform_v1';

enum NutritionQualitySpecialCase { none, plainWater }

class NutritionQualityResult {
  final double qualityScore;
  final NutritionRawScoreResult rawResult;
  final String transformVersion;
  final ScoringCategory category;
  final NutritionQualitySpecialCase specialCase;

  NutritionQualityResult({
    required this.qualityScore,
    required this.rawResult,
    required this.specialCase,
  }) : assert(qualityScore >= 0 && qualityScore <= 100),
       transformVersion = nutritionQualityTransformVersion,
       category = rawResult.resolvedCategory;

  bool get isPlainWaterSpecialCase =>
      specialCase == NutritionQualitySpecialCase.plainWater;
}
