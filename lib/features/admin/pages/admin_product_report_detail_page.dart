import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/core/utils/turkish_date_time_formatter.dart';
import 'package:food_analyzer_app/core/widgets/fresh_cached_product_image.dart';
import 'package:food_analyzer_app/features/admin/controllers/admin_product_report_detail_controller.dart';
import 'package:food_analyzer_app/features/admin/models/admin_product_report_detail.dart';
import 'package:food_analyzer_app/features/admin/widgets/admin_authorization_gate.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_status.dart';
import 'package:food_analyzer_app/features/product_reports/models/product_report_type.dart';

class AdminProductReportDetailPage extends ConsumerStatefulWidget {
  const AdminProductReportDetailPage({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<AdminProductReportDetailPage> createState() =>
      _AdminProductReportDetailPageState();
}

class _AdminProductReportDetailPageState
    extends ConsumerState<AdminProductReportDetailPage> {
  late final TextEditingController _adminNoteController;
  String? _syncedAdminNote;
  var _didPopWithResult = false;

  @override
  void initState() {
    super.initState();
    _adminNoteController = TextEditingController();
  }

  @override
  void dispose() {
    _adminNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AdminProductReportDetailState>(
      adminProductReportDetailControllerProvider(widget.reportId),
      (previous, next) {
        final adminNote = next.report?.adminNote ?? '';
        if (next.report != null && adminNote != _syncedAdminNote) {
          _syncedAdminNote = adminNote;
          _adminNoteController.value = TextEditingValue(
            text: adminNote,
            selection: TextSelection.collapsed(offset: adminNote.length),
          );
        }
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _popWithLatestReport();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Geri',
            onPressed: _popWithLatestReport,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Bildirim Detayı'),
          actions: const [AdminSignOutButton()],
        ),
        body: AdminAuthorizationGate(
          authorizedBuilder: (context, ref) {
            final state = ref.watch(
              adminProductReportDetailControllerProvider(widget.reportId),
            );
            final controller = ref.read(
              adminProductReportDetailControllerProvider(
                widget.reportId,
              ).notifier,
            );

            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state.report == null) {
              return _DetailMessageState(
                icon: Icons.error_outline,
                title: 'Bildirim Yüklenemedi',
                message:
                    state.error ??
                    'Bildirim yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
                actionLabel: 'Tekrar Dene',
                onAction: controller.load,
              );
            }

            final report = state.report!;
            final canSaveNote = _canSaveNote(report, state.isUpdating);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (state.error != null) ...[
                  _InlineError(message: state.error!),
                  const SizedBox(height: 12),
                ],
                _SectionCard(
                  title: 'Bildirim anındaki ürün',
                  child: _SnapshotSection(report: report),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Kullanıcı açıklaması',
                  child: Text(
                    report.details?.trim().isNotEmpty == true
                        ? report.details!.trim()
                        : 'Kullanıcı açıklama eklememiş.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: report.details?.trim().isNotEmpty == true
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Kanıt görselleri',
                  child: _EvidenceSection(
                    report: report,
                    onImageTap: _openImagePreview,
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Mevcut ürün kaydı',
                  child: _CurrentProductSection(report: report),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Yönetici notu',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('admin-report-note-field'),
                        controller: _adminNoteController,
                        minLines: 3,
                        maxLines: 5,
                        maxLength: 2000,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        enabled: !state.isUpdating,
                        decoration: const InputDecoration(
                          hintText: 'İnceleme sırasında not ekleyin',
                          alignLabelWithHint: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        key: const ValueKey('admin-report-note-save'),
                        onPressed: canSaveNote
                            ? () => _saveNote(controller, report.status)
                            : null,
                        child: state.isUpdating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text('Notu kaydet'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Durum işlemleri',
                  child: _StatusActionsSection(
                    report: report,
                    isUpdating: state.isUpdating,
                    onActionSelected: (targetStatus) => _confirmAndUpdateStatus(
                      controller: controller,
                      targetStatus: targetStatus,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _canSaveNote(AdminProductReportDetail report, bool isUpdating) {
    if (isUpdating) return false;

    final trimmedDraft = _adminNoteController.text.trim();
    final trimmedExisting = report.adminNote?.trim() ?? '';
    if (trimmedDraft.isEmpty) return false;
    if (trimmedDraft.length > 2000) return false;

    return trimmedDraft != trimmedExisting;
  }

  Future<void> _saveNote(
    AdminProductReportDetailController controller,
    ProductReportStatus currentStatus,
  ) async {
    FocusScope.of(context).unfocus();
    await controller.updateReport(
      status: currentStatus,
      adminNote: _adminNoteController.text,
    );
  }

  Future<void> _confirmAndUpdateStatus({
    required AdminProductReportDetailController controller,
    required ProductReportStatus targetStatus,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (context) =>
          _StatusConfirmationSheet(targetStatus: targetStatus),
    );

    if (!mounted || confirmed != true) return;

    FocusScope.of(context).unfocus();
    await controller.updateReport(
      status: targetStatus,
      adminNote: _adminNoteController.text,
    );
  }

  void _popWithLatestReport() {
    if (_didPopWithResult) return;
    _didPopWithResult = true;

    final report = ref
        .read(adminProductReportDetailControllerProvider(widget.reportId))
        .report;

    context.pop(report);
  }

  void _openImagePreview({required String cacheId, required String imageUrl}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ImagePreviewPage(cacheId: cacheId, imageUrl: imageUrl),
      ),
    );
  }
}

class _SnapshotSection extends StatelessWidget {
  const _SnapshotSection({required this.report});

  final AdminProductReportDetail report;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ProductThumbnail(
                  productId: 'detail-report-snapshot-${report.id}',
                  imageUrl: report.productImageSnapshot,
                  accentColor: AppColors.primary,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (report.productBrandSnapshot?.trim().isNotEmpty == true)
                    Text(
                      report.productBrandSnapshot!.trim(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  Text(
                    report.productNameSnapshot,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _MetaRow(label: 'Bildirim türü', value: report.type.labelTr),
                  _MetaRow(
                    label: 'Gönderim tarihi',
                    value: formatTurkishDateTime(report.createdAt),
                  ),
                  _MetaRow(label: 'Durum', value: report.status.labelTr),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.report, required this.onImageTap});

  final AdminProductReportDetail report;
  final void Function({required String cacheId, required String imageUrl})
  onImageTap;

  @override
  Widget build(BuildContext context) {
    if (report.evidenceImageUrls.isEmpty) {
      return Text(
        'Kanıt görseli eklenmemiş.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var index = 0; index < report.evidenceImageUrls.length; index++)
          Semantics(
            label: 'Kanıt görseli ${index + 1}',
            button: true,
            child: InkWell(
              onTap: () => onImageTap(
                cacheId: 'report-evidence-${report.id}-$index',
                imageUrl: report.evidenceImageUrls[index],
              ),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 92,
                height: 92,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ProductThumbnail(
                    productId: 'report-evidence-${report.id}-$index',
                    imageUrl: report.evidenceImageUrls[index],
                    accentColor: AppColors.primary,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CurrentProductSection extends StatelessWidget {
  const _CurrentProductSection({required this.report});

  final AdminProductReportDetail report;

  @override
  Widget build(BuildContext context) {
    final currentProduct = report.currentProduct;
    if (currentProduct == null) {
      return Text(
        'Ürün mevcut veritabanında bulunamıyor.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 88,
          height: 88,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ProductThumbnail(
              productId: 'detail-current-product-${report.id}',
              imageUrl: currentProduct.imageUrl,
              accentColor: AppColors.primary,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                currentProduct.name?.trim().isNotEmpty == true
                    ? currentProduct.name!.trim()
                    : 'Ürün adı bulunmuyor',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (currentProduct.brand?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 6),
                _MetaRow(label: 'Marka', value: currentProduct.brand!.trim()),
              ],
              if (currentProduct.barcode?.trim().isNotEmpty == true)
                _MetaRow(
                  label: 'Barkod',
                  value: currentProduct.barcode!.trim(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusActionsSection extends StatelessWidget {
  const _StatusActionsSection({
    required this.report,
    required this.isUpdating,
    required this.onActionSelected,
  });

  final AdminProductReportDetail report;
  final bool isUpdating;
  final ValueChanged<ProductReportStatus> onActionSelected;

  @override
  Widget build(BuildContext context) {
    final actions = report.status.validAdminTransitions;

    if (actions.isEmpty) {
      return Text(
        'Bu bildirim için kullanılabilir durum işlemi yok.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final targetStatus in actions)
          Semantics(
            label: report.status.adminActionLabelFor(targetStatus),
            button: true,
            child: OutlinedButton(
              key: ValueKey(
                'admin-status-action-${report.id}-${targetStatus.databaseValue}',
              ),
              onPressed: isUpdating
                  ? null
                  : () => onActionSelected(targetStatus),
              child: Text(report.status.adminActionLabelFor(targetStatus)),
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        text: TextSpan(
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.textPrimary),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _DetailMessageState extends StatelessWidget {
  const _DetailMessageState({
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
        padding: const EdgeInsets.all(24),
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

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.dangerText),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusConfirmationSheet extends StatelessWidget {
  const _StatusConfirmationSheet({required this.targetStatus});

  final ProductReportStatus targetStatus;

  @override
  Widget build(BuildContext context) {
    final (title, description) = switch (targetStatus) {
      ProductReportStatus.resolved => (
        'Bildirim çözüldü olarak işaretlensin mi?',
        'Bu işlem ürün verisini otomatik olarak değiştirmez.',
      ),
      ProductReportStatus.rejected => ('Bildirim reddedilsin mi?', null),
      ProductReportStatus.reviewing => (
        'Bildirim incelemeye alınsın mı?',
        null,
      ),
      ProductReportStatus.pending => ('Bildirim beklemeye alınsın mı?', null),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (description != null) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Vazgeç'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Onayla'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({required this.cacheId, required this.imageUrl});

  final String cacheId;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final provider = buildProductThumbnailGridProvider(
      productId: cacheId,
      imageUrl: imageUrl,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Görsel'),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image(
            image: provider,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
