import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

class ProductReportSubmission {
  final String productId;
  final ProductReportType type;
  final String? details;
  final List<String> evidenceImageUrls;

  ProductReportSubmission({
    required this.productId,
    required this.type,
    this.details,
    List<String> evidenceImageUrls = const <String>[],
  }) : evidenceImageUrls = List<String>.unmodifiable(evidenceImageUrls);
}
