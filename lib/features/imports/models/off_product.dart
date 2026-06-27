import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';

class OffProduct {
  final String barcode;
  final String? name;
  final String? brand;
  final String? ingredientsText;
  final String? imageUrl;
  final List<String>? categories;
  final String? categoriesText;
  final String sourceUrl;
  final NutritionData? nutriments;

  OffProduct({
    required this.barcode,
    this.name,
    this.brand,
    this.ingredientsText,
    this.imageUrl,
    this.categories,
    this.categoriesText,
    required this.sourceUrl,
    this.nutriments,
  });

  @override
  String toString() => 'OffProduct(barcode=$barcode, name=$name)';
}
