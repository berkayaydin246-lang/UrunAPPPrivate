import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class NutritionQualityTransformer {
  const NutritionQualityTransformer();

  static const _generalAnchors = <_QualityAnchor>[
    _QualityAnchor(raw: -5.5, quality: 100),
    _QualityAnchor(raw: 0.5, quality: 85),
    _QualityAnchor(raw: 2.5, quality: 70),
    _QualityAnchor(raw: 10.5, quality: 45),
    _QualityAnchor(raw: 18.5, quality: 20),
    _QualityAnchor(raw: 26.5, quality: 0),
  ];

  static const _fatCategoryAnchors = <_QualityAnchor>[
    _QualityAnchor(raw: -11.5, quality: 100),
    _QualityAnchor(raw: -5.5, quality: 85),
    _QualityAnchor(raw: 2.5, quality: 70),
    _QualityAnchor(raw: 10.5, quality: 45),
    _QualityAnchor(raw: 18.5, quality: 20),
    _QualityAnchor(raw: 26.5, quality: 0),
  ];

  static const _beverageAnchors = <_QualityAnchor>[
    _QualityAnchor(raw: -3.5, quality: 85),
    _QualityAnchor(raw: 2.5, quality: 70),
    _QualityAnchor(raw: 6.5, quality: 45),
    _QualityAnchor(raw: 9.5, quality: 20),
    _QualityAnchor(raw: 17.5, quality: 0),
  ];

  NutritionQualityResult transform(NutritionRawScoreResult rawResult) {
    if (rawResult.isPlainWaterSpecialCase) {
      return NutritionQualityResult(
        qualityScore: 100,
        rawResult: rawResult,
        specialCase: NutritionQualitySpecialCase.plainWater,
      );
    }

    final anchors = switch (rawResult.resolvedCategory) {
      ScoringCategory.generalFood ||
      ScoringCategory.cheese ||
      ScoringCategory.redMeat => _generalAnchors,
      ScoringCategory.fatsOilsNutsSeeds => _fatCategoryAnchors,
      ScoringCategory.beverage => _beverageAnchors,
      ScoringCategory.unknown ||
      ScoringCategory.outOfScope => throw ArgumentError.value(
        rawResult.resolvedCategory,
        'rawResult.resolvedCategory',
        'must be a supported scoring category',
      ),
    };
    final rawScore = rawResult.rawScore;
    if (rawScore == null) {
      throw ArgumentError.value(
        rawScore,
        'rawResult.rawScore',
        'must be present for a non-water result',
      );
    }

    return NutritionQualityResult(
      qualityScore: _interpolate(rawScore.toDouble(), anchors),
      rawResult: rawResult,
      specialCase: NutritionQualitySpecialCase.none,
    );
  }

  double _interpolate(double rawScore, List<_QualityAnchor> anchors) {
    if (rawScore <= anchors.first.raw) return anchors.first.quality;
    if (rawScore >= anchors.last.raw) return anchors.last.quality;

    for (var index = 0; index < anchors.length - 1; index += 1) {
      final left = anchors[index];
      final right = anchors[index + 1];
      if (rawScore <= right.raw) {
        final progress = (rawScore - left.raw) / (right.raw - left.raw);
        return left.quality + progress * (right.quality - left.quality);
      }
    }
    throw StateError('Nutrition quality anchor interpolation failed');
  }
}

class _QualityAnchor {
  final double raw;
  final double quality;

  const _QualityAnchor({required this.raw, required this.quality});
}
