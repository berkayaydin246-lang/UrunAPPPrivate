import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/admin/controllers/product_staging_review_controller.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_staging_approval_repository.dart';
import 'package:food_analyzer_app/features/product_staging/models/product_candidate.dart';
import 'package:food_analyzer_app/features/search/controllers/filtered_search_controller.dart';
import 'package:food_analyzer_app/features/search/controllers/search_controller.dart';

class ProductStagingDetailPage extends ConsumerStatefulWidget {
  final String stagingId;
  final ProductCandidate? candidate;

  const ProductStagingDetailPage({
    super.key,
    required this.stagingId,
    this.candidate,
  });

  @override
  ConsumerState<ProductStagingDetailPage> createState() =>
      _ProductStagingDetailPageState();
}

class _ProductStagingDetailPageState
    extends ConsumerState<ProductStagingDetailPage> {
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _categoryController = TextEditingController();
  final _adminNotesController = TextEditingController();

  ProductCandidate? _resolved;
  bool _loaded = false;
  bool _rawExpanded = false;

  @override
  void initState() {
    super.initState();
    // Refresh the suspicious-ingredients warning banner as the admin edits.
    _ingredientsController.addListener(() {
      if (mounted) setState(() {});
    });
    _resolve();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _ingredientsController.dispose();
    _categoryController.dispose();
    _adminNotesController.dispose();
    super.dispose();
  }

  void _resolve() {
    final fromExtra = widget.candidate;
    final fromList = ref
        .read(productStagingReviewProvider)
        .candidates
        .valueOrNull
        ?.where((c) => c.id == widget.stagingId)
        .firstOrNull;
    final resolved = fromExtra ?? fromList;
    if (resolved != null) {
      _populate(resolved);
    } else {
      _fetchFromDb();
    }
  }

  Future<void> _fetchFromDb() async {
    final sub = await const ProductStagingApprovalRepository()
        .fetchStagedProductById(widget.stagingId);
    if (!mounted) return;
    if (sub != null) _populate(sub);
    setState(() => _loaded = true);
  }

  void _populate(ProductCandidate c) {
    _resolved = c;
    _nameController.text = c.name ?? '';
    _brandController.text = c.brand ?? '';
    _ingredientsController.text = c.ingredientsText ?? '';
    _categoryController.text = c.categorySuggestion ?? '';
    _adminNotesController.text = c.adminNotes ?? '';
    _loaded = true;
  }

  // ── actions ──────────────────────────────────────────────────────────────

  /// Returns warning labels for recommended fields that are currently missing.
  ///
  /// Uses the live controller values so the admin sees up-to-date warnings as
  /// they fill in fields. Barcode is always included when absent (informational).
  List<String> _missingDataLabels() {
    if (_resolved == null) return [];
    final c = _resolved!;
    final edits = StagingApprovalEdits(
      name: _nameController.text.trim(),
      brand: _brandController.text.trim(),
      ingredientsText: _ingredientsController.text.trim(),
    );
    final warnings = ProductStagingApprovalRepository.approvalWarnings(
      c,
      edits,
    );
    return [
      if (warnings.contains(ApproveStagedResult.missingNutrition))
        'Besin değeri eksik',
      if (warnings.contains(ApproveStagedResult.missingIngredients))
        'İçindekiler eksik',
      if (warnings.contains(ApproveStagedResult.missingImage)) 'Görsel eksik',
      if (warnings.contains(ApproveStagedResult.missingBrand)) 'Marka eksik',
      if (c.barcode == null || c.barcode!.trim().isEmpty) 'Barkod yok',
    ];
  }

  Future<void> _approve() async {
    final missingLabels = _missingDataLabels();
    final hasSignificantGap = missingLabels.isNotEmpty;
    final confirmed = await _confirm(
      title: 'Ürünü Onayla',
      content: hasSignificantGap
          ? 'Bu ürün eksik bilgilerle eklenecek. '
                'Eksik alanlar sonradan tamamlanabilir.\n\n'
                'Eksik: ${missingLabels.join(', ')}'
          : 'Bu staged ürün onaylanacak ve products tablosuna eklenecek.',
      actionLabel: 'Onayla',
      actionColor: AppColors.success,
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(productStagingReviewProvider.notifier)
        .approve(
          widget.stagingId,
          edits: StagingApprovalEdits(
            name: _nameController.text.trim(),
            brand: _brandController.text.trim(),
            ingredientsText: _ingredientsController.text.trim(),
            categorySuggestion: _categoryController.text.trim(),
            adminNote: _adminNotesController.text.trim(),
          ),
        );

    if (!mounted) return;
    if (result != null) {
      final msg = switch (result) {
        ApproveStagedResult.approved => 'Ürün veritabanına eklendi.',
        ApproveStagedResult.updatedExisting =>
          'Mevcut ürün eksik alanlarla güncellendi.',
        ApproveStagedResult.productSavedStagingFailed =>
          'Ürün eklendi ancak staging durumu güncellenemedi.',
        ApproveStagedResult.invalidBarcode =>
          'Barkod olmadığı için onaylanamadı.',
        ApproveStagedResult.insufficientData =>
          'Ürün adı veya kaynak bağlantısı eksik olduğu için onaylanamaz.',
        ApproveStagedResult.autoRejectedNoAnalysisData =>
          'İçindekiler ve besin değerleri eksik olduğu için otomatik reddedildi.',
        // These four are informational warnings, never returned as hard blocks.
        ApproveStagedResult.missingBrand =>
          'Marka bilgisi eksik; ürün sonradan zenginleştirilebilir.',
        ApproveStagedResult.missingImage =>
          'Görsel eksik; ürün sonradan zenginleştirilebilir.',
        ApproveStagedResult.missingIngredients =>
          'İçindekiler bilgisi eksik; ürün sonradan zenginleştirilebilir.',
        ApproveStagedResult.missingNutrition =>
          'Besin değerleri eksik; ürün sonradan zenginleştirilebilir.',
        ApproveStagedResult.missingSourceLink =>
          'Barkod veya kaynak bağlantısı olmadığı için ürün güvenli şekilde eşleştirilemedi.',
        ApproveStagedResult.notFound => 'Staging kaydı bulunamadı.',
        ApproveStagedResult.alreadyProcessed => 'Bu kayıt zaten işlenmiş.',
      };
      final ok = result.stagingWasApproved;
      final warning = result == ApproveStagedResult.productSavedStagingFailed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: ok
              ? AppColors.success
              : (warning
                    ? AppColors.warning
                    : Theme.of(context).colorScheme.error),
        ),
      );
      // Refresh search providers so the newly approved product appears
      // immediately when the user switches back to the Search tab.
      if (ok) {
        ref.invalidate(activeSearchProvider);
        ref.read(filteredSearchProvider.notifier).refresh();
      }
      // Pop only on full success; on staging-update failure keep the page open
      // so the admin can retry.
      if (ok) Navigator.of(context).pop();
    } else {
      _showError();
    }
  }

  Future<void> _reject() async {
    final note = await _promptNote(title: 'Reddet', hint: 'Red sebebi...');
    if (note == null || !mounted) return;
    final ok = await ref
        .read(productStagingReviewProvider.notifier)
        .reject(widget.stagingId, note);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staging kaydı reddedildi.'),
          backgroundColor: AppColors.danger,
        ),
      );
      Navigator.of(context).pop();
    } else {
      _showError();
    }
  }

  Future<void> _needsReview() async {
    final note = await _promptNote(
      title: 'İnceleme Gerekli',
      hint: 'İnceleme notu...',
    );
    if (note == null || !mounted) return;
    final ok = await ref
        .read(productStagingReviewProvider.notifier)
        .markNeedsReview(widget.stagingId, note);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İnceleme gerekli olarak işaretlendi.')),
      );
      Navigator.of(context).pop();
    } else {
      _showError();
    }
  }

  void _showError() {
    final error = ref.read(productStagingReviewProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Hata: ${error ?? 'Bilinmeyen hata'}'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String content,
    required String actionLabel,
    required Color actionColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel, style: TextStyle(color: actionColor)),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptNote({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    return controller.text.trim();
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isBusy = ref.watch(productStagingReviewProvider).isProcessing;
    final isAutoReject =
        _resolved != null &&
        ProductStagingApprovalRepository.shouldAutoRejectForNoAnalysisData(
          _resolved!,
        );

    if (!_loaded) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Staging Detayı')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_resolved == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Staging Detayı')),
        body: const Center(child: Text('Kayıt bulunamadı.')),
      );
    }

    final c = _resolved!;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Staging Detayı')),
      body: isBusy
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 140),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('Barkod (salt okunur)'),
                  _readonly(c.barcode ?? 'Yok'),
                  const SizedBox(height: 16),

                  _label('Ürün Adı'),
                  _editable(_nameController, 'Ürün adı'),
                  const SizedBox(height: 16),

                  _label('Marka'),
                  _editable(_brandController, 'Marka'),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _infoCard(
                          'Kalite Skoru',
                          '${c.qualityScore}/100',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: _infoCard('Kaynak', c.source)),
                    ],
                  ),
                  // Hard rejection: no ingredients AND no nutrition → no
                  // analyzable data, approve button is disabled.
                  if (isAutoReject) ...[
                    const SizedBox(height: 10),
                    _errorBanner(
                      'İçindekiler ve besin değerleri olmadığı için '
                      'bu ürün onaylanamaz ve otomatik olarak reddedilecek.',
                    ),
                  ],
                  // Non-blocking review hints: a low score or a suspicious
                  // ingredients text warns the admin but never disables the
                  // approve button — completeness of the (edited) fields is
                  // what decides approvability.
                  if (c.qualityScore < 100) ...[
                    const SizedBox(height: 10),
                    _warningBanner(
                      'Kalite skoru düşük; lütfen alanları kontrol edin.',
                    ),
                  ],
                  if (ProductStagingApprovalRepository.isSuspiciousIngredients(
                    _ingredientsController.text,
                  )) ...[
                    const SizedBox(height: 8),
                    _warningBanner(
                      'İçindekiler metni kısa veya şüpheli görünüyor.',
                    ),
                  ],
                  // Non-blocking missing-field warning chips.
                  // These are advisory only; the admin can still approve.
                  Builder(
                    builder: (_) {
                      final labels = _missingDataLabels();
                      if (labels.isEmpty) return const SizedBox.shrink();
                      final hasNutritionOrIngredients = labels.any(
                        (l) => l.contains('Besin') || l.contains('İçindekiler'),
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          if (hasNutritionOrIngredients)
                            _warningBanner(
                              'Bu ürün eksik bilgilerle eklenecek. '
                              'Eksik alanlar sonradan tamamlanabilir.',
                            ),
                          const SizedBox(height: 8),
                          _label('Eksik Alanlar'),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: labels
                                .map(
                                  (l) => Chip(
                                    label: Text(
                                      l,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.warningText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    backgroundColor: AppColors.warningBg,
                                    side: BorderSide(
                                      color: AppColors.warning.withValues(
                                        alpha: 0.24,
                                      ),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      );
                    },
                  ),
                  if (c.sourceUrl != null) ...[
                    const SizedBox(height: 12),
                    _label('Kaynak URL'),
                    _readonly(c.sourceUrl!),
                  ],
                  const SizedBox(height: 16),

                  if (c.displayImageUrl != null) ...[
                    _label('Ön Görsel'),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      child: Container(
                        height: 220,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Image.network(
                          c.displayImageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.surfaceSoft,
                            child: const Center(
                              child: Text('Görsel yüklenemedi.'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  _label('İçindekiler'),
                  _editable(
                    _ingredientsController,
                    'İçindekiler metni...',
                    maxLines: 5,
                  ),
                  const SizedBox(height: 16),

                  if (c.nutrition != null) ...[
                    _label('Besin Değerleri'),
                    const SizedBox(height: 6),
                    _NutritionCard(nutritionJson: c.nutritionJson!),
                    const SizedBox(height: 16),
                  ],

                  _label('Kategori Önerisi'),
                  _editable(_categoryController, 'Kategori önerisi'),
                  if (c.categoryTags != null && c.categoryTags!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: c.categoryTags!
                          .take(12)
                          .map(
                            (t) => Chip(
                              label: Text(
                                t,
                                style: const TextStyle(fontSize: 10),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 16),

                  _label('Admin Notu'),
                  _editable(_adminNotesController, 'Not...', maxLines: 2),
                  const SizedBox(height: 16),

                  if (c.rawSourcePayload != null)
                    _RawPayloadSection(
                      payload: c.rawSourcePayload!,
                      expanded: _rawExpanded,
                      onToggle: () =>
                          setState(() => _rawExpanded = !_rawExpanded),
                    ),
                ],
              ),
            ),
      bottomNavigationBar: isBusy
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAutoReject
                            ? AppColors.neutral
                            : AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Onayla'),
                      onPressed: isAutoReject ? null : _approve,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF8B5CF6),
                              side: const BorderSide(color: Color(0xFF8B5CF6)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.flag_outlined),
                            label: const Text('İnceleme Gerekli'),
                            onPressed: _needsReview,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Reddet'),
                            onPressed: _reject,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w800,
    ),
  );

  Widget _editable(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint, isDense: true),
      ),
    );
  }

  Widget _readonly(String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
      ),
    );
  }

  Widget _infoCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Red, hard-block banner (auto-reject conditions).
  Widget _errorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.block_outlined, size: 16, color: AppColors.danger),
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

  /// Orange, non-blocking review hint (low score / suspicious ingredients).
  Widget _warningBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            size: 16,
            color: AppColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.warningText),
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionCard extends StatelessWidget {
  final Map<String, dynamic> nutritionJson;
  const _NutritionCard({required this.nutritionJson});

  static const _labels = {
    'energy_kcal': 'Enerji (kcal)',
    'fat': 'Yağ (g)',
    'saturated_fat': 'Doymuş Yağ (g)',
    'carbohydrates': 'Karbonhidrat (g)',
    'sugars': 'Şeker (g)',
    'fiber': 'Lif (g)',
    'proteins': 'Protein (g)',
    'salt': 'Tuz (g)',
    'sodium': 'Sodyum (g)',
    'serving_size': 'Porsiyon',
  };

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (final key in _labels.keys) {
      final value = nutritionJson[key];
      if (value == null) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _labels[key]!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                value.toString(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows.isEmpty ? [const Text('—')] : rows,
      ),
    );
  }
}

class _RawPayloadSection extends StatelessWidget {
  final Map<String, dynamic> payload;
  final bool expanded;
  final VoidCallback onToggle;

  const _RawPayloadSection({
    required this.payload,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            children: [
              Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
              const SizedBox(width: 4),
              Text(
                'Ham Kaynak Verisi (debug)',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (expanded)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceSoft,
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              const JsonEncoder.withIndent('  ').convert(payload),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
      ],
    );
  }
}
