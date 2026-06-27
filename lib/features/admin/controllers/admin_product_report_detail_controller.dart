import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_detail.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_product_report_repository.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';

class AdminProductReportDetailState {
  final AdminProductReportDetail? report;
  final bool isLoading;
  final bool isUpdating;
  final String? error;

  const AdminProductReportDetailState({
    this.report,
    this.isLoading = true,
    this.isUpdating = false,
    this.error,
  });

  AdminProductReportDetailState copyWith({
    AdminProductReportDetail? report,
    bool clearReport = false,
    bool? isLoading,
    bool? isUpdating,
    String? error,
    bool clearError = false,
  }) {
    return AdminProductReportDetailState(
      report: clearReport ? null : (report ?? this.report),
      isLoading: isLoading ?? this.isLoading,
      isUpdating: isUpdating ?? this.isUpdating,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final adminProductReportDetailControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      AdminProductReportDetailController,
      AdminProductReportDetailState,
      String
    >((ref, reportId) {
      return AdminProductReportDetailController(
        reportId: reportId,
        repository: ref.watch(adminProductReportRepositoryProvider),
      );
    });

class AdminProductReportDetailController
    extends StateNotifier<AdminProductReportDetailState> {
  AdminProductReportDetailController({
    required String reportId,
    required AdminProductReportRepository repository,
  }) : _reportId = reportId,
       _repository = repository,
       super(const AdminProductReportDetailState()) {
    load();
  }

  final String _reportId;
  final AdminProductReportRepository _repository;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final report = await _repository.getReport(_reportId);
      if (!mounted) return;

      state = state.copyWith(report: report, isLoading: false);
    } catch (error) {
      if (!mounted) return;

      state = state.copyWith(isLoading: false, error: _mapError(error));
    }
  }

  Future<bool> updateReport({
    required ProductReportStatus status,
    String? adminNote,
  }) async {
    final currentReport = state.report;
    if (currentReport == null || state.isUpdating) {
      return false;
    }

    state = state.copyWith(isUpdating: true, clearError: true);

    try {
      final updatedReport = await _repository.updateReport(
        reportId: currentReport.id,
        status: status,
        adminNote: adminNote,
      );
      if (!mounted) return false;

      state = state.copyWith(report: updatedReport, isUpdating: false);
      return true;
    } catch (error) {
      if (!mounted) return false;

      state = state.copyWith(isUpdating: false, error: _mapError(error));
      return false;
    }
  }

  String _mapError(Object error) {
    if (error is AdminProductReportException) {
      switch (error.type) {
        case AdminReportFailureType.notAuthorized:
          return 'Bu alanı görüntüleme yetkiniz yok.';
        case AdminReportFailureType.reportNotFound:
          return 'Bildirim bulunamadı.';
        case AdminReportFailureType.invalidTransition:
          return 'Bu durum değişikliği geçerli değil.';
        case AdminReportFailureType.invalidRequest:
          return 'İşlem şu anda tamamlanamadı. Lütfen bilgileri kontrol edin.';
        case AdminReportFailureType.notAuthenticated:
        case AdminReportFailureType.networkFailure:
        case AdminReportFailureType.unknown:
          return 'Bildirim yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.';
      }
    }

    return 'Bildirim yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
}
