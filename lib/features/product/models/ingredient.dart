import 'package:food_analyzer_app/features/product/models/ingredient_risk_reference.dart';

class Ingredient {
  final String id;
  final String name;
  final String normalizedName;
  final List<String>? alternativeNames;
  final List<String>? aliases;
  final List<String>? commonNames;
  final List<String>? englishNames;
  final String? eCode;
  final String? category;
  final String riskLevel; // low, medium, high, unknown
  final String? shortDescription;
  final String? longDescription;
  final String? additiveGroup;
  final String? childWarning;
  final List<String>? sourceReferences;
  final List<IngredientRiskReference>? sourceReferenceEntries;
  final String? sourceUrl;
  // New educational metadata fields
  final String?
  ingredientType; // e.g., "Rafine bitkisel yağ", "Koruyucu katkı maddesi"
  final String? shortPurpose; // why it's used (1-2 sentences)
  final String? shortRiskSummary; // why it may be concerning (1-2 sentences)
  final List<String>?
  cautionGroups; // groups of people to be careful, e.g. ["çocuklar"]
  final String? processingRole; // e.g., "Ultra işlenmiş ürünlerde yaygın"
  final DateTime createdAt;
  final DateTime updatedAt;

  Ingredient({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.alternativeNames,
    this.aliases,
    this.commonNames,
    this.englishNames,
    this.eCode,
    this.category,
    required this.riskLevel,
    this.shortDescription,
    this.longDescription,
    this.additiveGroup,
    this.childWarning,
    this.sourceReferences,
    this.sourceReferenceEntries,
    this.sourceUrl,
    this.ingredientType,
    this.shortPurpose,
    this.shortRiskSummary,
    this.cautionGroups,
    this.processingRole,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create Ingredient from Supabase JSON
  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      id: json['id'] as String,
      name: json['name'] as String,
      normalizedName: json['normalized_name'] as String,
      alternativeNames: _parseStringArray(json['alternative_names']),
      aliases: _parseStringArray(json['aliases']),
      commonNames: _parseStringArray(json['common_names']),
      englishNames: _parseStringArray(json['english_names']),
      eCode: json['e_code'] as String?,
      category: json['category'] as String?,
      riskLevel: json['risk_level'] as String? ?? 'unknown',
      shortDescription: json['short_description'] as String?,
      longDescription: json['long_description'] as String?,
      additiveGroup: json['additive_group'] as String?,
      childWarning: json['child_warning'] as String?,
      sourceReferences: _parseStringArray(json['source_references']),
      sourceReferenceEntries: _parseReferenceArray(
        json['source_reference_entries'],
      ),
      sourceUrl: json['source_url'] as String?,
      ingredientType: json['ingredient_type'] as String?,
      shortPurpose: json['short_purpose'] as String?,
      shortRiskSummary: json['short_risk_summary'] as String?,
      cautionGroups: _parseStringArray(json['caution_groups']),
      processingRole: json['processing_role'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert Ingredient to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'normalized_name': normalizedName,
      'alternative_names': alternativeNames,
      'aliases': aliases,
      'common_names': commonNames,
      'english_names': englishNames,
      'e_code': eCode,
      'category': category,
      'risk_level': riskLevel,
      'short_description': shortDescription,
      'long_description': longDescription,
      'additive_group': additiveGroup,
      'child_warning': childWarning,
      'source_references': sourceReferences,
      'source_reference_entries': sourceReferenceEntries
          ?.map((entry) => entry.toJson())
          .toList(growable: false),
      'source_url': sourceUrl,
      'ingredient_type': ingredientType,
      'short_purpose': shortPurpose,
      'short_risk_summary': shortRiskSummary,
      'caution_groups': cautionGroups,
      'processing_role': processingRole,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Get user-friendly risk level label in Turkish
  String getRiskLevelTurkish() {
    switch (riskLevel) {
      case 'low':
        return 'Düşük düzey';
      case 'medium':
        return 'Orta düzey';
      case 'high':
        return 'Yüksek düzey';
      case 'unknown':
        return 'Bilinmiyor';
      default:
        return riskLevel;
    }
  }

  @override
  String toString() => 'Ingredient(id=$id, name=$name, eCode=$eCode)';
}

/// Helper to parse PostgreSQL text arrays
List<String>? _parseStringArray(dynamic value) {
  if (value == null) return null;
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return null;
}

List<IngredientRiskReference>? _parseReferenceArray(dynamic value) {
  if (value == null || value is! List) return null;
  final items = value
      .whereType<Map>()
      .map(
        (item) =>
            IngredientRiskReference.fromJson(Map<String, dynamic>.from(item)),
      )
      .toList(growable: false);
  return items.isEmpty ? null : items;
}
