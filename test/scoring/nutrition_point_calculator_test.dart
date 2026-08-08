import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_point_calculator.dart';

void main() {
  const calculator = NutritionPointCalculator();
  const delta = 0.0001;

  void testUpperBoundTable(
    String name,
    List<double> thresholds,
    int Function(double) calculate,
  ) {
    test('$name tests every threshold below, exact, and above', () {
      for (var index = 0; index < thresholds.length; index += 1) {
        final threshold = thresholds[index];
        expect(
          calculate(threshold - delta),
          index,
          reason: '$name just below $threshold',
        );
        expect(calculate(threshold), index, reason: '$name exactly $threshold');
        expect(
          calculate(threshold + delta),
          index + 1,
          reason: '$name just above $threshold',
        );
      }
    });
  }

  testUpperBoundTable('general energy', const [
    335,
    670,
    1005,
    1340,
    1675,
    2010,
    2345,
    2680,
    3015,
    3350,
  ], calculator.generalEnergyPoints);

  testUpperBoundTable('general saturated fat', const [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
  ], calculator.saturatedFatPoints);

  testUpperBoundTable('general sugars', const [
    3.4,
    6.8,
    10,
    14,
    17,
    20,
    24,
    27,
    31,
    34,
    37,
    41,
    44,
    48,
    51,
  ], calculator.generalSugarPoints);

  testUpperBoundTable('general and beverage salt', const [
    0.2,
    0.4,
    0.6,
    0.8,
    1,
    1.2,
    1.4,
    1.6,
    1.8,
    2,
    2.2,
    2.4,
    2.6,
    2.8,
    3,
    3.2,
    3.4,
    3.6,
    3.8,
    4,
  ], calculator.saltPoints);

  testUpperBoundTable('general protein', const [
    2.4,
    4.8,
    7.2,
    9.6,
    12,
    14,
    17,
  ], calculator.generalProteinPoints);

  testUpperBoundTable('general and beverage fiber', const [
    3,
    4.1,
    5.2,
    6.3,
    7.4,
  ], calculator.fiberPoints);

  test('general FVL tests every threshold below, exact, and above', () {
    const cases = [
      (threshold: 40.0, below: 0, exact: 0, above: 1),
      (threshold: 60.0, below: 1, exact: 1, above: 2),
      (threshold: 80.0, below: 2, exact: 2, above: 5),
    ];
    for (final value in cases) {
      expect(calculator.generalFvlPoints(value.threshold - delta), value.below);
      expect(calculator.generalFvlPoints(value.threshold), value.exact);
      expect(calculator.generalFvlPoints(value.threshold + delta), value.above);
    }
  });

  testUpperBoundTable('fat saturated energy', const [
    120,
    240,
    360,
    480,
    600,
    720,
    840,
    960,
    1080,
    1200,
  ], calculator.fatSaturatedEnergyPoints);

  test('fat ratio tests every threshold below, exact, and above', () {
    const thresholds = <double>[10, 16, 22, 28, 34, 40, 46, 52, 58, 64];
    for (var index = 0; index < thresholds.length; index += 1) {
      final threshold = thresholds[index];
      expect(calculator.fatSaturatedRatioPoints(threshold - delta), index);
      expect(calculator.fatSaturatedRatioPoints(threshold), index + 1);
      expect(calculator.fatSaturatedRatioPoints(threshold + delta), index + 1);
    }
  });

  testUpperBoundTable('beverage energy', const [
    30,
    90,
    150,
    210,
    240,
    270,
    300,
    330,
    360,
    390,
  ], calculator.beverageEnergyPoints);

  testUpperBoundTable('beverage sugars', const [
    0.5,
    2,
    3.5,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
  ], calculator.beverageSugarPoints);

  testUpperBoundTable('beverage protein', const [
    1.2,
    1.5,
    1.8,
    2.1,
    2.4,
    2.7,
    3,
  ], calculator.beverageProteinPoints);

  test('beverage FVL tests every threshold below, exact, and above', () {
    const cases = [
      (threshold: 40.0, below: 0, exact: 0, above: 2),
      (threshold: 60.0, below: 2, exact: 2, above: 4),
      (threshold: 80.0, below: 4, exact: 4, above: 6),
    ];
    for (final value in cases) {
      expect(
        calculator.beverageFvlPoints(value.threshold - delta),
        value.below,
      );
      expect(calculator.beverageFvlPoints(value.threshold), value.exact);
      expect(
        calculator.beverageFvlPoints(value.threshold + delta),
        value.above,
      );
    }
  });

  test('point functions reject invalid numeric values instead of clamping', () {
    for (final invalid in [double.nan, double.infinity, -0.1]) {
      expect(
        () => calculator.generalEnergyPoints(invalid),
        throwsArgumentError,
      );
    }
    expect(() => calculator.generalFvlPoints(100.1), throwsArgumentError);
    expect(
      () => calculator.fatSaturatedRatioPoints(100.1),
      throwsArgumentError,
    );
  });
}
