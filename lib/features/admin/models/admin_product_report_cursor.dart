import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_summary.dart';

/// Keyset pagination cursor for `admin_list_product_reports`.
///
/// Encodes the (created_at, id) of the last row on a page so the next call
/// can continue exactly where the previous left off with no duplicates or
/// missing rows — even when multiple reports share the same timestamp.
@immutable
class AdminProductReportCursor {
  final DateTime createdAt;
  final String id;

  const AdminProductReportCursor({required this.createdAt, required this.id});

  /// Builds the cursor from the last summary in a page.
  factory AdminProductReportCursor.fromSummary(
    AdminProductReportSummary summary,
  ) {
    return AdminProductReportCursor(
      createdAt: summary.createdAt,
      id: summary.id,
    );
  }

  /// ISO-8601 string suitable for `p_before_created_at` RPC parameter.
  String get createdAtIso => createdAt.toUtc().toIso8601String();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminProductReportCursor &&
          runtimeType == other.runtimeType &&
          createdAt == other.createdAt &&
          id == other.id;

  @override
  int get hashCode => Object.hash(createdAt, id);
}
