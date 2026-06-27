import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_analyzer_app/features/admin/controllers/product_submission_review_controller.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_submission_approval_repository.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';

class ProductSubmissionDetailPage extends ConsumerStatefulWidget {
  final String submissionId;
  final ProductSubmission? submission;

  const ProductSubmissionDetailPage({
    super.key,
    required this.submissionId,
    this.submission,
  });

  @override
  ConsumerState<ProductSubmissionDetailPage> createState() =>
      _ProductSubmissionDetailPageState();
}

class _ProductSubmissionDetailPageState
    extends ConsumerState<ProductSubmissionDetailPage> {
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _ingredientsController = TextEditingController();

  ProductSubmission? _resolved;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _ingredientsController.dispose();
    super.dispose();
  }

  void _resolve() {
    // Try from passed extra first, then from loaded list.
    final fromExtra = widget.submission;
    final fromList = ref
        .read(productSubmissionReviewProvider)
        .submissions
        .valueOrNull
        ?.where((s) => s.id == widget.submissionId)
        .firstOrNull;

    final resolved = fromExtra ?? fromList;
    if (resolved != null) {
      _populate(resolved);
    } else {
      // Fetch directly (deep link / page refresh).
      _fetchFromDb();
    }
  }

  Future<void> _fetchFromDb() async {
    final sub = await const ProductSubmissionApprovalRepository().fetchById(
      widget.submissionId,
    );
    if (!mounted) return;
    if (sub != null) _populate(sub);
    setState(() => _loaded = true);
  }

  void _populate(ProductSubmission sub) {
    _resolved = sub;
    _nameController.text = sub.productName ?? '';
    _brandController.text = sub.brand ?? '';
    _ingredientsController.text = sub.extractedIngredientsText ?? '';
    _loaded = true;
  }

  // ── actions ───────────────────────────────────────────────────────────────

  Future<void> _approve() async {
    final confirmed = await _confirmDialog(
      title: 'Ürünü Onayla',
      content: 'Bu gönderi onaylanacak ve ürün veritabanına eklenecek.',
      actionLabel: 'Onayla',
      actionColor: Colors.green,
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(productSubmissionReviewProvider.notifier)
        .approve(
          widget.submissionId,
          editedProductName: _nameController.text.trim(),
          editedBrand: _brandController.text.trim(),
          editedIngredientsText: _ingredientsController.text.trim(),
        );

    if (!mounted) return;

    if (result != null) {
      final msg = switch (result) {
        ApproveProductResult.approved => 'Ürün veritabanına eklendi.',
        ApproveProductResult.updatedExisting =>
          'Mevcut ürün eksik alanlarla güncellendi.',
        _ => 'İşlem tamamlandı.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } else {
      final error = ref.read(productSubmissionReviewProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: ${error ?? 'Bilinmeyen hata'}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _reject() async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reddet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Red sebebi (isteğe bağlı):'),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Açıklama...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reddet', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(productSubmissionReviewProvider.notifier)
        .reject(
          widget.submissionId,
          reason: noteController.text.trim().isEmpty
              ? null
              : noteController.text.trim(),
        );

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gönderi reddedildi.'),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.of(context).pop();
    } else {
      final error = ref.read(productSubmissionReviewProvider).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: ${error ?? 'Bilinmeyen hata'}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool?> _confirmDialog({
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

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productSubmissionReviewProvider);
    final isBusy = state.isProcessing;

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gönderi Detayı')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_resolved == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gönderi Detayı')),
        body: const Center(child: Text('Gönderi bulunamadı.')),
      );
    }

    final sub = _resolved!;

    return Scaffold(
      appBar: AppBar(title: const Text('Gönderi Detayı')),
      body: isBusy
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Barcode (read-only)
                  _SectionLabel('Barkod'),
                  const SizedBox(height: 6),
                  _ReadOnlyField(sub.barcode),
                  const SizedBox(height: 16),

                  // OCR helper notice
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      'OCR sonucu otomatik çıkarılmıştır. '
                      'Onaylamadan önce kontrol edip düzeltebilirsiniz.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Editable product name
                  _SectionLabel('Ürün Adı'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Ürün adı',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Editable brand
                  _SectionLabel('Marka'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _brandController,
                    decoration: const InputDecoration(
                      hintText: 'Marka',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Editable ingredients
                  _SectionLabel('İçindekiler (OCR)'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _ingredientsController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Çıkarılan içerik metni...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Nutrition (read-only JSON — passed as-is on approve)
                  if (sub.extractedNutrition != null) ...[
                    _SectionLabel('Besin Değerleri (OCR)'),
                    const SizedBox(height: 6),
                    _NutritionCard(nutrition: sub.extractedNutrition!),
                    const SizedBox(height: 16),
                  ],

                  // Extraction status
                  _ExtractionStatusCard(
                    status: sub.extractionStatus,
                    error: sub.extractionError,
                  ),
                  const SizedBox(height: 16),

                  // Front image
                  if (sub.frontImageUrl != null) ...[
                    _SectionLabel('Ön Görsel'),
                    const SizedBox(height: 8),
                    _ImageCard(url: sub.frontImageUrl!),
                    const SizedBox(height: 16),
                  ],

                  // Label image
                  if (sub.labelImageUrl != null) ...[
                    _SectionLabel('Etiket Görseli'),
                    const SizedBox(height: 8),
                    _ImageCard(url: sub.labelImageUrl!),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: isBusy
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Onayla'),
                      onPressed: _approve,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Reddet'),
                      onPressed: _reject,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String value;
  const _ReadOnlyField(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _NutritionCard extends StatelessWidget {
  final Map<String, dynamic> nutrition;
  const _NutritionCard({required this.nutrition});

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
      final value = nutrition[key];
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                value.toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    if (rows.isEmpty) {
      rows.add(
        Text(
          jsonEncode(nutrition),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

class _ExtractionStatusCard extends StatelessWidget {
  final String status;
  final String? error;
  const _ExtractionStatusCard({required this.status, this.error});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'success' => ('OCR başarılı', Colors.green),
      'failed' => ('OCR başarısız', Colors.red),
      'pending' => ('Otomatik okuma devam ediyor.', Colors.orange),
      _ => ('Otomatik okuma yapılmadı.', Colors.grey),
    };

    // Only show the error message when extraction actually failed.
    // A successful re-extraction may leave a stale error string in the DB;
    // displaying it alongside "OCR başarılı" would be misleading.
    final showError = status == 'failed';
    final errorMessage = showError
        ? (error?.trim().isNotEmpty == true
              ? error!
              : 'Otomatik okuma başarısız oldu.')
        : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Çıkarma Durumu: $label',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: color,
              fontSize: 13,
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 4),
            Text(
              errorMessage,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.red[700]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String url;
  const _ImageCard({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (_, _, _) => Container(
          height: 120,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(child: Text('Görsel yüklenemedi.')),
        ),
      ),
    );
  }
}
