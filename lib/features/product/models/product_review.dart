import 'package:flutter/material.dart';

class ProductReview {
  final String id;
  final String productId;
  final String scoreLabel; // iyi_secim, orta, dikkatli_tuket, sik_tuketme
  final String? summary;
  final String? warningText;
  final List<String>? positivePoints;
  final List<String>? negativePoints;
  final String? consumptionAdvice;
  final bool? suitableForChildren;
  final String reviewStatus; // draft, published, archived
  final String? reviewedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductReview({
    required this.id,
    required this.productId,
    required this.scoreLabel,
    this.summary,
    this.warningText,
    this.positivePoints,
    this.negativePoints,
    this.consumptionAdvice,
    this.suitableForChildren,
    required this.reviewStatus,
    this.reviewedBy,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create ProductReview from Supabase JSON
  factory ProductReview.fromJson(Map<String, dynamic> json) {
    return ProductReview(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      scoreLabel: json['score_label'] as String,
      summary: json['summary'] as String?,
      warningText: json['warning_text'] as String?,
      positivePoints: _parseStringArray(json['positive_points']),
      negativePoints: _parseStringArray(json['negative_points']),
      consumptionAdvice: json['consumption_advice'] as String?,
      suitableForChildren: json['suitable_for_children'] as bool?,
      reviewStatus: json['review_status'] as String? ?? 'draft',
      reviewedBy: json['reviewed_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert ProductReview to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'score_label': scoreLabel,
      'summary': summary,
      'warning_text': warningText,
      'positive_points': positivePoints,
      'negative_points': negativePoints,
      'consumption_advice': consumptionAdvice,
      'suitable_for_children': suitableForChildren,
      'review_status': reviewStatus,
      'reviewed_by': reviewedBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Get user-friendly score label in Turkish
  String getScoreLabelTurkish() {
    switch (scoreLabel) {
      case 'iyi_secim':
        return 'İyi Seçim';
      case 'orta':
        return 'Orta';
      case 'dikkatli_tuket':
        return 'Dikkatli Tüket';
      case 'sik_tuketme':
        return 'Sık Tüketme';
      default:
        return scoreLabel;
    }
  }

  /// Get color for score label
  Color getScoreColor() {
    switch (scoreLabel) {
      case 'iyi_secim':
        return Colors.green;
      case 'orta':
        return Colors.amber;
      case 'dikkatli_tuket':
        return Colors.orange;
      case 'sik_tuketme':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  String toString() => 'ProductReview(id=$id, scoreLabel=$scoreLabel)';
}

/// Helper to parse PostgreSQL text arrays
List<String>? _parseStringArray(dynamic value) {
  if (value == null) return null;
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return null;
}
