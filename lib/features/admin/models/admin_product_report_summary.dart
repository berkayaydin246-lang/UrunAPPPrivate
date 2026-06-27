import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/features/admin/models/current_product_snapshot.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

/// Summary fields returned by `admin_list_product_reports`.
///
/// Does not contain evidence image URLs or the admin note — use
/// [AdminProductReportDetail] (from `admin_get_product_report`) for those.
@immutable
class AdminProductReportSummary {
  final String id;
  final String? productId;
  final String productNameSnapshot;
  final String? productBrandSnapshot;
  final String? productImageSnapshot;
  final ProductReportType type;
  final String? details;
  final int evidenceImageCount;
  final ProductReportStatus status;
  final DateTime createdAt;
  final DateTime? reviewedAt;

  /// Current product data from the catalog at fetch time. Null when the
  /// product has been deleted or was never linked.
  final CurrentProductSnapshot? currentProduct;

  const AdminProductReportSummary({
    required this.id,
    required this.productId,
    required this.productNameSnapshot,
    required this.productBrandSnapshot,
    required this.productImageSnapshot,
    required this.type,
    required this.details,
    required this.evidenceImageCount,
    required this.status,
    required this.createdAt,
    required this.reviewedAt,
    required this.currentProduct,
  });

  factory AdminProductReportSummary.fromJson(Map<String, dynamic> json) {
    final rawType = json['report_type'] as String?;
    final type = rawType != null
        ? productReportTypeFromDatabaseValue(rawType)
        : null;
    if (type == null) {
      throw FormatException(
        'Unknown or missing report_type in AdminProductReportSummary: $rawType',
      );
    }

    final rawStatus = json['status'] as String?;
    final status = rawStatus != null
        ? ProductReportStatus.tryFromDatabase(rawStatus)
        : null;
    if (status == null) {
      throw FormatException(
        'Unknown or missing status in AdminProductReportSummary: $rawStatus',
      );
    }

    return AdminProductReportSummary(
      id: json['id'] as String,
      productId: json['product_id'] as String?,
      productNameSnapshot: json['product_name_snapshot'] as String,
      productBrandSnapshot: json['product_brand_snapshot'] as String?,
      productImageSnapshot: json['product_image_snapshot'] as String?,
      type: type,
      details: json['details'] as String?,
      evidenceImageCount: (json['evidence_image_count'] as num).toInt(),
      status: status,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: _tryParseDateTime(json['reviewed_at']),
      currentProduct: CurrentProductSnapshot.tryFromJson(json),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminProductReportSummary &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status &&
          reviewedAt == other.reviewedAt;

  @override
  int get hashCode => Object.hash(id, status, reviewedAt);
}

DateTime? _tryParseDateTime(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
