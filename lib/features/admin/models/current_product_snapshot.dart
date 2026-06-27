import 'package:flutter/foundation.dart';

/// Current product data fetched from the catalog at review time.
///
/// May be null in its entirety when the product was deleted after the report
/// was submitted. Individual fields may be null for incomplete product rows.
@immutable
class CurrentProductSnapshot {
  final String? name;
  final String? brand;
  final String? imageUrl;
  final String? barcode;

  const CurrentProductSnapshot({
    this.name,
    this.brand,
    this.imageUrl,
    this.barcode,
  });

  /// Returns null when all current-product fields in [json] are absent/null.
  static CurrentProductSnapshot? tryFromJson(Map<String, dynamic> json) {
    final name = json['current_product_name'] as String?;
    final brand = json['current_product_brand'] as String?;
    final imageUrl = json['current_product_image_url'] as String?;
    final barcode = json['current_product_barcode'] as String?;

    if (name == null && brand == null && imageUrl == null && barcode == null) {
      return null;
    }

    return CurrentProductSnapshot(
      name: name,
      brand: brand,
      imageUrl: imageUrl,
      barcode: barcode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrentProductSnapshot &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          brand == other.brand &&
          imageUrl == other.imageUrl &&
          barcode == other.barcode;

  @override
  int get hashCode => Object.hash(name, brand, imageUrl, barcode);
}
