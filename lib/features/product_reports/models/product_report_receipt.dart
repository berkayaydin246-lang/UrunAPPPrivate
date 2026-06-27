class ProductReportReceipt {
  final String reportId;
  final DateTime? submittedAt;

  const ProductReportReceipt({required this.reportId, this.submittedAt});

  factory ProductReportReceipt.fromRpcResponse(dynamic response) {
    final data = switch (response) {
      final Map<String, dynamic> map => map,
      final Map map => map.map((key, value) => MapEntry(key.toString(), value)),
      final List<dynamic> list when list.length == 1 && list.first is Map =>
        (list.first as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      _ => throw const FormatException(
        'Invalid product report receipt response',
      ),
    };

    final reportId = data['report_id']?.toString().trim();
    if (reportId == null || reportId.isEmpty) {
      throw const FormatException('Missing report_id in RPC response');
    }

    final submittedAtRaw = data['submitted_at']?.toString().trim();
    final submittedAt = submittedAtRaw == null || submittedAtRaw.isEmpty
        ? null
        : DateTime.tryParse(submittedAtRaw);

    return ProductReportReceipt(reportId: reportId, submittedAt: submittedAt);
  }
}
