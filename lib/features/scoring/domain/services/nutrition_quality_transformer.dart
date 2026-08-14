import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class NutritionQualityTransformer {
  const NutritionQualityTransformer()
    : transformVersion = nutritionQualityTransformV2Version;

  const NutritionQualityTransformer.v1()
    : transformVersion = nutritionQualityTransformV1Version;

  final String transformVersion;

  static const _generalV1Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -5.5, quality: 100),
    _QualityAnchor(raw: 0.5, quality: 85),
    _QualityAnchor(raw: 2.5, quality: 70),
    _QualityAnchor(raw: 10.5, quality: 45),
    _QualityAnchor(raw: 18.5, quality: 20),
    _QualityAnchor(raw: 26.5, quality: 0),
  ];

  static const _fatCategoryV1Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -11.5, quality: 100),
    _QualityAnchor(raw: -5.5, quality: 85),
    _QualityAnchor(raw: 2.5, quality: 70),
    _QualityAnchor(raw: 10.5, quality: 45),
    _QualityAnchor(raw: 18.5, quality: 20),
    _QualityAnchor(raw: 26.5, quality: 0),
  ];

  static const _beverageV1Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -3.5, quality: 85),
    _QualityAnchor(raw: 2.5, quality: 70),
    _QualityAnchor(raw: 6.5, quality: 45),
    _QualityAnchor(raw: 9.5, quality: 20),
    _QualityAnchor(raw: 17.5, quality: 0),
  ];

  static const _generalV2Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -5.5, quality: 100),
    _QualityAnchor(raw: 0.5, quality: 94),
    _QualityAnchor(raw: 2.5, quality: 86),
    _QualityAnchor(raw: 10.5, quality: 72),
    _QualityAnchor(raw: 18.5, quality: 66),
    _QualityAnchor(raw: 26.5, quality: 42),
    _QualityAnchor(raw: 34.5, quality: 18),
    _QualityAnchor(raw: 42.5, quality: 0),
  ];

  static const _cheeseV2Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -5.5, quality: 100),
    _QualityAnchor(raw: 0.5, quality: 92),
    _QualityAnchor(raw: 2.5, quality: 84),
    _QualityAnchor(raw: 10.5, quality: 68),
    _QualityAnchor(raw: 18.5, quality: 54),
    _QualityAnchor(raw: 26.5, quality: 32),
    _QualityAnchor(raw: 34.5, quality: 12),
    _QualityAnchor(raw: 42.5, quality: 0),
  ];

  static const _redMeatV2Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -5.5, quality: 100),
    _QualityAnchor(raw: 0.5, quality: 92),
    _QualityAnchor(raw: 2.5, quality: 84),
    _QualityAnchor(raw: 10.5, quality: 70),
    _QualityAnchor(raw: 18.5, quality: 56),
    _QualityAnchor(raw: 26.5, quality: 34),
    _QualityAnchor(raw: 34.5, quality: 14),
    _QualityAnchor(raw: 42.5, quality: 0),
  ];

  static const _fatCategoryV2Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -11.5, quality: 100),
    _QualityAnchor(raw: -5.5, quality: 94),
    _QualityAnchor(raw: 2.5, quality: 82),
    _QualityAnchor(raw: 10.5, quality: 68),
    _QualityAnchor(raw: 18.5, quality: 50),
    _QualityAnchor(raw: 26.5, quality: 30),
    _QualityAnchor(raw: 34.5, quality: 12),
    _QualityAnchor(raw: 42.5, quality: 0),
  ];

  static const _beverageV2Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -3.5, quality: 95),
    _QualityAnchor(raw: 2.5, quality: 88),
    _QualityAnchor(raw: 6.5, quality: 75),
    _QualityAnchor(raw: 9.5, quality: 60),
    _QualityAnchor(raw: 13.5, quality: 40),
    _QualityAnchor(raw: 17.5, quality: 20),
    _QualityAnchor(raw: 21.5, quality: 0),
  ];

  NutritionQualityResult transform(NutritionRawScoreResult rawResult) {
    if (rawResult.isPlainWaterSpecialCase) {
      return NutritionQualityResult(
        qualityScore: 100,
        rawResult: rawResult,
        specialCase: NutritionQualitySpecialCase.plainWater,
        transformVersion: transformVersion,
      );
    }

    final rawScore = rawResult.rawScore;
    if (rawScore == null) {
      throw ArgumentError.value(
        rawScore,
        'rawResult.rawScore',
        'must be present for a non-water result',
      );
    }

    return NutritionQualityResult(
      qualityScore: qualityForRawScore(
        rawScore.toDouble(),
        rawResult.resolvedCategory,
      ),
      rawResult: rawResult,
      specialCase: NutritionQualitySpecialCase.none,
      transformVersion: transformVersion,
    );
  }

  double qualityForRawScore(double rawScore, ScoringCategory category) {
    if (!rawScore.isFinite) {
      throw ArgumentError.value(rawScore, 'rawScore', 'must be finite');
    }
    final anchors = _anchorsFor(category);
    return _interpolate(rawScore, anchors);
  }

  List<_QualityAnchor> _anchorsFor(ScoringCategory category) {
    final isV1 = transformVersion == nutritionQualityTransformV1Version;
    return switch (category) {
      ScoringCategory.generalFood =>
        isV1 ? _generalV1Anchors : _generalV2Anchors,
      ScoringCategory.cheese => isV1 ? _generalV1Anchors : _cheeseV2Anchors,
      ScoringCategory.redMeat => isV1 ? _generalV1Anchors : _redMeatV2Anchors,
      ScoringCategory.fatsOilsNutsSeeds =>
        isV1 ? _fatCategoryV1Anchors : _fatCategoryV2Anchors,
      ScoringCategory.beverage =>
        isV1 ? _beverageV1Anchors : _beverageV2Anchors,
      ScoringCategory.unknown ||
      ScoringCategory.outOfScope => throw ArgumentError.value(
        category,
        'category',
        'must be a supported scoring category',
      ),
    };
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
