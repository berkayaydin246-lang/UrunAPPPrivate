import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_cursor.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_detail.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_summary.dart';
import 'package:food_analyzer_app/features/admin/repositories/admin_product_report_repository.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';

class AdminProductReportsListState {
  final ProductReportStatus? selectedStatus;
  final List<AdminProductReportSummary> reports;
  final AdminProductReportCursor? nextCursor;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final bool isRefreshing;
  final String? error;
  final int requestGeneration;

  const AdminProductReportsListState({
    this.selectedStatus = ProductReportStatus.pending,
    this.reports = const [],
    this.nextCursor,
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.error,
    this.requestGeneration = 0,
  });

  bool get hasNextPage => nextCursor != null;

  AdminProductReportsListState copyWith({
    ProductReportStatus? selectedStatus,
    bool clearSelectedStatus = false,
    List<AdminProductReportSummary>? reports,
    AdminProductReportCursor? nextCursor,
    bool clearNextCursor = false,
    bool? isInitialLoading,
    bool? isLoadingMore,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    int? requestGeneration,
  }) {
    return AdminProductReportsListState(
      selectedStatus: clearSelectedStatus
          ? null
          : (selectedStatus ?? this.selectedStatus),
      reports: reports ?? this.reports,
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: clearError ? null : (error ?? this.error),
      requestGeneration: requestGeneration ?? this.requestGeneration,
    );
  }
}

final adminProductReportsListControllerProvider =
    StateNotifierProvider.autoDispose<
      AdminProductReportsListController,
      AdminProductReportsListState
    >((ref) {
      return AdminProductReportsListController(
        repository: ref.watch(adminProductReportRepositoryProvider),
      );
    });

class AdminProductReportsListController
    extends StateNotifier<AdminProductReportsListState> {
  AdminProductReportsListController({
    required AdminProductReportRepository repository,
  }) : _repository = repository,
       super(const AdminProductReportsListState()) {
    loadFirstPage();
  }

  final AdminProductReportRepository _repository;

  static const _pageSize = 30;

  Future<void> loadFirstPage() async {
    final generation = state.requestGeneration + 1;
    state = state.copyWith(
      reports: const [],
      clearNextCursor: true,
      isInitialLoading: true,
      isLoadingMore: false,
      isRefreshing: false,
      clearError: true,
      requestGeneration: generation,
    );

    await _fetchFirstPage(generation);
  }

  Future<void> selectStatus(ProductReportStatus? status) async {
    if (status == state.selectedStatus) return;

    final generation = state.requestGeneration + 1;
    state = state.copyWith(
      selectedStatus: status,
      reports: const [],
      clearNextCursor: true,
      isInitialLoading: true,
      isLoadingMore: false,
      isRefreshing: false,
      clearError: true,
      requestGeneration: generation,
    );

    await _fetchFirstPage(generation);
  }

  Future<void> refresh() async {
    if (state.isInitialLoading || state.isRefreshing) return;

    final generation = state.requestGeneration + 1;
    state = state.copyWith(
      isRefreshing: true,
      clearError: true,
      requestGeneration: generation,
    );

    await _fetchFirstPage(generation, preserveVisibleRows: true);
  }

  Future<void> loadMore() async {
    if (state.isInitialLoading ||
        state.isLoadingMore ||
        state.isRefreshing ||
        state.nextCursor == null) {
      return;
    }

    final generation = state.requestGeneration;
    final currentCursor = state.nextCursor;
    if (currentCursor == null) return;

    state = state.copyWith(isLoadingMore: true, clearError: true);

    try {
      final page = await _repository.listReports(
        status: state.selectedStatus,
        limit: _pageSize,
        cursor: currentCursor,
      );
      if (!mounted || generation != state.requestGeneration) return;

      state = state.copyWith(
        reports: _dedupeReports([...state.reports, ...page.reports]),
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        isLoadingMore: false,
      );
    } catch (error) {
      if (!mounted || generation != state.requestGeneration) return;

      state = state.copyWith(isLoadingMore: false, error: _mapError(error));
    }
  }

  void syncUpdatedReport(AdminProductReportDetail report) {
    final matchesActiveFilter =
        state.selectedStatus == null || state.selectedStatus == report.status;

    final updatedSummary = report.toSummary();
    final currentReports = [...state.reports];
    final existingIndex = currentReports.indexWhere(
      (item) => item.id == report.id,
    );

    if (!matchesActiveFilter) {
      if (existingIndex == -1) return;
      currentReports.removeAt(existingIndex);
    } else if (existingIndex == -1) {
      currentReports.insert(0, updatedSummary);
    } else {
      currentReports[existingIndex] = updatedSummary;
    }

    state = state.copyWith(reports: List.unmodifiable(currentReports));
  }

  Future<void> _fetchFirstPage(
    int generation, {
    bool preserveVisibleRows = false,
  }) async {
    try {
      final page = await _repository.listReports(
        status: state.selectedStatus,
        limit: _pageSize,
      );
      if (!mounted || generation != state.requestGeneration) return;

      state = state.copyWith(
        reports: _dedupeReports(page.reports),
        nextCursor: page.nextCursor,
        clearNextCursor: page.nextCursor == null,
        isInitialLoading: false,
        isRefreshing: false,
      );
    } catch (error) {
      if (!mounted || generation != state.requestGeneration) return;

      state = state.copyWith(
        reports: preserveVisibleRows ? state.reports : const [],
        clearNextCursor: !preserveVisibleRows,
        isInitialLoading: false,
        isRefreshing: false,
        error: _mapError(error),
      );
    }
  }

  List<AdminProductReportSummary> _dedupeReports(
    List<AdminProductReportSummary> reports,
  ) {
    final seenIds = <String>{};
    final deduped = <AdminProductReportSummary>[];

    for (final report in reports) {
      if (seenIds.add(report.id)) {
        deduped.add(report);
      }
    }

    return List.unmodifiable(deduped);
  }

  String _mapError(Object error) {
    if (error is AdminProductReportException) {
      switch (error.type) {
        case AdminReportFailureType.notAuthorized:
          return 'Bu alanı görüntüleme yetkiniz yok.';
        case AdminReportFailureType.notAuthenticated:
          return 'Yönetici hesabınızla giriş yapın.';
        case AdminReportFailureType.networkFailure:
          return 'Bildirimler yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.';
        case AdminReportFailureType.reportNotFound:
        case AdminReportFailureType.invalidTransition:
        case AdminReportFailureType.invalidRequest:
        case AdminReportFailureType.unknown:
          return 'Bildirimler yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.';
      }
    }

    return 'Bildirimler yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
}
