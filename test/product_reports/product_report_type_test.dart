import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

void main() {
  group('ProductReportType', () {
    test('exposes stable database values in enum order', () {
      expect(
        ProductReportType.values.map((reportType) => reportType.databaseValue),
        [
          'wrong_image',
          'outdated_ingredients',
          'wrong_nutrition',
          'wrong_name_or_brand',
          'wrong_category',
          'wrong_barcode',
          'other',
        ],
      );
    });

    test('exposes centralized Turkish labels', () {
      expect(ProductReportType.wrongImage.labelTr, 'Görsel yanlış');
      expect(
        ProductReportType.outdatedIngredients.labelTr,
        'İçindekiler güncel değil',
      );
      expect(
        ProductReportType.wrongNutrition.labelTr,
        'Besin değerleri yanlış',
      );
      expect(
        ProductReportType.wrongNameOrBrand.labelTr,
        'Ürün adı veya marka yanlış',
      );
      expect(ProductReportType.wrongCategory.labelTr, 'Kategori yanlış');
      expect(ProductReportType.wrongBarcode.labelTr, 'Barkod yanlış');
      expect(ProductReportType.other.labelTr, 'Diğer');
    });

    test('parses database values back into the enum', () {
      expect(
        productReportTypeFromDatabaseValue(' wrong_image '),
        ProductReportType.wrongImage,
      );
      expect(
        productReportTypeFromDatabaseValue('wrong_name_or_brand'),
        ProductReportType.wrongNameOrBrand,
      );
      expect(productReportTypeFromDatabaseValue(''), isNull);
      expect(productReportTypeFromDatabaseValue('missing'), isNull);
      expect(productReportTypeFromDatabaseValue(null), isNull);
    });
  });
}
