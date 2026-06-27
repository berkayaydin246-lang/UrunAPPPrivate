import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/admin/controllers/admin_product_reports_list_controller.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_detail.dart';
import 'package:food_analyzer_app/features/admin/widgets/admin_authorization_gate.dart';
import 'package:food_analyzer_app/features/admin/widgets/admin_product_report_card.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';

class AdminProductReportsPage extends ConsumerStatefulWidget {
  const AdminProductReportsPage({super.key});

  @override
  ConsumerState<AdminProductReportsPage> createState() =>
      _AdminProductReportsPageState();
}

class _AdminProductReportsPageState
    extends ConsumerState<AdminProductReportsPage> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Ürün Bildirimleri'),
        actions: const [AdminSignOutButton()],
      ),
      body: AdminAuthorizationGate(
        authorizedBuilder: (context, ref) {
          final state = ref.watch(adminProductReportsListControllerProvider);
          final notifier = ref.read(
            adminProductReportsListControllerProvider.notifier,
          );

          return Column(
            children: [
              _FilterBar(
                selectedStatus: state.selectedStatus,
                onSelected: notifier.selectStatus,
              ),
              Expanded(child: _buildContent(context, state, notifier)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AdminProductReportsListState state,
    AdminProductReportsListController notifier,
  ) {
    if (state.isInitialLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.reports.isEmpty) {
      final isUnauthorized =
          state.error == 'Bu alanı görüntüleme yetkiniz yok.';
      return _ListMessageState(
        icon: isUnauthorized ? Icons.lock_outline : Icons.error_outline,
        title: isUnauthorized ? 'Yetki Gerekli' : 'Bildirimler Yüklenemedi',
        message: state.error!,
        actionLabel: 'Tekrar Dene',
        onAction: notifier.refresh,
      );
    }

    if (state.reports.isEmpty) {
      return RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          children: [
            _ListMessageState(
              icon: Icons.inbox_outlined,
              title: 'Liste Boş',
              message: state.selectedStatus == ProductReportStatus.pending
                  ? 'Bekleyen ürün bildirimi yok.'
                  : 'Bu durumda ürün bildirimi bulunmuyor.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.builder(
        key: const ValueKey('admin-product-reports-list'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: state.reports.length + 1,
        itemBuilder: (context, index) {
          if (index == state.reports.length) {
            return Column(
              children: [
                if (state.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: _InlineListError(
                      message: state.error!,
                      onRetry: state.hasNextPage
                          ? notifier.loadMore
                          : notifier.refresh,
                    ),
                  ),
                if (state.isLoadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
              ],
            );
          }

          final report = state.reports[index];
          return AdminProductReportCard(
            report: report,
            onTap: () => _openDetail(report.id),
          );
        },
      ),
    );
  }

  Future<void> _openDetail(String reportId) async {
    final updatedReport = await context.pushNamed<AdminProductReportDetail>(
      'admin_product_report_detail',
      pathParameters: {'id': reportId},
    );

    if (!mounted || updatedReport == null) return;

    ref
        .read(adminProductReportsListControllerProvider.notifier)
        .syncUpdatedReport(updatedReport);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 320) return;

    ref.read(adminProductReportsListControllerProvider.notifier).loadMore();
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selectedStatus, required this.onSelected});

  final ProductReportStatus? selectedStatus;
  final ValueChanged<ProductReportStatus?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <({ProductReportStatus? status, String label})>[
      (
        status: ProductReportStatus.pending,
        label: ProductReportStatus.pending.labelTr,
      ),
      (
        status: ProductReportStatus.reviewing,
        label: ProductReportStatus.reviewing.labelTr,
      ),
      (
        status: ProductReportStatus.resolved,
        label: ProductReportStatus.resolved.labelTr,
      ),
      (
        status: ProductReportStatus.rejected,
        label: ProductReportStatus.rejected.labelTr,
      ),
      (status: null, label: 'Tümü'),
    ];

    return Container(
      height: 64,
      width: double.infinity,
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option.status == selectedStatus;
          return Semantics(
            label: '${option.label} filtresi',
            button: true,
            child: ChoiceChip(
              key: ValueKey(
                'report-filter-${option.status?.databaseValue ?? 'all'}',
              ),
              label: Text(option.label),
              selected: isSelected,
              onSelected: (_) => onSelected(option.status),
            ),
          );
        },
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemCount: options.length,
      ),
    );
  }
}

class _ListMessageState extends StatelessWidget {
  const _ListMessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineListError extends StatelessWidget {
  const _InlineListError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.dangerText),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
        ],
      ),
    );
  }
}
