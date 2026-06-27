import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';

@immutable
class LocalProductSnapshot {
  final String productId;
  final String name;
  final String? brand;
  final String? imageUrl;
  final List<String> categoryTags;

  const LocalProductSnapshot({
    required this.productId,
    required this.name,
    this.brand,
    this.imageUrl,
    this.categoryTags = const <String>[],
  });

  factory LocalProductSnapshot.fromJson(Map<String, dynamic> json) {
    final productId = _readRequiredString(json['productId']);
    final name = _readRequiredString(json['name']);

    return LocalProductSnapshot(
      productId: productId,
      name: name,
      brand: _readOptionalString(json['brand']),
      imageUrl: _readOptionalString(json['imageUrl']),
      categoryTags: _readStringList(json['categoryTags']),
    );
  }

  static LocalProductSnapshot? tryParse(Object? json) {
    if (json is! Map) return null;

    try {
      return LocalProductSnapshot.fromJson(
        json.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      return null;
    }
  }

  LocalProductSnapshot copyWith({
    String? productId,
    String? name,
    String? brand,
    bool clearBrand = false,
    String? imageUrl,
    bool clearImageUrl = false,
    List<String>? categoryTags,
  }) {
    return LocalProductSnapshot(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      brand: clearBrand ? null : (brand ?? this.brand),
      imageUrl: clearImageUrl ? null : (imageUrl ?? this.imageUrl),
      categoryTags: categoryTags ?? this.categoryTags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'name': name,
      'brand': brand,
      'imageUrl': imageUrl,
      'categoryTags': categoryTags,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LocalProductSnapshot &&
            runtimeType == other.runtimeType &&
            productId == other.productId &&
            name == other.name &&
            brand == other.brand &&
            imageUrl == other.imageUrl &&
            listEquals(categoryTags, other.categoryTags);
  }

  @override
  int get hashCode => Object.hash(
    productId,
    name,
    brand,
    imageUrl,
    Object.hashAll(categoryTags),
  );
}

LocalProductSnapshot localSnapshotFromProduct(Product product) {
  return LocalProductSnapshot(
    productId: product.id,
    name: product.name.trim(),
    brand: _normalizeOptionalString(product.brand),
    imageUrl: _normalizeOptionalString(product.imageUrl),
    categoryTags: _readStringList(product.categoryTags),
  );
}

String _readRequiredString(Object? value) {
  final normalized = _normalizeOptionalString(value);
  if (normalized == null) {
    throw const FormatException('Missing required string value');
  }
  return normalized;
}

String? _readOptionalString(Object? value) {
  return _normalizeOptionalString(value);
}

String? _normalizeOptionalString(Object? value) {
  final normalized = value?.toString().trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const <String>[];

  final seen = <String>{};
  final items = <String>[];

  for (final item in value) {
    final normalized = item.toString().trim();
    if (normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    items.add(normalized);
  }

  return List<String>.unmodifiable(items);
}
