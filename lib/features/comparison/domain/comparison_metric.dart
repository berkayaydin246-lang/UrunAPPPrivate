import 'dart:math' as math;

enum ComparisonPreference { lowerIsBetter, higherIsBetter, neutral }

enum ComparisonOutcome {
  productAIsBetter,
  productBIsBetter,
  equal,
  notComparable,
  missingData,
  neutral,
}

enum NutritionBasis {
  per100Generic,
  per100g,
  per100ml,
  perServing,
  perPackage,
  unknown,
}

extension NutritionBasisX on NutritionBasis {
  String get label {
    switch (this) {
      case NutritionBasis.per100Generic:
        return '100 g/ml başına';
      case NutritionBasis.per100g:
        return '100 g başına';
      case NutritionBasis.per100ml:
        return '100 ml başına';
      case NutritionBasis.perServing:
        return 'Porsiyon başına';
      case NutritionBasis.perPackage:
        return 'Paket başına';
      case NutritionBasis.unknown:
        return 'Ölçüm temeli bilinmiyor';
    }
  }
}

class ComparisonMetric {
  const ComparisonMetric({
    required this.key,
    required this.label,
    required this.productAValue,
    required this.productBValue,
    required this.displayUnit,
    required this.basisA,
    required this.basisB,
    required this.preference,
    required this.outcome,
    required this.isComparable,
    this.reason,
  });

  final String key;
  final String label;
  final double? productAValue;
  final double? productBValue;
  final String displayUnit;
  final NutritionBasis basisA;
  final NutritionBasis basisB;
  final ComparisonPreference preference;
  final ComparisonOutcome outcome;
  final bool isComparable;
  final String? reason;

  bool get highlightsProductA =>
      outcome == ComparisonOutcome.productAIsBetter &&
      preference != ComparisonPreference.neutral;

  bool get highlightsProductB =>
      outcome == ComparisonOutcome.productBIsBetter &&
      preference != ComparisonPreference.neutral;

  String get centralStatusLabel {
    switch (outcome) {
      case ComparisonOutcome.equal:
        return 'Eşit';
      case ComparisonOutcome.notComparable:
        return reason == kComparisonUnknownBasisReason
            ? 'Karşılaştırılamıyor'
            : 'Farklı ölçüm temeli';
      case ComparisonOutcome.missingData:
        return 'Bilgi yok';
      case ComparisonOutcome.neutral:
        return '';
      case ComparisonOutcome.productAIsBetter:
      case ComparisonOutcome.productBIsBetter:
        return '';
    }
  }

  String get productABadgeLabel {
    if (outcome != ComparisonOutcome.productAIsBetter) return '';
    return switch (preference) {
      ComparisonPreference.lowerIsBetter => 'Daha düşük',
      ComparisonPreference.higherIsBetter => 'Daha yüksek',
      ComparisonPreference.neutral => '',
    };
  }

  String get productBBadgeLabel {
    if (outcome != ComparisonOutcome.productBIsBetter) return '';
    return switch (preference) {
      ComparisonPreference.lowerIsBetter => 'Daha düşük',
      ComparisonPreference.higherIsBetter => 'Daha yüksek',
      ComparisonPreference.neutral => '',
    };
  }
}

const kComparisonMissingDataReason = 'Bu değer için bilgi yok.';
const kComparisonIncompatibleBasisReason =
    'Bu değerler farklı ölçüm temellerinde olduğu için doğrudan karşılaştırılamaz.';
const kComparisonUnknownBasisReason =
    'Bu değerlerin ölçüm temeli doğrulanamadığı için doğrudan karşılaştırılamaz.';

ComparisonMetric buildNumericComparisonMetric({
  required String key,
  required String label,
  required double? productAValue,
  required double? productBValue,
  required String displayUnit,
  required NutritionBasis basisA,
  required NutritionBasis basisB,
  required ComparisonPreference preference,
  double equalityTolerance = 0.05,
}) {
  if (productAValue == null || productBValue == null) {
    return ComparisonMetric(
      key: key,
      label: label,
      productAValue: productAValue,
      productBValue: productBValue,
      displayUnit: displayUnit,
      basisA: basisA,
      basisB: basisB,
      preference: preference,
      outcome: ComparisonOutcome.missingData,
      isComparable: false,
      reason: kComparisonMissingDataReason,
    );
  }

  if (basisA == NutritionBasis.unknown ||
      basisB == NutritionBasis.unknown ||
      basisA == NutritionBasis.per100Generic ||
      basisB == NutritionBasis.per100Generic) {
    return ComparisonMetric(
      key: key,
      label: label,
      productAValue: productAValue,
      productBValue: productBValue,
      displayUnit: displayUnit,
      basisA: basisA,
      basisB: basisB,
      preference: preference,
      outcome: ComparisonOutcome.notComparable,
      isComparable: false,
      reason: kComparisonUnknownBasisReason,
    );
  }

  if (!areNutritionBasesComparable(basisA, basisB)) {
    return ComparisonMetric(
      key: key,
      label: label,
      productAValue: productAValue,
      productBValue: productBValue,
      displayUnit: displayUnit,
      basisA: basisA,
      basisB: basisB,
      preference: preference,
      outcome: ComparisonOutcome.notComparable,
      isComparable: false,
      reason: kComparisonIncompatibleBasisReason,
    );
  }

  if (areNearlyEqual(
    productAValue,
    productBValue,
    tolerance: equalityTolerance,
  )) {
    return ComparisonMetric(
      key: key,
      label: label,
      productAValue: productAValue,
      productBValue: productBValue,
      displayUnit: displayUnit,
      basisA: basisA,
      basisB: basisB,
      preference: preference,
      outcome: ComparisonOutcome.equal,
      isComparable: true,
    );
  }

  final outcome = switch (preference) {
    ComparisonPreference.lowerIsBetter =>
      productAValue < productBValue
          ? ComparisonOutcome.productAIsBetter
          : ComparisonOutcome.productBIsBetter,
    ComparisonPreference.higherIsBetter =>
      productAValue > productBValue
          ? ComparisonOutcome.productAIsBetter
          : ComparisonOutcome.productBIsBetter,
    ComparisonPreference.neutral => ComparisonOutcome.neutral,
  };

  return ComparisonMetric(
    key: key,
    label: label,
    productAValue: productAValue,
    productBValue: productBValue,
    displayUnit: displayUnit,
    basisA: basisA,
    basisB: basisB,
    preference: preference,
    outcome: outcome,
    isComparable: true,
  );
}

bool areNutritionBasesComparable(NutritionBasis basisA, NutritionBasis basisB) {
  if (basisA == NutritionBasis.unknown ||
      basisB == NutritionBasis.unknown ||
      basisA == NutritionBasis.per100Generic ||
      basisB == NutritionBasis.per100Generic) {
    return false;
  }

  return basisA == basisB;
}

bool areNearlyEqual(double valueA, double valueB, {double tolerance = 0.05}) {
  final difference = (valueA - valueB).abs();
  final relativeTolerance = math.max(valueA.abs(), valueB.abs()) * 0.01;
  return difference <= math.max(tolerance, relativeTolerance);
}
