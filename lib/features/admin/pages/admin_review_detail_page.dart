import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/features/admin/controllers/submission_review_controller.dart';
import 'package:food_analyzer_app/features/admin/models/user_submission.dart';

class AdminReviewDetailPage extends ConsumerWidget {
  final String submissionId;
  final UserSubmission? submission;

  const AdminReviewDetailPage({
    super.key,
    required this.submissionId,
    this.submission,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(submissionReviewProvider);

    // Resolve from passed extra or find in loaded list.
    final item =
        submission ??
        state.submissions.valueOrNull
            ?.where((s) => s.id == submissionId)
            .firstOrNull;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Başvuru Detayı')),
        body: const Center(child: Text('Başvuru bulunamadı.')),
      );
    }

    final isBusy = state.isUpdating || state.isDraftCreating;

    return Scaffold(
      appBar: AppBar(title: const Text('Başvuru Detayı')),
      body: isBusy
          ? const Center(child: CircularProgressIndicator())
          : _DetailBody(item: item),
      bottomNavigationBar: isBusy ? null : _ActionBar(item: item),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final UserSubmission item;

  const _DetailBody({required this.item});

  @override
  Widget build(BuildContext context) {
    final local = item.createdAt.toLocal();
    final dateFormatted =
        '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoCard(
            children: [
              _FieldRow(label: 'Ürün Adı', value: item.productName ?? '—'),
              _FieldRow(label: 'Barkod', value: item.barcode ?? '—'),
              _FieldRow(label: 'Gönderim Tarihi', value: dateFormatted),
              _FieldRow(label: 'Durum', value: item.statusLabel),
              if (item.adminNote != null)
                _FieldRow(label: 'Admin Notu', value: item.adminNote!),
            ],
          ),
          if (item.frontImageUrl != null) ...[
            const SizedBox(height: 16),
            _SectionLabel(label: 'Ön Görsel'),
            const SizedBox(height: 8),
            _NetworkImageCard(url: item.frontImageUrl!),
          ],
          if (item.ingredientsImageUrl != null) ...[
            const SizedBox(height: 16),
            _SectionLabel(label: 'İçindekiler Görseli'),
            const SizedBox(height: 8),
            _NetworkImageCard(url: item.ingredientsImageUrl!),
          ],
          if (item.ocrText != null) ...[
            const SizedBox(height: 16),
            _SectionLabel(label: 'OCR Metni'),
            const SizedBox(height: 8),
            _TextCard(text: item.ocrText!),
          ],
          const SizedBox(height: 160), // space for bottom action bar
        ],
      ),
    );
  }
}

class _ActionBar extends ConsumerWidget {
  final UserSubmission item;

  const _ActionBar({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Submission status actions ──────────────────────────────────
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Onayla'),
              onPressed: () => _confirm(
                context,
                ref,
                title: 'Başvuruyu Onayla',
                content: 'Bu başvuruyu onaylamak istediğinize emin misiniz?',
                newStatus: 'approved',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: const BorderSide(color: Colors.blue),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.info_outline),
              label: const Text('Ek Bilgi Gerekli'),
              onPressed: () => _requestMoreInfo(context, ref),
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
              onPressed: () => _confirm(
                context,
                ref,
                title: 'Başvuruyu Reddet',
                content: 'Bu başvuruyu reddetmek istediğinize emin misiniz?',
                newStatus: 'rejected',
              ),
            ),

            // ── Product draft section ──────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Ürün İşlemleri',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Ürün Taslağı Oluştur'),
              onPressed: () => _createDraft(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status update helpers ────────────────────────────────────────────────

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String content,
    required String newStatus,
  }) async {
    final confirmed = await showDialog<bool>(
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
            child: Text(
              newStatus == 'approved' ? 'Onayla' : 'Reddet',
              style: TextStyle(
                color: newStatus == 'approved' ? Colors.green : Colors.red,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final success = await ref
        .read(submissionReviewProvider.notifier)
        .updateStatus(item.id, newStatus);

    if (!context.mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'approved'
                ? 'Başvuru onaylandı.'
                : 'Başvuru reddedildi.',
          ),
          backgroundColor: newStatus == 'approved' ? Colors.green : Colors.red,
        ),
      );
      Navigator.of(context).pop();
    } else {
      final error = ref.read(submissionReviewProvider).updateError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: ${error ?? 'Bilinmeyen hata'}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _requestMoreInfo(BuildContext context, WidgetRef ref) async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ek Bilgi Gerekli'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Kullanıcıya iletmek istediğiniz notu yazın (isteğe bağlı):',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Ek bilgi notu...',
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
            child: const Text('Gönder'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final adminNote = noteController.text.trim().isEmpty
        ? null
        : noteController.text.trim();

    final success = await ref
        .read(submissionReviewProvider.notifier)
        .updateStatus(item.id, 'needs_more_info', adminNote: adminNote);

    if (!context.mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ek bilgi talebi gönderildi.'),
          backgroundColor: Colors.blue,
        ),
      );
      Navigator.of(context).pop();
    } else {
      final error = ref.read(submissionReviewProvider).updateError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: ${error ?? 'Bilinmeyen hata'}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ── Draft creation helper ────────────────────────────────────────────────

  Future<void> _createDraft(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ürün Taslağı Oluştur'),
        content: const Text(
          'Bu başvurudan bir ürün taslağı oluşturulsun mu?\n\n'
          'Ürün "beklemede" durumunda eklenecek ve doğrulanmayacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final productId = await ref
        .read(submissionReviewProvider.notifier)
        .createProductDraft(item);

    if (!context.mounted) return;

    if (productId != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Taslak Oluşturuldu'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ürün taslağı başarıyla eklendi.'),
              const SizedBox(height: 8),
              Text(
                'Ürün ID: $productId',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Kapat'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (context.mounted) {
                  context.push('/product/$productId');
                }
              },
              child: const Text('Ürün Detayına Git'),
            ),
          ],
        ),
      );
    } else {
      final error = ref.read(submissionReviewProvider).draftCreateError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Taslak oluşturulamadı.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// ── Reusable layout helpers ──────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;

  const _FieldRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _NetworkImageCard extends StatelessWidget {
  final String url;

  const _NetworkImageCard({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (context, error, st) => Container(
          height: 100,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'Görsel yüklenemedi.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextCard extends StatelessWidget {
  final String text;

  const _TextCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
