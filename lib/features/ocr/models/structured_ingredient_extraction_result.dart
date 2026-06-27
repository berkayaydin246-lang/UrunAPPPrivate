class StructuredIngredientItem {
  final String name;
  final String originalText;
  final String? eCode;
  final double confidence;

  const StructuredIngredientItem({
    required this.name,
    required this.originalText,
    this.eCode,
    required this.confidence,
  });

  bool get isConfirmed =>
      confidence >=
      StructuredIngredientExtractionResult.confirmedConfidenceThreshold;

  factory StructuredIngredientItem.fromJson(Map<String, dynamic> json) {
    return StructuredIngredientItem(
      name: (json['name'] ?? '').toString().trim(),
      originalText:
          (json['original_text'] ?? json['originalText'] ?? json['name'] ?? '')
              .toString()
              .trim(),
      eCode: (json['e_code'] ?? json['eCode'])?.toString().trim(),
      confidence: ((json['confidence'] as num?)?.toDouble() ?? 0.0).clamp(
        0.0,
        1.0,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'original_text': originalText,
      'e_code': eCode,
      'confidence': confidence,
    };
  }
}

class StructuredIngredientExtractionResult {
  static const double confirmedConfidenceThreshold = 0.85;

  final String rawText;
  final String cleanedText;
  final List<StructuredIngredientItem> ingredients;
  final List<String> eCodes;
  final List<String> uncertainItems;
  final List<String> warnings;
  final double qualityScore;

  const StructuredIngredientExtractionResult({
    required this.rawText,
    required this.cleanedText,
    required this.ingredients,
    required this.eCodes,
    required this.uncertainItems,
    required this.warnings,
    required this.qualityScore,
  });

  factory StructuredIngredientExtractionResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return StructuredIngredientExtractionResult(
      rawText: (json['raw_text'] ?? json['rawText'] ?? '').toString().trim(),
      cleanedText:
          (json['cleaned_text'] ??
                  json['cleanedText'] ??
                  json['raw_text'] ??
                  '')
              .toString()
              .trim(),
      ingredients: _parseIngredientItems(json['ingredients']),
      eCodes: _parseStringList(json['e_codes'] ?? json['eCodes']),
      uncertainItems: _parseStringList(
        json['uncertain_items'] ?? json['uncertainItems'],
      ),
      warnings: _parseStringList(json['warnings']),
      qualityScore:
          ((json['quality_score'] ?? json['qualityScore'] ?? 0) as num?)
              ?.toDouble()
              .clamp(0.0, 1.0) ??
          0.0,
    );
  }

  List<StructuredIngredientItem> get confirmedIngredients =>
      ingredients.where((item) => item.isConfirmed).toList(growable: false);

  String get confirmedIngredientsText {
    final confirmed = confirmedIngredients;
    if (confirmed.isEmpty) return '';
    return confirmed
        .map(
          (item) =>
              item.originalText.isNotEmpty ? item.originalText : item.name,
        )
        .join(', ');
  }

  bool get hasConfirmedIngredients => confirmedIngredients.isNotEmpty;

  List<String> get confirmedIngredientNames => confirmedIngredients
      .map((item) => item.name)
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);

  Map<String, dynamic> toJson() {
    return {
      'raw_text': rawText,
      'cleaned_text': cleanedText,
      'ingredients': ingredients.map((item) => item.toJson()).toList(),
      'e_codes': eCodes,
      'uncertain_items': uncertainItems,
      'warnings': warnings,
      'quality_score': qualityScore,
    };
  }

  static List<StructuredIngredientItem> _parseIngredientItems(dynamic value) {
    if (value is! List) return const <StructuredIngredientItem>[];
    return value
        .whereType<Map>()
        .map(
          (item) => StructuredIngredientItem.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList(growable: false);
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
