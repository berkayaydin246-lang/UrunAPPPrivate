import 'dart:convert';

import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

class Product {
  final String id;
  final String? barcode;
  final String name;
  final String? normalizedName;
  final String? brand;
  final String? categoryId;
  final String? imageUrl;
  final String? ingredientsText;
  final String? nutritionText;
  final String? source;
  final String? sourceUrl;
  final String
  verificationStatus; // verified, pending, imported, user_submitted, rejected
  final List<String>? searchKeywords;
  final List<String>? categoryTags;
  final String? canonicalCategory;
  final String? canonicalSubcategory;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product({
    required this.id,
    this.barcode,
    required this.name,
    this.normalizedName,
    this.brand,
    this.categoryId,
    this.imageUrl,
    this.ingredientsText,
    this.nutritionText,
    this.source,
    this.sourceUrl,
    required this.verificationStatus,
    this.searchKeywords,
    this.categoryTags,
    this.canonicalCategory,
    this.canonicalSubcategory,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create Product from Supabase JSON response
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      barcode: json['barcode'] as String?,
      name: json['name'] as String,
      normalizedName: json['normalized_name'] as String?,
      brand: json['brand'] as String?,
      categoryId: json['category_id'] as String?,
      imageUrl: json['image_url'] as String?,
      ingredientsText: json['ingredients_text'] as String?,
      nutritionText: json['nutrition_text'] as String?,
      source: json['source'] as String?,
      sourceUrl: json['source_url'] as String?,
      verificationStatus: json['verification_status'] as String? ?? 'pending',
      searchKeywords: (json['search_keywords'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      categoryTags: (json['category_tags'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      canonicalCategory: json['canonical_category'] as String?,
      canonicalSubcategory: json['canonical_subcategory'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert Product to JSON for Supabase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'barcode': barcode,
      'name': name,
      'normalized_name': normalizedName,
      'brand': brand,
      'category_id': categoryId,
      'image_url': imageUrl,
      'ingredients_text': ingredientsText,
      'nutrition_text': nutritionText,
      'source': source,
      'source_url': sourceUrl,
      'verification_status': verificationStatus,
      if (searchKeywords != null) 'search_keywords': searchKeywords,
      if (categoryTags != null) 'category_tags': categoryTags,
      if (canonicalCategory != null) 'canonical_category': canonicalCategory,
      if (canonicalSubcategory != null)
        'canonical_subcategory': canonicalSubcategory,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  NutritionData? get nutrition {
    if (nutritionText == null) return null;
    try {
      final decoded = jsonDecode(nutritionText!);
      if (decoded is! Map<String, dynamic>) return null;
      return NutritionData.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  // ── data-completeness helpers ─────────────────────────────────────────────

  bool get hasIngredients =>
      ingredientsText != null && ingredientsText!.trim().length > 10;

  // Uses the parsed NutritionData instead of a string-length proxy so that
  // an empty JSON object ("{}") doesn't show "Besin ✓".
  bool get hasNutrition => nutrition?.hasAnyData == true;

  bool get hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  String toString() => 'Product(id=$id, name=$name, brand=$brand)';
}
