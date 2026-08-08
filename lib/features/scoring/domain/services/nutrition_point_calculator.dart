class NutritionPointCalculator {
  const NutritionPointCalculator();

  static const _generalEnergyUpperBounds = <double>[
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
  ];
  static const _saturatedFatUpperBounds = <double>[
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
  ];
  static const _generalSugarUpperBounds = <double>[
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
  ];
  static const _saltUpperBounds = <double>[
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
  ];
  static const _generalProteinUpperBounds = <double>[
    2.4,
    4.8,
    7.2,
    9.6,
    12,
    14,
    17,
  ];
  static const _fiberUpperBounds = <double>[3, 4.1, 5.2, 6.3, 7.4];
  static const _fatSaturatedEnergyUpperBounds = <double>[
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
  ];
  static const _fatRatioLowerBounds = <double>[
    10,
    16,
    22,
    28,
    34,
    40,
    46,
    52,
    58,
    64,
  ];
  static const _beverageEnergyUpperBounds = <double>[
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
  ];
  static const _beverageSugarUpperBounds = <double>[
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
  ];
  static const _beverageProteinUpperBounds = <double>[
    1.2,
    1.5,
    1.8,
    2.1,
    2.4,
    2.7,
    3,
  ];

  int generalEnergyPoints(double energyKj) =>
      _upperBandPoints(energyKj, _generalEnergyUpperBounds, 'energyKj');

  int saturatedFatPoints(double saturatedFat) =>
      _upperBandPoints(saturatedFat, _saturatedFatUpperBounds, 'saturatedFat');

  int generalSugarPoints(double sugars) =>
      _upperBandPoints(sugars, _generalSugarUpperBounds, 'sugars');

  int saltPoints(double salt) =>
      _upperBandPoints(salt, _saltUpperBounds, 'salt');

  int generalProteinPoints(double protein) =>
      _upperBandPoints(protein, _generalProteinUpperBounds, 'protein');

  int fiberPoints(double fiber) =>
      _upperBandPoints(fiber, _fiberUpperBounds, 'fiber');

  int generalFvlPoints(double percentage) {
    _requirePercentage(percentage, 'fvlPercentage');
    if (percentage <= 40) return 0;
    if (percentage <= 60) return 1;
    if (percentage <= 80) return 2;
    return 5;
  }

  int fatSaturatedEnergyPoints(double energyKj) => _upperBandPoints(
    energyKj,
    _fatSaturatedEnergyUpperBounds,
    'saturatedEnergyKj',
  );

  int fatSaturatedRatioPoints(double ratioPercent) {
    _requirePercentage(ratioPercent, 'saturatedFatRatioPercent');
    var points = 0;
    for (final lowerBound in _fatRatioLowerBounds) {
      if (ratioPercent < lowerBound) break;
      points += 1;
    }
    return points;
  }

  int beverageEnergyPoints(double energyKj) =>
      _upperBandPoints(energyKj, _beverageEnergyUpperBounds, 'energyKj');

  int beverageSugarPoints(double sugars) =>
      _upperBandPoints(sugars, _beverageSugarUpperBounds, 'sugars');

  int beverageProteinPoints(double protein) =>
      _upperBandPoints(protein, _beverageProteinUpperBounds, 'protein');

  int beverageFvlPoints(double percentage) {
    _requirePercentage(percentage, 'fvlPercentage');
    if (percentage <= 40) return 0;
    if (percentage <= 60) return 2;
    if (percentage <= 80) return 4;
    return 6;
  }

  int beverageNnsPoints(bool present) => present ? 4 : 0;

  int _upperBandPoints(double value, List<double> upperBounds, String name) {
    _requireNonNegativeFinite(value, name);
    for (var index = 0; index < upperBounds.length; index += 1) {
      if (value <= upperBounds[index]) return index;
    }
    return upperBounds.length;
  }

  void _requirePercentage(double value, String name) {
    _requireNonNegativeFinite(value, name);
    if (value > 100) {
      throw ArgumentError.value(value, name, 'must be at most 100');
    }
  }

  void _requireNonNegativeFinite(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(value, name, 'must be finite and non-negative');
    }
  }
}
