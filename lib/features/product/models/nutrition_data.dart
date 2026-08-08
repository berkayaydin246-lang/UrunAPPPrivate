class NutritionData {
  final double? energyKj;
  final double? energyKcal;
  final double? fat;
  final double? saturatedFat;
  final double? carbohydrates;
  final double? sugars;
  final double? fiber;
  final double? proteins;
  final double? salt;
  final double? sodium;
  final String? servingSize;

  const NutritionData({
    this.energyKj,
    this.energyKcal,
    this.fat,
    this.saturatedFat,
    this.carbohydrates,
    this.sugars,
    this.fiber,
    this.proteins,
    this.salt,
    this.sodium,
    this.servingSize,
  });

  bool get hasAnyData =>
      energyKj != null ||
      energyKcal != null ||
      fat != null ||
      saturatedFat != null ||
      carbohydrates != null ||
      sugars != null ||
      fiber != null ||
      proteins != null ||
      salt != null ||
      sodium != null;

  factory NutritionData.fromMap(Map<String, dynamic> map) {
    return NutritionData(
      energyKj: _toDouble(map['energy_kj']),
      energyKcal: _toDouble(map['energy_kcal']),
      fat: _toDouble(map['fat']),
      saturatedFat: _toDouble(map['saturated_fat']),
      carbohydrates: _toDouble(map['carbohydrates']),
      sugars: _toDouble(map['sugars']),
      fiber: _toDouble(map['fiber']),
      proteins: _toDouble(map['proteins']),
      salt: _toDouble(map['salt']),
      sodium: _toDouble(map['sodium']),
      servingSize: _cleanText(map['serving_size']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (energyKj != null) 'energy_kj': energyKj,
      if (energyKcal != null) 'energy_kcal': energyKcal,
      if (fat != null) 'fat': fat,
      if (saturatedFat != null) 'saturated_fat': saturatedFat,
      if (carbohydrates != null) 'carbohydrates': carbohydrates,
      if (sugars != null) 'sugars': sugars,
      if (fiber != null) 'fiber': fiber,
      if (proteins != null) 'proteins': proteins,
      if (salt != null) 'salt': salt,
      if (sodium != null) 'sodium': sodium,
      if (servingSize != null) 'serving_size': servingSize,
    };
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    final parsed = switch (value) {
      num number => number.toDouble(),
      String text => double.tryParse(text.trim().replaceAll(',', '.')),
      _ => null,
    };
    if (parsed == null || !parsed.isFinite || parsed < 0) return null;
    return parsed;
  }

  static String? _cleanText(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
  }
}

/// Returns the app's canonical nutrition map or null when no numeric nutrient
/// is available. Invalid, non-finite, negative, and unit-bearing values are
/// discarded rather than reaching product storage or UI.
Map<String, dynamic>? normalizeNutritionMap(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final nutrition = NutritionData.fromMap(raw);
  return nutrition.hasAnyData ? nutrition.toMap() : null;
}
