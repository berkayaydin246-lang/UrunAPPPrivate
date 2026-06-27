import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/comparison/domain/comparison_metric.dart';
import 'package:food_analyzer_app/features/comparison/domain/product_comparison.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';

void main() {
  group('comparison metric evaluation', () {
    test('lower sugar prefers the lower value', () {
      final metric = buildNumericComparisonMetric(
        key: 'sugars',
        label: 'Şeker',
        productAValue: 4.2,
        productBValue: 12.5,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.lowerIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.productAIsBetter);
      expect(metric.productABadgeLabel, 'Daha düşük');
    });

    test('lower salt prefers the lower value', () {
      final metric = buildNumericComparisonMetric(
        key: 'salt',
        label: 'Tuz',
        productAValue: 1.1,
        productBValue: 0.3,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.lowerIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.productBIsBetter);
      expect(metric.productBBadgeLabel, 'Daha düşük');
    });

    test('lower saturated fat prefers the lower value', () {
      final metric = buildNumericComparisonMetric(
        key: 'saturated_fat',
        label: 'Doymuş yağ',
        productAValue: 5,
        productBValue: 2,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.lowerIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.productBIsBetter);
    });

    test('higher protein prefers the higher value', () {
      final metric = buildNumericComparisonMetric(
        key: 'proteins',
        label: 'Protein',
        productAValue: 8,
        productBValue: 5,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.higherIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.productAIsBetter);
      expect(metric.productABadgeLabel, 'Daha yüksek');
    });

    test('higher fiber prefers the higher value', () {
      final metric = buildNumericComparisonMetric(
        key: 'fiber',
        label: 'Lif',
        productAValue: 4,
        productBValue: 7,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.higherIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.productBIsBetter);
    });

    test('neutral metrics do not declare a better product', () {
      final metric = buildNumericComparisonMetric(
        key: 'energy',
        label: 'Enerji',
        productAValue: 180,
        productBValue: 220,
        displayUnit: 'kcal',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.neutral,
      );

      expect(metric.outcome, ComparisonOutcome.neutral);
      expect(metric.centralStatusLabel, isEmpty);
      expect(metric.productABadgeLabel, isEmpty);
      expect(metric.productBBadgeLabel, isEmpty);
    });

    test('equal values produce equal', () {
      final metric = buildNumericComparisonMetric(
        key: 'protein',
        label: 'Protein',
        productAValue: 5,
        productBValue: 5,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.higherIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.equal);
      expect(metric.centralStatusLabel, 'Eşit');
    });

    test('null vs value produces missingData', () {
      final metric = buildNumericComparisonMetric(
        key: 'sugar',
        label: 'Şeker',
        productAValue: null,
        productBValue: 4,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.lowerIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.missingData);
      expect(metric.reason, kComparisonMissingDataReason);
    });

    test('null vs null produces missingData', () {
      final metric = buildNumericComparisonMetric(
        key: 'fiber',
        label: 'Lif',
        productAValue: null,
        productBValue: null,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.higherIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.missingData);
    });

    test('per 100 g vs per 100 ml is not comparable', () {
      final metric = buildNumericComparisonMetric(
        key: 'salt',
        label: 'Tuz',
        productAValue: 0.3,
        productBValue: 0.2,
        displayUnit: 'g',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100ml,
        preference: ComparisonPreference.lowerIsBetter,
      );

      expect(metric.outcome, ComparisonOutcome.notComparable);
      expect(metric.centralStatusLabel, 'Farklı ölçüm temeli');
      expect(metric.reason, kComparisonIncompatibleBasisReason);
    });

    test('per 100 g vs per 100 g is comparable', () {
      expect(
        areNutritionBasesComparable(
          NutritionBasis.per100g,
          NutritionBasis.per100g,
        ),
        isTrue,
      );
    });

    test('rounding tolerance avoids false differences', () {
      final metric = buildNumericComparisonMetric(
        key: 'energy',
        label: 'Enerji',
        productAValue: 100.0,
        productBValue: 100.04,
        displayUnit: 'kcal',
        basisA: NutritionBasis.per100g,
        basisB: NutritionBasis.per100g,
        preference: ComparisonPreference.neutral,
      );

      expect(metric.outcome, ComparisonOutcome.equal);
    });
  });

  group('nutrition basis inference', () {
    test('infers per100ml for beverages with liquid units', () {
      final product = _product(
        id: 'cola',
        name: 'Zero Cola 1 L',
        categoryTags: const ['icecekler', 'gazli_icecek'],
        nutrition: const {'sugars': 0},
      );

      expect(inferNutritionBasis(product), NutritionBasis.per100ml);
    });

    test('infers per100g for solids with gram units', () {
      final product = _product(
        id: 'chips',
        name: 'Patates Cipsi 150 G',
        categoryTags: const ['cips', 'atistirmalik'],
        nutrition: const {'sugars': 1.2},
      );

      expect(inferNutritionBasis(product), NutritionBasis.per100g);
    });
  });
}

Product _product({
  required String id,
  required String name,
  List<String>? categoryTags,
  Map<String, dynamic>? nutrition,
}) {
  final now = DateTime.utc(2026, 6, 26, 12);
  return Product(
    id: id,
    name: name,
    nutritionText: nutrition == null ? null : jsonEncode(nutrition),
    verificationStatus: 'verified',
    categoryTags: categoryTags,
    createdAt: now,
    updatedAt: now,
  );
}
