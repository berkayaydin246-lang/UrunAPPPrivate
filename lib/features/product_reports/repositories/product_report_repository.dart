import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:food_analyzer_app/core/services/app_installation_id_service.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_receipt.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_submission.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

typedef ProductReportRpcInvoker =
    Future<dynamic> Function(String functionName, Map<String, dynamic> params);

abstract interface class ProductReportRepository {
  Future<ProductReportReceipt> submitReport(ProductReportSubmission submission);
}

enum ProductReportSubmissionFailureType {
  rateLimited,
  duplicateRecentReport,
  productNotFound,
  invalidSubmission,
  networkFailure,
  unknown,
}

class ProductReportSubmissionException implements Exception {
  final ProductReportSubmissionFailureType type;
  final String userMessage;

  const ProductReportSubmissionException({
    required this.type,
    required this.userMessage,
  });

  @override
  String toString() {
    return 'ProductReportSubmissionException(type: $type)';
  }
}

final productReportRepositoryProvider = Provider<ProductReportRepository>((
  ref,
) {
  return SupabaseProductReportRepository(
    installationIdService: ref.watch(appInstallationIdServiceProvider),
  );
});

class SupabaseProductReportRepository implements ProductReportRepository {
  SupabaseProductReportRepository({
    required AppInstallationIdService installationIdService,
    ProductReportRpcInvoker? rpcInvoker,
    String Function()? submissionIdGenerator,
  }) : _installationIdService = installationIdService,
       _rpcInvoker = rpcInvoker ?? _defaultRpcInvoker,
       _submissionIdGenerator = submissionIdGenerator ?? generateUuidV4;

  final AppInstallationIdService _installationIdService;
  final ProductReportRpcInvoker _rpcInvoker;
  final String Function() _submissionIdGenerator;

  static const _submitProductReportRpc = 'submit_product_report';

  @override
  Future<ProductReportReceipt> submitReport(
    ProductReportSubmission submission,
  ) async {
    final productId = submission.productId.trim();
    final normalizedDetails = _normalizeDetails(submission.details);
    final normalizedEvidenceUrls = _normalizeEvidenceUrls(
      submission.evidenceImageUrls,
    );

    if (!_uuidRegex.hasMatch(productId)) {
      throw _invalidSubmissionFailure();
    }

    if (normalizedDetails != null && normalizedDetails.length > 1000) {
      throw _invalidSubmissionFailure();
    }

    if (normalizedEvidenceUrls.length > 3) {
      throw _invalidSubmissionFailure();
    }

    final installationId = await _installationIdService
        .getOrCreateInstallationId();
    if (!_uuidRegex.hasMatch(installationId)) {
      throw _unknownFailure();
    }

    final clientSubmissionId = _submissionIdGenerator();
    if (!_uuidRegex.hasMatch(clientSubmissionId)) {
      throw _unknownFailure();
    }

    try {
      final response = await _rpcInvoker(_submitProductReportRpc, {
        'p_product_id': productId,
        'p_report_type': submission.type.databaseValue,
        'p_details': normalizedDetails,
        'p_client_install_id': installationId,
        'p_client_submission_id': clientSubmissionId,
        'p_evidence_image_urls': normalizedEvidenceUrls,
      });

      return ProductReportReceipt.fromRpcResponse(response);
    } on ProductReportSubmissionException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrestException(error);
    } on SocketException {
      throw _networkFailure();
    } on HttpException {
      throw _networkFailure();
    } on TimeoutException {
      throw _networkFailure();
    } catch (_) {
      throw _unknownFailure();
    }
  }

  static Future<dynamic> _defaultRpcInvoker(
    String functionName,
    Map<String, dynamic> params,
  ) {
    return SupabaseService.client.rpc(functionName, params: params);
  }

  ProductReportSubmissionException _mapPostgrestException(
    PostgrestException error,
  ) {
    switch (error.message.trim()) {
      case 'report_rate_limited':
        return const ProductReportSubmissionException(
          type: ProductReportSubmissionFailureType.rateLimited,
          userMessage:
              'Kısa sürede çok fazla bildirim gönderildi. Lütfen daha sonra tekrar deneyin.',
        );
      case 'duplicate_recent_report':
        return const ProductReportSubmissionException(
          type: ProductReportSubmissionFailureType.duplicateRecentReport,
          userMessage:
              'Bu ürün için aynı türde bir bildirim kısa süre önce zaten gönderildi.',
        );
      case 'product_not_found':
        return const ProductReportSubmissionException(
          type: ProductReportSubmissionFailureType.productNotFound,
          userMessage: 'Ürün artık bulunamadığı için bildirim gönderilemedi.',
        );
      case 'invalid_product_id':
      case 'invalid_client_install_id':
      case 'invalid_client_submission_id':
      case 'invalid_report_type':
      case 'details_too_long':
      case 'too_many_evidence_images':
        return _invalidSubmissionFailure();
      default:
        return _unknownFailure();
    }
  }

  static ProductReportSubmissionException _invalidSubmissionFailure() {
    return const ProductReportSubmissionException(
      type: ProductReportSubmissionFailureType.invalidSubmission,
      userMessage:
          'Bildirim bilgileri geçersiz. Lütfen kontrol edip tekrar deneyin.',
    );
  }

  static ProductReportSubmissionException _networkFailure() {
    return const ProductReportSubmissionException(
      type: ProductReportSubmissionFailureType.networkFailure,
      userMessage:
          'Bağlantı hatası nedeniyle bildirim gönderilemedi. Lütfen tekrar deneyin.',
    );
  }

  static ProductReportSubmissionException _unknownFailure() {
    return const ProductReportSubmissionException(
      type: ProductReportSubmissionFailureType.unknown,
      userMessage: 'Bildirim şu anda gönderilemedi. Lütfen tekrar deneyin.',
    );
  }
}

String? _normalizeDetails(String? details) {
  final trimmedDetails = details?.trim();
  if (trimmedDetails == null || trimmedDetails.isEmpty) {
    return null;
  }
  return trimmedDetails;
}

List<String> _normalizeEvidenceUrls(List<String> evidenceImageUrls) {
  return List<String>.unmodifiable([
    for (final evidenceUrl in evidenceImageUrls)
      if (evidenceUrl.trim().isNotEmpty) evidenceUrl.trim(),
  ]);
}

final _uuidRegex = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
