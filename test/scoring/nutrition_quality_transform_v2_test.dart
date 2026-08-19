import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_validator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/score_audit_fingerprint.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

import '../../tool/support/score_v2_calibration_support.dart';
import 'support/etiketly_score_test_support.dart';
import 'support/score_audit_test_support.dart';

void main() {
  const v1 = NutritionQualityTransformer.v1();
  const v2 = NutritionQualityTransformer.v2();

  const generalAnchors = <(double, double)>[
    (-5.5, 100),
    (0.5, 94),
    (2.5, 86),
    (10.5, 72),
    (18.5, 66),
    (26.5, 42),
    (34.5, 18),
    (42.5, 0),
  ];
  const cheeseAnchors = <(double, double)>[
    (-5.5, 100),
    (0.5, 92),
    (2.5, 84),
    (10.5, 68),
    (18.5, 54),
    (26.5, 32),
    (34.5, 12),
    (42.5, 0),
  ];
  const redMeatAnchors = <(double, double)>[
    (-5.5, 100),
    (0.5, 92),
    (2.5, 84),
    (10.5, 70),
    (18.5, 56),
    (26.5, 34),
    (34.5, 14),
    (42.5, 0),
  ];
  const fatAnchors = <(double, double)>[
    (-11.5, 100),
    (-5.5, 94),
    (2.5, 82),
    (10.5, 68),
    (18.5, 50),
    (26.5, 30),
    (34.5, 12),
    (42.5, 0),
  ];
  const beverageAnchors = <(double, double)>[
    (-3.5, 95),
    (2.5, 88),
    (6.5, 75),
    (9.5, 60),
    (13.5, 40),
    (17.5, 20),
    (21.5, 0),
  ];

  void expectCurve(ScoringCategory category, List<(double, double)> anchors) {
    for (final (raw, quality) in anchors) {
      expect(
        v2.qualityForRawScore(raw, category),
        quality,
        reason: '${category.name} anchor raw=$raw',
      );
    }
    for (var index = 0; index < anchors.length - 1; index += 1) {
      final left = anchors[index];
      final right = anchors[index + 1];
      final midpoint = (left.$1 + right.$1) / 2;
      expect(
        v2.qualityForRawScore(midpoint, category),
        closeTo((left.$2 + right.$2) / 2, 1e-12),
        reason: '${category.name} interpolation region $index',
      );
    }
  }

  test('v2 general-food anchors and regions are exact', () {
    expectCurve(ScoringCategory.generalFood, generalAnchors);
  });

  test('v2 cheese anchors and regions are exact', () {
    expectCurve(ScoringCategory.cheese, cheeseAnchors);
  });

  test('v2 red-meat anchors and regions are exact', () {
    expectCurve(ScoringCategory.redMeat, redMeatAnchors);
  });

  test('v2 fats/oils/nuts/seeds anchors and regions are exact', () {
    expectCurve(ScoringCategory.fatsOilsNutsSeeds, fatAnchors);
  });

  test('v2 beverage anchors and regions are exact', () {
    expectCurve(ScoringCategory.beverage, beverageAnchors);
  });

  test('calibration raw-score API rejects non-finite input', () {
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => v2.qualityForRawScore(value, ScoringCategory.generalFood),
        throwsArgumentError,
      );
    }
  });

  test('v1 curve and version remain available without mutation', () {
    expect(
      nutritionQualityTransformV1Version,
      'nutrition_quality_transform_v1',
    );
    expect(etiketlyScoreV1Version, 'etiketly_score_v1');
    expect(v1.qualityForRawScore(0.5, ScoringCategory.generalFood), 85);
    expect(v1.qualityForRawScore(2.5, ScoringCategory.beverage), 70);
  });

  final results = {
    for (final fixture in scoreV2CalibrationFixtures)
      fixture.name: evaluateScoreV2Calibration(fixture),
  };

  test('A strong balanced food remains in the high 90s', () {
    final result = results['A strong balanced general food']!;
    expect(result.nutritionQualityV2, inInclusiveRange(88, 100));
    expect(result.finalV2, inInclusiveRange(88, 100));
  });

  test('B one major salt negative is material but does not collapse', () {
    final result = results['B tarhana-like one major salt negative']!;
    expect(result.rawResult.saltPoints, greaterThanOrEqualTo(10));
    expect(result.nutritionQualityV2, inInclusiveRange(65, 69));
    expect(result.additiveQuality, closeTo(96.5, 0.0000001));
    expect(result.finalV2, inInclusiveRange(70, 74));
    expect(
      result.finalV2,
      lessThan(results['A strong balanced general food']!.finalV2),
    );
  });

  test('C and F genuinely multi-negative foods stay clearly weak', () {
    final multi = results['C multi-negative low-fiber food']!;
    final snack = results['F genuinely poor multi-negative snack']!;
    expect(multi.finalV2, lessThan(30));
    expect(snack.finalV2, lessThan(30));
    expect(multi.publicBandV2, 'Çok zayıf');
    expect(snack.publicBandV2, 'Çok zayıf');
  });

  test('D high sugar only is penalized without becoming very weak', () {
    final balanced = results['A strong balanced general food']!;
    final sugar = results['D high sugar only']!;
    expect(sugar.rawResult.sugarsPoints, greaterThanOrEqualTo(10));
    expect(sugar.finalV2, lessThan(balanced.finalV2));
    expect(sugar.finalV2.round(), greaterThanOrEqualTo(30));
  });

  test('E high saturated fat only is penalized without becoming very weak', () {
    final balanced = results['A strong balanced general food']!;
    final saturatedFat = results['E high saturated fat only']!;
    expect(saturatedFat.rawResult.saturatedFatPoints, greaterThanOrEqualTo(9));
    expect(saturatedFat.finalV2, lessThan(balanced.finalV2));
    expect(saturatedFat.finalV2.round(), greaterThanOrEqualTo(30));
  });

  test('G fiber and useful protein retain meaningful positive value', () {
    final positive = results['G high-fiber useful-protein profile']!;
    final without = results['G comparison without fiber and protein']!;
    expect(positive.rawResult.fiberPoints, greaterThan(0));
    expect(positive.rawResult.proteinPointsApplied, greaterThan(0));
    expect(positive.rawNutritionScore!, lessThan(without.rawNutritionScore!));
    expect(
      positive.nutritionQualityV2,
      greaterThan(without.nutritionQualityV2),
    );
  });

  test(
    'H beverage calibration preserves expected ordering and water maximum',
    () {
      final water = results['H plain water']!;
      final low = results['H low-negative beverage']!;
      final medium = results['H medium beverage']!;
      final poor = results['H poor sugary beverage']!;
      expect(water.nutritionQualityV2, 100);
      expect(low.nutritionQualityV2, greaterThan(medium.nutritionQualityV2));
      expect(medium.nutritionQualityV2, greaterThan(poor.nutritionQualityV2));
    },
  );

  test('I fats/oils/nuts/seeds calibration distinguishes profiles', () {
    final nuts = results['I unsalted nuts and seeds']!;
    final highSaturated = results['I high-saturated fat']!;
    expect(
      nuts.nutritionQualityV2,
      greaterThan(highSaturated.nutritionQualityV2),
    );
  });

  test('category-specific stress fixtures meet rollout acceptance bands', () {
    final legumes = results['K salty canned legumes']!;
    final redMeat = results['K processed salty red meat']!;
    final cheese = results['K hard cheese']!;
    final butter = results['K butter']!;
    final coconutOil = results['K coconut oil']!;
    final nuts = results['K plain nuts']!;
    final cola = results['K regular cola']!;

    expect(legumes.publicBandV2, isNot('Çok iyi'));
    expect(redMeat.finalV2, inInclusiveRange(55, 69));
    expect(redMeat.publicBandV2, 'Orta');
    expect(cheese.finalV2, inInclusiveRange(55, 69));
    expect(cheese.publicBandV2, 'Orta');
    expect(butter.finalV2, inInclusiveRange(50, 65));
    expect(butter.publicBandV2, 'Orta');
    expect(coconutOil.finalV2, inInclusiveRange(50, 65));
    expect(coconutOil.publicBandV2, 'Orta');
    expect(nuts.finalV2, greaterThanOrEqualTo(85));
    expect(cola.finalV2, inInclusiveRange(55, 60));
    expect(cola.publicBandV2, 'Orta');
  });

  test('named snack fixtures preserve sensible severity ordering', () {
    final chips = results['K chips']!;
    final biscuit = results['K chocolate biscuit']!;
    final poor = results['F genuinely poor multi-negative snack']!;

    expect(chips.finalV2, greaterThan(biscuit.finalV2));
    expect(biscuit.finalV2, greaterThan(poor.finalV2));
    expect(poor.finalV2, lessThan(30));
  });

  test('J package size is absent from score and fingerprint inputs', () {
    final input = results['B tarhana-like one major salt negative']!.input;
    final small = buildAuditSnapshot(
      product: auditProductFromInput(
        input,
        id: 'small-package',
        name: 'Calibration Product 150 G',
      ),
      assessment: auditOrdinaryAssessment(),
    );
    final large = buildAuditSnapshot(
      product: auditProductFromInput(
        input,
        id: 'large-package',
        name: 'Calibration Product 2 KG',
      ),
      assessment: auditOrdinaryAssessment(),
    );

    expect(small.finalScore, large.finalScore);
    expect(small.inputFingerprint, large.inputFingerprint);
  });

  test('high salt and good overall profile are both explained', () {
    final calibration = results['B tarhana-like one major salt negative']!;
    final nutrition = const NutritionQualityTransformer().transform(
      calibration.rawResult,
    );
    final score = const EtiketlyScoreCalculator().calculate(
      nutritionQuality: nutrition,
      additiveQuality: calibration.additiveResult,
      readiness: readyFinalReadiness(calibration.additiveResult),
    );
    final state = const EtiketlyScorePresentationMapper().fromResult(score);

    expect(state.qualityLabel, 'İyi');
    expect(state.nutritionSummary, contains('orta düzeydedir'));
    expect(
      state.nutritionAttentionPoints,
      contains(predicate<String>((value) => value.contains('Tuz'))),
    );
  });

  test('calibration report contains all required comparison fields', () {
    final report = formatScoreV2CalibrationReport(results.values);
    for (final field in const [
      'fixture',
      'category',
      'raw nutrition score',
      'nutritionQuality v1',
      'nutritionQuality v2',
      'additiveQuality',
      'final v1',
      'final v2',
      'public band v1',
      'public band v2',
    ]) {
      expect(report, contains(field));
    }
  });

  test(
    'historical v1 snapshot stays valid but cannot satisfy current (v3)',
    () {
      final current = buildAuditSnapshot(
        product: auditProductFromInput(
          results['A strong balanced general food']!.input,
        ),
        assessment: auditOrdinaryAssessment(),
      );
      final historical = _asHistoricalV1(current);
      const validator = EtiketlyScoreAuditValidator();
      const gate = EtiketlyPublicScoreAuditGate();

      expect(validator.validate(historical).isValid, isTrue);
      expect(current.scoreVersion, etiketlyScoreV2Version);
      expect(
        current.nutritionTransformVersion,
        nutritionQualityTransformVersion,
      );
      expect(
        gate.evaluate(current: current, trusted: historical).status,
        PublicScoreAuditStatus.stale,
      );
    },
  );
}

EtiketlyScoreAuditSnapshot _asHistoricalV1(EtiketlyScoreAuditSnapshot current) {
  final category = ScoringCategory.values.byName(
    current.nutritionResult.resolvedCategory,
  );
  final rawScore = current.nutritionResult.rawScore;
  final nutritionQuality = current.nutritionResult.isPlainWaterSpecialCase
      ? 100.0
      : const NutritionQualityTransformer.v1().qualityForRawScore(
          rawScore!.toDouble(),
          category,
        );
  final nutritionContribution =
      nutritionQuality * EtiketlyScoreCalculator.nutritionWeight;
  final additiveContribution =
      current.additiveResult.additiveQuality *
      EtiketlyScoreCalculator.additiveWeight;
  final snapshot = EtiketlyScoreAuditSnapshot(
    productId: current.productId,
    barcode: current.barcode,
    productUpdatedAt: current.productUpdatedAt,
    productVerificationStatus: current.productVerificationStatus,
    ingredientText: current.ingredientText,
    sourceEvidenceSchemaVersion: current.sourceEvidenceSchemaVersion,
    inputFingerprint: List.filled(64, '0').join(),
    scoreVersion: etiketlyScoreV1Version,
    nutritionMethodologyVersion: current.nutritionMethodologyVersion,
    nutritionTransformVersion: nutritionQualityTransformV1Version,
    additiveTransformVersion: current.additiveTransformVersion,
    resolvedInput: current.resolvedInput,
    canonicalAdditives: current.canonicalAdditives,
    nutritionResult: ScoreAuditNutritionResultSnapshot(
      resolvedCategory: current.nutritionResult.resolvedCategory,
      rawScore: current.nutritionResult.rawScore,
      negativePoints: current.nutritionResult.negativePoints,
      positivePoints: current.nutritionResult.positivePoints,
      specialRules: current.nutritionResult.specialRules,
      isPlainWaterSpecialCase: current.nutritionResult.isPlainWaterSpecialCase,
      nutritionQuality: nutritionQuality,
    ),
    additiveResult: current.additiveResult,
    nutritionContribution: nutritionContribution,
    additiveContribution: additiveContribution,
    finalScore: nutritionContribution + additiveContribution,
  );
  return snapshot.withInputFingerprint(
    ScoreAuditFingerprint.create(snapshot.fingerprintPayload()),
  );
}
