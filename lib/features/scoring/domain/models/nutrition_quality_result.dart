import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

const nutritionQualityTransformV1Version = 'nutrition_quality_transform_v1';
const nutritionQualityTransformV2Version = 'nutrition_quality_transform_v2';
const nutritionQualityTransformVersion = nutritionQualityTransformV2Version;

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
    this.transformVersion = nutritionQualityTransformVersion,
  }) : assert(qualityScore >= 0 && qualityScore <= 100),
       category = rawResult.resolvedCategory;

  bool get isPlainWaterSpecialCase =>
      specialCase == NutritionQualitySpecialCase.plainWater;
}
