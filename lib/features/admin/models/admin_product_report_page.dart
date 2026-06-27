import 'package:flutter/foundation.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_cursor.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_summary.dart';

/// One page of results from `admin_list_product_reports`.
///
/// [nextCursor] is null when this is the final page (fewer reports returned
/// than the requested limit, or the returned list is empty).
@immutable
class AdminProductReportPage {
  final List<AdminProductReportSummary> reports;

  /// Non-null when there are more pages to fetch.
  final AdminProductReportCursor? nextCursor;

  const AdminProductReportPage({
    required this.reports,
    required this.nextCursor,
  });

  /// Builds a page from the RPC JSON array, computing the cursor from the
  /// last item when [requestedLimit] reports were returned.
  factory AdminProductReportPage.fromJsonArray(
    List<dynamic> jsonArray, {
    required int requestedLimit,
  }) {
    final reports = jsonArray
        .cast<Map<String, dynamic>>()
        .map(AdminProductReportSummary.fromJson)
        .toList(growable: false);

    // If fewer items than the limit were returned, this is the last page.
    final hasMore = reports.length >= requestedLimit;
    final nextCursor = hasMore
        ? AdminProductReportCursor.fromSummary(reports.last)
        : null;

    return AdminProductReportPage(
      reports: List.unmodifiable(reports),
      nextCursor: nextCursor,
    );
  }

  bool get isEmpty => reports.isEmpty;
  bool get hasNextPage => nextCursor != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminProductReportPage &&
          runtimeType == other.runtimeType &&
          reports == other.reports &&
          nextCursor == other.nextCursor;

  @override
  int get hashCode => Object.hash(reports, nextCursor);
}
