import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';

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
  final ProductScoringLifecycleResult? scoring;

  const OffImportResult({
    required this.product,
    required this.source,
    required this.isLimitedData,
    this.scoring,
  });
}
