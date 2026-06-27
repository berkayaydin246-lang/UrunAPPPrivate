class ProductContext {
  final String productType;
  final double confidence;
  final String source;

  ProductContext({
    required this.productType,
    required this.confidence,
    required this.source,
  });

  bool get isReliable =>
      confidence >= 0.8 ||
      source == 'barcode_category' ||
      source == 'product_category';
}
