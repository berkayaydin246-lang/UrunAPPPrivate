import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class NutritionQualityTransformer {
  /// Production-current as of the V3 cutover: approved Candidate A
  /// recalibration (see the offline calibration audit — generalFood/
  /// beverage anchors re-shaped in the raw 0.5–6.5 region only; everything
  /// else — cheese/redMeat/fatsOilsNutsSeeds, raw point thresholds,
  /// additive transform, 80/20 weighting — unchanged from V2). Equivalent
  /// to calling [NutritionQualityTransformer.v3] explicitly; both exist so
  /// existing explicit-v3 call sites (backfill/coverage tooling, tests
  /// written before cutover) keep working unchanged.
  const NutritionQualityTransformer()
    : transformVersion = nutritionQualityTransformV3Version;

  const NutritionQualityTransformer.v1()
    : transformVersion = nutritionQualityTransformV1Version;

  /// Frozen historical version — no longer production-current as of the
  /// V3 cutover, but fully reconstructable forever (same anchors, same
  /// behavior, never mutated) for old audit snapshots and tests that
  /// specifically need V2's numbers.
  const NutritionQualityTransformer.v2()
    : transformVersion = nutritionQualityTransformV2Version;

  const NutritionQualityTransformer.v3()
    : transformVersion = nutritionQualityTransformV3Version;

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

  /// Approved Candidate A (offline calibration audit). Re-anchors ONLY the
  /// raw 0.5–6.5 region relative to V2 — the (-5.5,100) ceiling, and every
  /// anchor from 10.5 onward, are IDENTICAL to V2, so raw scores at or
  /// below -5.5 or at or above 10.5 produce byte-identical quality values
  /// to V2. A new intermediate anchor at 6.5 exists purely for resolution
  /// inside the recalibrated zone — same domain, no discontinuity.
  static const _generalV3Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -5.5, quality: 100),
    _QualityAnchor(raw: 0.5, quality: 92),
    _QualityAnchor(raw: 2.5, quality: 78),
    _QualityAnchor(raw: 6.5, quality: 74),
    _QualityAnchor(raw: 10.5, quality: 72),
    _QualityAnchor(raw: 18.5, quality: 66),
    _QualityAnchor(raw: 26.5, quality: 42),
    _QualityAnchor(raw: 34.5, quality: 18),
    _QualityAnchor(raw: 42.5, quality: 0),
  ];

  /// Approved Candidate A (offline calibration audit). Re-anchors ONLY the
  /// raw -3.5..6.5 region relative to V2 — every anchor from 9.5 onward is
  /// IDENTICAL to V2. A new intermediate anchor at 4.5 gives resolution
  /// inside the NNS-beverage-dense zone.
  static const _beverageV3Anchors = <_QualityAnchor>[
    _QualityAnchor(raw: -3.5, quality: 95),
    _QualityAnchor(raw: 2.5, quality: 84),
    _QualityAnchor(raw: 4.5, quality: 76),
    _QualityAnchor(raw: 6.5, quality: 70),
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
    // cheese/redMeat/fatsOilsNutsSeeds are deliberately NOT re-anchored by
    // V3 (approved Candidate A only touched generalFood/beverage) — V3
    // reuses the exact same V2 anchor lists for those three categories, so
    // results are byte-identical to V2, never a parallel duplicated copy
    // that could silently drift.
    return switch (transformVersion) {
      nutritionQualityTransformV1Version => switch (category) {
        ScoringCategory.generalFood ||
        ScoringCategory.cheese ||
        ScoringCategory.redMeat => _generalV1Anchors,
        ScoringCategory.fatsOilsNutsSeeds => _fatCategoryV1Anchors,
        ScoringCategory.beverage => _beverageV1Anchors,
        ScoringCategory.unknown || ScoringCategory.outOfScope =>
          throw ArgumentError.value(
            category,
            'category',
            'must be a supported scoring category',
          ),
      },
      nutritionQualityTransformV3Version => switch (category) {
        ScoringCategory.generalFood => _generalV3Anchors,
        ScoringCategory.cheese => _cheeseV2Anchors,
        ScoringCategory.redMeat => _redMeatV2Anchors,
        ScoringCategory.fatsOilsNutsSeeds => _fatCategoryV2Anchors,
        ScoringCategory.beverage => _beverageV3Anchors,
        ScoringCategory.unknown || ScoringCategory.outOfScope =>
          throw ArgumentError.value(
            category,
            'category',
            'must be a supported scoring category',
          ),
      },
      _ => switch (category) {
        ScoringCategory.generalFood => _generalV2Anchors,
        ScoringCategory.cheese => _cheeseV2Anchors,
        ScoringCategory.redMeat => _redMeatV2Anchors,
        ScoringCategory.fatsOilsNutsSeeds => _fatCategoryV2Anchors,
        ScoringCategory.beverage => _beverageV2Anchors,
        ScoringCategory.unknown || ScoringCategory.outOfScope =>
          throw ArgumentError.value(
            category,
            'category',
            'must be a supported scoring category',
          ),
      },
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
