import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/features/admin/models/current_product_snapshot.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_summary.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

/// Full detail for one report — returned by `admin_get_product_report` and
/// `admin_update_product_report`.
///
/// Contains all summary fields plus evidence image URLs, admin note,
/// reviewer identity, and current product barcode.
@immutable
class AdminProductReportDetail {
  final String id;
  final String? productId;
  final String productNameSnapshot;
  final String? productBrandSnapshot;
  final String? productImageSnapshot;
  final ProductReportType type;
  final String? details;
  final List<String> evidenceImageUrls;
  final int evidenceImageCount;
  final ProductReportStatus status;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final CurrentProductSnapshot? currentProduct;

  const AdminProductReportDetail({
    required this.id,
    required this.productId,
    required this.productNameSnapshot,
    required this.productBrandSnapshot,
    required this.productImageSnapshot,
    required this.type,
    required this.details,
    required this.evidenceImageUrls,
    required this.evidenceImageCount,
    required this.status,
    required this.adminNote,
    required this.createdAt,
    required this.reviewedAt,
    required this.reviewedBy,
    required this.currentProduct,
  });

  factory AdminProductReportDetail.fromJson(Map<String, dynamic> json) {
    final rawType = json['report_type'] as String?;
    final type = rawType != null
        ? productReportTypeFromDatabaseValue(rawType)
        : null;
    if (type == null) {
      throw FormatException(
        'Unknown or missing report_type in AdminProductReportDetail: $rawType',
      );
    }

    final rawStatus = json['status'] as String?;
    final status = rawStatus != null
        ? ProductReportStatus.tryFromDatabase(rawStatus)
        : null;
    if (status == null) {
      throw FormatException(
        'Unknown or missing status in AdminProductReportDetail: $rawStatus',
      );
    }

    final rawUrls = json['evidence_image_urls'];
    final evidenceImageUrls = rawUrls is List
        ? List<String>.unmodifiable(
            rawUrls
                .whereType<String>()
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty),
          )
        : const <String>[];

    return AdminProductReportDetail(
      id: json['id'] as String,
      productId: json['product_id'] as String?,
      productNameSnapshot: json['product_name_snapshot'] as String,
      productBrandSnapshot: json['product_brand_snapshot'] as String?,
      productImageSnapshot: json['product_image_snapshot'] as String?,
      type: type,
      details: json['details'] as String?,
      evidenceImageUrls: evidenceImageUrls,
      evidenceImageCount: (json['evidence_image_count'] as num).toInt(),
      status: status,
      adminNote: json['admin_note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      reviewedAt: _tryParseDateTime(json['reviewed_at']),
      reviewedBy: json['reviewed_by'] as String?,
      currentProduct: CurrentProductSnapshot.tryFromJson(json),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminProductReportDetail &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          status == other.status &&
          adminNote == other.adminNote &&
          reviewedAt == other.reviewedAt;

  @override
  int get hashCode => Object.hash(id, status, adminNote, reviewedAt);

  AdminProductReportSummary toSummary() {
    return AdminProductReportSummary(
      id: id,
      productId: productId,
      productNameSnapshot: productNameSnapshot,
      productBrandSnapshot: productBrandSnapshot,
      productImageSnapshot: productImageSnapshot,
      type: type,
      details: details,
      evidenceImageCount: evidenceImageCount,
      status: status,
      createdAt: createdAt,
      reviewedAt: reviewedAt,
      currentProduct: currentProduct,
    );
  }
}

DateTime? _tryParseDateTime(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
