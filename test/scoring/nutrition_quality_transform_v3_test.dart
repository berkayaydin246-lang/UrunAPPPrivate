import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';

import 'scoring_test_fixtures.dart';
import 'support/score_audit_test_support.dart';

/// Direct regression coverage for the approved Candidate A recalibration,
/// implemented as `nutrition_quality_transform_v3` — a NEW versioned
/// transform, never a mutation of V2. See the offline calibration audit
/// for the evidence behind these specific anchor values.
void main() {
  const v2 = NutritionQualityTransformer();
  const v3 = NutritionQualityTransformer.v3();

  const v3GeneralAnchors = <(double, double)>[
    (-5.5, 100),
    (0.5, 92),
    (2.5, 78),
    (6.5, 74),
    (10.5, 72),
    (18.5, 66),
    (26.5, 42),
    (34.5, 18),
    (42.5, 0),
  ];
  const v3BeverageAnchors = <(double, double)>[
    (-3.5, 95),
    (2.5, 84),
    (4.5, 76),
    (6.5, 70),
    (9.5, 60),
    (13.5, 40),
    (17.5, 20),
    (21.5, 0),
  ];

  void expectCurve(ScoringCategory category, List<(double, double)> anchors) {
    for (final (raw, quality) in anchors) {
      expect(
        v3.qualityForRawScore(raw, category),
        quality,
        reason: '${category.name} v3 anchor raw=$raw',
      );
    }
    for (var index = 0; index < anchors.length - 1; index += 1) {
      final left = anchors[index];
      final right = anchors[index + 1];
      final midpoint = (left.$1 + right.$1) / 2;
      expect(
        v3.qualityForRawScore(midpoint, category),
        closeTo((left.$2 + right.$2) / 2, 1e-12),
        reason: '${category.name} v3 interpolation region $index',
      );
    }
  }

  group('version identity', () {
    test('v3 constant and instance version string', () {
      expect(
        nutritionQualityTransformV3Version,
        'nutrition_quality_transform_v3',
      );
      expect(v3.transformVersion, nutritionQualityTransformV3Version);
    });

    test(
      'production-default nutritionQualityTransformVersion now points at '
      'V3 — cut over from V2 after full shadow backfill coverage '
      '(4330/4330) was verified',
      () {
        expect(
          nutritionQualityTransformVersion,
          nutritionQualityTransformV3Version,
        );
        expect(
          const NutritionQualityTransformer().transformVersion,
          nutritionQualityTransformV3Version,
        );
      },
    );

    test('V2 remains available and unchanged via .v2()', () {
      const v2 = NutritionQualityTransformer.v2();
      expect(v2.transformVersion, nutritionQualityTransformV2Version);
      expect(v2.qualityForRawScore(2.5, ScoringCategory.generalFood), 86);
    });
  });

  group('approved Candidate A exact anchor curves', () {
    test('generalFood', () {
      expectCurve(ScoringCategory.generalFood, v3GeneralAnchors);
    });

    test('beverage', () {
      expectCurve(ScoringCategory.beverage, v3BeverageAnchors);
    });
  });

  group('PART C — specific regression canaries', () {
    test('generalFood raw=-8 clamps to ceiling 100', () {
      expect(v3.qualityForRawScore(-8, ScoringCategory.generalFood), 100);
    });

    test('generalFood raw=-5 stays essentially at ceiling', () {
      expect(
        v3.qualityForRawScore(-5, ScoringCategory.generalFood),
        closeTo(99.33, 0.01),
      );
    });

    test('generalFood raw=-1', () {
      expect(
        v3.qualityForRawScore(-1, ScoringCategory.generalFood),
        closeTo(94.00, 0.01),
      );
    });

    test('generalFood raw=1', () {
      expect(
        v3.qualityForRawScore(1, ScoringCategory.generalFood),
        closeTo(88.50, 0.01),
      );
    });

    test('generalFood raw=2', () {
      expect(
        v3.qualityForRawScore(2, ScoringCategory.generalFood),
        closeTo(81.50, 0.01),
      );
    });

    test('generalFood raw=4', () {
      expect(
        v3.qualityForRawScore(4, ScoringCategory.generalFood),
        closeTo(76.50, 0.01),
      );
    });

    test('generalFood raw=5 -> 75.50', () {
      expect(v3.qualityForRawScore(5, ScoringCategory.generalFood), 75.50);
    });

    test('generalFood raw=6 -> 74.50', () {
      expect(v3.qualityForRawScore(6, ScoringCategory.generalFood), 74.50);
    });

    test('generalFood raw=22 -> IDENTICAL to V2 (55.50)', () {
      final v3Value = v3.qualityForRawScore(22, ScoringCategory.generalFood);
      final v2Value = v2.qualityForRawScore(22, ScoringCategory.generalFood);
      expect(v3Value, 55.50);
      expect(v3Value, v2Value);
    });

    test('generalFood raw=26 -> IDENTICAL to V2 (43.50)', () {
      final v3Value = v3.qualityForRawScore(26, ScoringCategory.generalFood);
      final v2Value = v2.qualityForRawScore(26, ScoringCategory.generalFood);
      expect(v3Value, 43.50);
      expect(v3Value, v2Value);
    });

    test('beverage raw=4 -> 78.00', () {
      expect(v3.qualityForRawScore(4, ScoringCategory.beverage), 78.00);
    });

    test('beverage raw=7 -> approximately 68.33', () {
      expect(
        v3.qualityForRawScore(7, ScoringCategory.beverage),
        closeTo(68.33, 0.01),
      );
    });

    test('beverage raw=12 -> IDENTICAL to V2 (47.50)', () {
      final v3Value = v3.qualityForRawScore(12, ScoringCategory.beverage);
      final v2Value = v2.qualityForRawScore(12, ScoringCategory.beverage);
      expect(v3Value, 47.50);
      expect(v3Value, v2Value);
    });
  });

  group('V3 leaves cheese/redMeat/fatsOilsNutsSeeds byte-identical to V2', () {
    const rawSamples = <double>[-11.5, -5.5, -3, 0, 2.5, 5, 8, 10.5, 15, 18.5, 22, 26.5, 30, 34.5, 40, 42.5, 50];

    test('cheese', () {
      for (final raw in rawSamples) {
        expect(
          v3.qualityForRawScore(raw, ScoringCategory.cheese),
          v2.qualityForRawScore(raw, ScoringCategory.cheese),
          reason: 'cheese raw=$raw must match V2 exactly',
        );
      }
    });

    test('redMeat', () {
      for (final raw in rawSamples) {
        expect(
          v3.qualityForRawScore(raw, ScoringCategory.redMeat),
          v2.qualityForRawScore(raw, ScoringCategory.redMeat),
          reason: 'redMeat raw=$raw must match V2 exactly',
        );
      }
    });

    test('fatsOilsNutsSeeds', () {
      for (final raw in rawSamples) {
        expect(
          v3.qualityForRawScore(raw, ScoringCategory.fatsOilsNutsSeeds),
          v2.qualityForRawScore(raw, ScoringCategory.fatsOilsNutsSeeds),
          reason: 'fatsOilsNutsSeeds raw=$raw must match V2 exactly',
        );
      }
    });
  });

  group('generalFood/beverage above the recalibrated zone match V2 exactly', () {
    test('generalFood raw>=10.5 identical to V2', () {
      for (final raw in <double>[10.5, 12, 15, 18.5, 22, 26.5, 30, 34.5, 40, 42.5, 60]) {
        expect(
          v3.qualityForRawScore(raw, ScoringCategory.generalFood),
          v2.qualityForRawScore(raw, ScoringCategory.generalFood),
          reason: 'generalFood raw=$raw must match V2 exactly above the '
              'recalibrated zone',
        );
      }
    });

    test('beverage raw>=9.5 identical to V2', () {
      for (final raw in <double>[9.5, 11, 13.5, 17.5, 21.5, 30]) {
        expect(
          v3.qualityForRawScore(raw, ScoringCategory.beverage),
          v2.qualityForRawScore(raw, ScoringCategory.beverage),
          reason: 'beverage raw=$raw must match V2 exactly above the '
              'recalibrated zone',
        );
      }
    });

    test('generalFood raw<=-5.5 identical ceiling ties to V2', () {
      for (final raw in <double>[-5.5, -8, -100]) {
        expect(
          v3.qualityForRawScore(raw, ScoringCategory.generalFood),
          v2.qualityForRawScore(raw, ScoringCategory.generalFood),
        );
      }
    });
  });

  group(
    'V3 audit-snapshot end-to-end validation (regression: '
    'EtiketlyScoreAuditValidator._isSupportedVersionSet previously had no '
    'entry for etiketlyScoreV2Version paired with '
    'nutritionQualityTransformV3Version, so every genuinely-valid V3 '
    'snapshot failed validation with unsupportedVersion — caught only by '
    'running the real V3 backfill tool against production, not by any '
    'unit test that stopped at NutritionQualityTransformer alone)',
    () {
      test(
        'a real V3-evaluated snapshot (built the exact same way '
        'ProductScoreAuditEvaluator does) passes EtiketlyScoreAuditValidator',
        () {
          const orchestrator = ProductEtiketlyScoreOrchestrator(
            nutritionQualityTransformer: NutritionQualityTransformer.v3(),
          );
          final product = auditProductFromInput(
            completeInput(category: ScoringCategory.generalFood),
            id: 'v3-validator-regression',
          );
          final snapshot = buildAuditSnapshot(
            product: product,
            assessment: auditOrdinaryAssessment(),
            orchestrator: orchestrator,
          );

          expect(snapshot.nutritionTransformVersion, v3.transformVersion);
          expect(snapshot.scoreVersion, 'etiketly_score_v2');

          final validation = const EtiketlyScoreAuditValidator().validate(
            snapshot,
          );
          expect(
            validation.isValid,
            isTrue,
            reason: 'issues: ${validation.issues}',
          );
        },
      );

      test(
        'a V3 snapshot round-trips through JSON and still validates',
        () {
          const orchestrator = ProductEtiketlyScoreOrchestrator(
            nutritionQualityTransformer: NutritionQualityTransformer.v3(),
          );
          final product = auditProductFromInput(
            completeInput(category: ScoringCategory.beverage),
            id: 'v3-validator-regression-beverage',
          );
          final snapshot = buildAuditSnapshot(
            product: product,
            assessment: auditOrdinaryAssessment(),
            orchestrator: orchestrator,
          );
          final roundTripped = EtiketlyScoreAuditSnapshot.tryFromJson(
            snapshot.toJson(),
          );
          expect(roundTripped, isNotNull);
          final validation = const EtiketlyScoreAuditValidator().validate(
            roundTripped!,
          );
          expect(
            validation.isValid,
            isTrue,
            reason: 'issues: ${validation.issues}',
          );
        },
      );
    },
  );

  group('interpolation mechanics', () {
    test('below-first-anchor clamps to first anchor quality', () {
      expect(v3.qualityForRawScore(-999, ScoringCategory.generalFood), 100);
      expect(v3.qualityForRawScore(-999, ScoringCategory.beverage), 95);
    });

    test('above-last-anchor clamps to last anchor quality', () {
      expect(v3.qualityForRawScore(999, ScoringCategory.generalFood), 0);
      expect(v3.qualityForRawScore(999, ScoringCategory.beverage), 0);
    });

    test('monotonic non-increasing across the full generalFood domain', () {
      double? previous;
      for (var raw = -20.0; raw <= 60.0; raw += 0.25) {
        final quality = v3.qualityForRawScore(raw, ScoringCategory.generalFood);
        if (previous != null) {
          expect(
            quality,
            lessThanOrEqualTo(previous),
            reason: 'quality must never increase as raw increases (raw=$raw)',
          );
        }
        previous = quality;
      }
    });

    test('monotonic non-increasing across the full beverage domain', () {
      double? previous;
      for (var raw = -10.0; raw <= 30.0; raw += 0.25) {
        final quality = v3.qualityForRawScore(raw, ScoringCategory.beverage);
        if (previous != null) {
          expect(quality, lessThanOrEqualTo(previous));
        }
        previous = quality;
      }
    });

    test('deterministic: identical input always produces identical output', () {
      for (var i = 0; i < 5; i++) {
        expect(v3.qualityForRawScore(5, ScoringCategory.generalFood), 75.50);
        expect(v3.qualityForRawScore(4, ScoringCategory.beverage), 78.00);
      }
      // A second independent instance must agree too — no hidden state.
      const anotherV3 = NutritionQualityTransformer.v3();
      expect(
        anotherV3.qualityForRawScore(5, ScoringCategory.generalFood),
        v3.qualityForRawScore(5, ScoringCategory.generalFood),
      );
    });

    test('rejects non-finite raw input', () {
      for (final value in [double.nan, double.infinity, double.negativeInfinity]) {
        expect(
          () => v3.qualityForRawScore(value, ScoringCategory.generalFood),
          throwsArgumentError,
        );
      }
    });
  });
}
