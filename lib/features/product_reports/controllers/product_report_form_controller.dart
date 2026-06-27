import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_submission.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';
import 'package:food_analyzer_app/features/product_reports/repositories/product_report_repository.dart';

enum ReportSubmissionStatus { idle, submitting, success, failure }

class ReportFormState {
  final ProductReportType? selectedType;
  final String details;
  final ReportSubmissionStatus status;
  final String? errorMessage;

  const ReportFormState({
    this.selectedType,
    this.details = '',
    this.status = ReportSubmissionStatus.idle,
    this.errorMessage,
  });

  bool get canSubmit {
    if (selectedType == null) return false;
    if (status == ReportSubmissionStatus.submitting) return false;
    if (details.trim().length > 1000) return false;
    if (selectedType == ProductReportType.other && details.trim().isEmpty) {
      return false;
    }
    return true;
  }

  ReportFormState copyWith({
    ProductReportType? selectedType,
    bool clearSelectedType = false,
    String? details,
    ReportSubmissionStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ReportFormState(
      selectedType: clearSelectedType
          ? null
          : (selectedType ?? this.selectedType),
      details: details ?? this.details,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ProductReportFormNotifier extends StateNotifier<ReportFormState> {
  ProductReportFormNotifier({
    required this.productId,
    required ProductReportRepository repository,
  }) : _repository = repository,
       super(const ReportFormState());

  final String productId;
  final ProductReportRepository _repository;

  void selectType(ProductReportType type) {
    state = state.copyWith(selectedType: type, clearError: true);
  }

  void updateDetails(String value) {
    state = state.copyWith(details: value, clearError: true);
  }

  Future<bool> submit() async {
    if (state.status == ReportSubmissionStatus.submitting) return false;
    if (!state.canSubmit) return false;

    final type = state.selectedType!;
    final trimmedDetails = state.details.trim();

    state = state.copyWith(
      status: ReportSubmissionStatus.submitting,
      clearError: true,
    );

    try {
      await _repository.submitReport(
        ProductReportSubmission(
          productId: productId,
          type: type,
          details: trimmedDetails.isEmpty ? null : trimmedDetails,
          evidenceImageUrls: const [],
        ),
      );
      state = state.copyWith(status: ReportSubmissionStatus.success);
      return true;
    } on ProductReportSubmissionException catch (e) {
      state = state.copyWith(
        status: ReportSubmissionStatus.failure,
        errorMessage: _mapError(e.type),
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        status: ReportSubmissionStatus.failure,
        errorMessage: _kUnknownError,
      );
      return false;
    }
  }

  static String _mapError(ProductReportSubmissionFailureType type) {
    switch (type) {
      case ProductReportSubmissionFailureType.rateLimited:
        return 'Bugün çok sayıda bildirim gönderdin. Daha sonra tekrar deneyebilirsin.';
      case ProductReportSubmissionFailureType.duplicateRecentReport:
        return 'Bu ürün için yakın zamanda aynı bildirimi gönderdin.';
      case ProductReportSubmissionFailureType.productNotFound:
        return 'Bu ürün artık veritabanında bulunamıyor.';
      case ProductReportSubmissionFailureType.invalidSubmission:
        return 'Bildirim bilgilerini kontrol edip tekrar dene.';
      case ProductReportSubmissionFailureType.networkFailure:
        return 'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.';
      case ProductReportSubmissionFailureType.unknown:
        return _kUnknownError;
    }
  }

  static const _kUnknownError =
      'Bildirim gönderilemedi. Biraz sonra tekrar dene.';
}

final productReportFormProvider = StateNotifierProvider.autoDispose
    .family<ProductReportFormNotifier, ReportFormState, String>(
      (ref, productId) => ProductReportFormNotifier(
        productId: productId,
        repository: ref.watch(productReportRepositoryProvider),
      ),
    );
