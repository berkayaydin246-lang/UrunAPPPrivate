import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

class ProductSubmission {
  final String id;
  final String barcode;
  final String? productName;
  final String? brand;
  final String? imageUrl;
  final String? frontImageUrl;
  final String? labelImageUrl;
  final String? nutritionImageUrl;
  final String? extractedIngredientsText;
  final Map<String, dynamic>? extractedNutrition;
  final String extractionStatus;
  final String? extractionError;
  final String? notes;
  final String? submittedBy;
  final String status;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductSubmission({
    required this.id,
    required this.barcode,
    this.productName,
    this.brand,
    this.imageUrl,
    this.frontImageUrl,
    this.labelImageUrl,
    this.nutritionImageUrl,
    this.extractedIngredientsText,
    this.extractedNutrition,
    this.extractionStatus = 'not_started',
    this.extractionError,
    this.notes,
    this.submittedBy,
    required this.status,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductSubmission.fromJson(Map<String, dynamic> json) {
    return ProductSubmission(
      id: json['id'] as String,
      barcode: json['barcode'] as String,
      productName: json['product_name'] as String?,
      brand: json['brand'] as String?,
      imageUrl: json['image_url'] as String?,
      frontImageUrl: json['front_image_url'] as String?,
      labelImageUrl: json['label_image_url'] as String?,
      nutritionImageUrl: json['nutrition_image_url'] as String?,
      extractedIngredientsText: json['extracted_ingredients_text'] as String?,
      extractedNutrition: _nutritionMapOrNull(json['extracted_nutrition']),
      extractionStatus: json['extraction_status'] as String? ?? 'not_started',
      extractionError: json['extraction_error'] as String?,
      notes: json['notes'] as String?,
      submittedBy: json['submitted_by'] as String?,
      status: json['status'] as String? ?? 'pending',
      source: json['source'] as String? ?? 'barcode_missing',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

Map<String, dynamic>? _nutritionMapOrNull(dynamic value) {
  if (value is! Map) return null;
  return normalizeNutritionMap(Map<String, dynamic>.from(value));
}
