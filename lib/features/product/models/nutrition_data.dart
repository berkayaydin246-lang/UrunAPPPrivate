class NutritionData {
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
      energyKcal: _toDouble(map['energy_kcal']),
      fat: _toDouble(map['fat']),
      saturatedFat: _toDouble(map['saturated_fat']),
      carbohydrates: _toDouble(map['carbohydrates']),
      sugars: _toDouble(map['sugars']),
      fiber: _toDouble(map['fiber']),
      proteins: _toDouble(map['proteins']),
      salt: _toDouble(map['salt']),
      sodium: _toDouble(map['sodium']),
      servingSize: map['serving_size'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
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
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
