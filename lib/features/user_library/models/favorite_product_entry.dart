import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/features/user_library/models/local_product_snapshot.dart';

@immutable
class FavoriteProductEntry {
  final LocalProductSnapshot product;
  final DateTime addedAt;

  const FavoriteProductEntry({required this.product, required this.addedAt});

  factory FavoriteProductEntry.fromJson(Map<String, dynamic> json) {
    final product = LocalProductSnapshot.tryParse(json['product']);
    final addedAt = _tryParseDateTime(json['addedAt']);

    if (product == null || addedAt == null) {
      throw const FormatException('Invalid favorite entry');
    }

    return FavoriteProductEntry(product: product, addedAt: addedAt);
  }

  static FavoriteProductEntry? tryParse(Object? json) {
    if (json is! Map) return null;

    try {
      return FavoriteProductEntry.fromJson(
        json.map((key, value) => MapEntry(key.toString(), value)),
      );
    } on FormatException {
      return null;
    }
  }

  FavoriteProductEntry copyWith({
    LocalProductSnapshot? product,
    DateTime? addedAt,
  }) {
    return FavoriteProductEntry(
      product: product ?? this.product,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product': product.toJson(),
      'addedAt': addedAt.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FavoriteProductEntry &&
            runtimeType == other.runtimeType &&
            product == other.product &&
            addedAt == other.addedAt;
  }

  @override
  int get hashCode => Object.hash(product, addedAt);
}

DateTime? _tryParseDateTime(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
