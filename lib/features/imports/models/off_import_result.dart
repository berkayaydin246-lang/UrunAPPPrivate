import 'package:food_analyzer_app/features/product/models/product.dart';

enum OffImportSource {
  /// Product already existed in local DB (by barcode or by name+brand merge).
  existingLocal,

  /// New product was fetched from OFF and inserted into the local DB.
  insertedFromOff,
}

class OffImportResult {
  final Product product;
  final OffImportSource source;

  /// True when OFF returned a product but with no ingredients text and no image.
  final bool isLimitedData;

  const OffImportResult({
    required this.product,
    required this.source,
    required this.isLimitedData,
  });
}
