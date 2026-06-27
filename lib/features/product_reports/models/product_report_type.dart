enum ProductReportType {
  wrongImage,
  outdatedIngredients,
  wrongNutrition,
  wrongNameOrBrand,
  wrongCategory,
  wrongBarcode,
  other,
}

extension ProductReportTypeX on ProductReportType {
  String get databaseValue {
    switch (this) {
      case ProductReportType.wrongImage:
        return 'wrong_image';
      case ProductReportType.outdatedIngredients:
        return 'outdated_ingredients';
      case ProductReportType.wrongNutrition:
        return 'wrong_nutrition';
      case ProductReportType.wrongNameOrBrand:
        return 'wrong_name_or_brand';
      case ProductReportType.wrongCategory:
        return 'wrong_category';
      case ProductReportType.wrongBarcode:
        return 'wrong_barcode';
      case ProductReportType.other:
        return 'other';
    }
  }

  String get labelTr {
    switch (this) {
      case ProductReportType.wrongImage:
        return 'Görsel yanlış';
      case ProductReportType.outdatedIngredients:
        return 'İçindekiler güncel değil';
      case ProductReportType.wrongNutrition:
        return 'Besin değerleri yanlış';
      case ProductReportType.wrongNameOrBrand:
        return 'Ürün adı veya marka yanlış';
      case ProductReportType.wrongCategory:
        return 'Kategori yanlış';
      case ProductReportType.wrongBarcode:
        return 'Barkod yanlış';
      case ProductReportType.other:
        return 'Diğer';
    }
  }
}

ProductReportType? productReportTypeFromDatabaseValue(String? rawValue) {
  final normalizedValue = rawValue?.trim();
  if (normalizedValue == null || normalizedValue.isEmpty) {
    return null;
  }

  for (final reportType in ProductReportType.values) {
    if (reportType.databaseValue == normalizedValue) {
      return reportType;
    }
  }

  return null;
}
