import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';

enum ProductActivityType { viewed, scanned }

extension ProductActivityTypeStorage on ProductActivityType {
  String get storageValue {
    switch (this) {
      case ProductActivityType.viewed:
        return 'viewed';
      case ProductActivityType.scanned:
        return 'scanned';
    }
  }

  static ProductActivityType? fromStorageValue(Object? value) {
    switch (value?.toString().trim()) {
      case 'viewed':
        return ProductActivityType.viewed;
      case 'scanned':
        return ProductActivityType.scanned;
      default:
        return null;
    }
  }
}

@immutable
class ProductActivityEntry {
  final LocalProductSnapshot product;
  final ProductActivityType type;
  final DateTime occurredAt;

  const ProductActivityEntry({
    required this.product,
    required this.type,
    required this.occurredAt,
  });

  factory ProductActivityEntry.fromJson(Map<String, dynamic> json) {
    final product = LocalProductSnapshot.tryParse(json['product']);
    final type = ProductActivityTypeStorage.fromStorageValue(json['type']);
    final occurredAt = _tryParseDateTime(json['occurredAt']);

    if (product == null || type == null || occurredAt == null) {
      throw const FormatException('Invalid product activity entry');
    }

    return ProductActivityEntry(
      product: product,
      type: type,
      occurredAt: occurredAt,
    );
  }

  static ProductActivityEntry? tryParse(Object? json) {
    if (json is! Map) return null;

    try {
      return ProductActivityEntry.fromJson(
        json.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      return null;
    }
  }

  ProductActivityEntry copyWith({
    LocalProductSnapshot? product,
    ProductActivityType? type,
    DateTime? occurredAt,
  }) {
    return ProductActivityEntry(
      product: product ?? this.product,
      type: type ?? this.type,
      occurredAt: occurredAt ?? this.occurredAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product': product.toJson(),
      'type': type.storageValue,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProductActivityEntry &&
            runtimeType == other.runtimeType &&
            product == other.product &&
            type == other.type &&
            occurredAt == other.occurredAt;
  }

  @override
  int get hashCode => Object.hash(product, type, occurredAt);
}

DateTime? _tryParseDateTime(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
