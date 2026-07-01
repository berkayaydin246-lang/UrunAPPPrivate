import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/features/analysis/models/analysis_route_args.dart';
import 'package:food_analyzer_app/features/ocr/controllers/ocr_controller.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';
import 'package:food_analyzer_app/features/ocr/widgets/ocr_text_editor.dart';

// Set --dart-define=SHOW_OCR_DEBUG_JSON=true to reveal the raw JSON panel
// in debug builds. Never shown in profile or release builds.
const bool _showOcrDebugJson = bool.fromEnvironment('SHOW_OCR_DEBUG_JSON');

/// OCR flow for Turkish packaged food labels.
///
/// CRITICAL: User editable correction is MANDATORY. This screen must always
/// allow users to review and manually correct OCR output before analysis.
/// False ingredient text can lead to incorrect health analysis.
///
/// Flow:
/// 1. Capture/pick image
/// 2. Local ML Kit OCR (fast, offline)
/// 3. Quality evaluation
/// 4. If low quality: offer server fallback (if available)
/// 5. User correction (required)
/// 6. Proceed to ingredient analysis
class OcrScreen extends ConsumerWidget {
  const OcrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ocrState = ref.watch(ocrProvider);
    final ocrNotifier = ref.read(ocrProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('İçindekileri Tara'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ocrNotifier.reset();
            context.pop();
          },
        ),
      ),
      body: _buildBody(context, ref, ocrState, ocrNotifier),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    OcrState ocrState,
    OcrNotifier ocrNotifier,
  ) {
    if (ocrState.isBusy) {
      final isRemote = ocrState.isUploading || ocrState.isRemoteProcessing;
      return _LoadingView(
        message: isRemote
            ? 'Gelişmiş OCR işleniyor...'
            : 'Metin tanımlanıyor...',
        subMessage: isRemote
            ? 'Fotoğraf sunucuya gönderiliyor ve daha net metin çıkarılıyor.'
            : 'Lütfen bekleyin. OCR işlemi yapılıyor.',
      );
    }

    if (ocrState.hasError) {
      return _ErrorView(
        message: ocrState.error ?? 'Bilinmeyen bir hata oluştu',
        onRetry: () => ocrNotifier.retryOcr(),
        onReset: () => ocrNotifier.retakeImage(),
      );
    }

    if (!ocrState.hasImage) {
      return _CaptureIntro(
        onCamera: () async => ocrNotifier.captureImageFromCamera(),
        onGallery: () async => ocrNotifier.pickImageFromGallery(),
        onOpenCropHelp: () => _showCropHelp(context),
      );
    }

    if (ocrState.hasExtractedText) {
      return _OcrResultView(
        ocrState: ocrState,
        onRetake: () => ocrNotifier.retakeImage(),
        onProductionOcr: () =>
            ocrNotifier.processCurrentImageWithProductionOcr(),
        onEditText: () => _showEditDialog(context, ocrState, ocrNotifier),
        onContinue: () {
          final hasStructuredExtraction =
              ocrState.hasStructuredExtractionResult;
          final text = ocrState.editableText ?? '';
          final structuredNames = ocrState
              .structuredExtractionResult
              ?.ingredients
              .map((item) => item.name.trim())
              .where((name) => name.isNotEmpty)
              .toList(growable: false);
          if (hasStructuredExtraction && text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Gelişmiş OCR sonucu doğrulanamadı. Lütfen metni düzenle veya Hızlı OCR kullan.',
                ),
              ),
            );
            return;
          }
          if (text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('İçindekiler metni boş olamaz.')),
            );
            return;
          }

          context.push(
            '/analysis',
            extra: AnalysisRouteArgs(
              ocrText: text,
              structuredIngredients: structuredNames,
            ),
          );
        },
      );
    }

    return _OcrPreviewView(
      imageFile: File(ocrState.imageFile!.path),
      onStartOcr: () => ocrNotifier.processCurrentImage(),
      onStartProductionOcr: () =>
          ocrNotifier.processCurrentImageWithProductionOcr(),
      warningMessage: ocrState.remoteError,
      onRetake: () => ocrNotifier.retakeImage(),
      onOpenCropHelp: () => _showCropHelp(context),
    );
  }

  void _showEditDialog(
    BuildContext context,
    OcrState ocrState,
    OcrNotifier ocrNotifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: OcrTextEditor(
            initialText:
                ocrState.editableText ?? ocrState.extractedText?.text ?? '',
            onSave: ocrNotifier.updateEditableText,
            onCancel: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }

  void _showCropHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kırpma Yardımı'),
        content: const Text(
          'Şimdilik yalnızca içindekiler bölümünü kadraja almaya çalış.\n\n'
          'İpucu:\n'
          '• Yazının tamamı kadrajda olsun\n'
          '• Işığın yansımamasına dikkat et\n'
          '• Fotoğrafı mümkün olduğunca net çek',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

class _CaptureIntro extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onOpenCropHelp;

  const _CaptureIntro({
    required this.onCamera,
    required this.onGallery,
    required this.onOpenCropHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              'İçindekiler Fotoğrafını Çek',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Ürünün içindekiler kısmının net bir fotoğrafını çekin veya yükleyin',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            const _GuidanceCard(),
            const SizedBox(height: 16),
            _CropHintCard(onOpenHelp: onOpenCropHelp),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('Kameradan Çek'),
                onPressed: onCamera,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('Galeriden Seç'),
                onPressed: onGallery,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Çekim İpuçları',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const _BulletLine(text: 'Yazının tamamı kadrajda olsun'),
          const _BulletLine(text: 'Işığın yansımamasına dikkat et'),
          const _BulletLine(text: 'Fotoğrafı mümkün olduğunca net çek'),
        ],
      ),
    );
  }
}

class _CropHintCard extends StatelessWidget {
  final VoidCallback onOpenHelp;

  const _CropHintCard({required this.onOpenHelp});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.crop, color: Colors.grey[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kırpma rehberi',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Şimdilik yalnızca içindekiler kısmını yakınlaştırmaya çalış.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onOpenHelp,
                  child: const Text('Kırpma Yardımı'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OcrPreviewView extends StatelessWidget {
  final File imageFile;
  final VoidCallback onStartOcr;
  final VoidCallback onStartProductionOcr;
  final String? warningMessage;
  final VoidCallback onRetake;
  final VoidCallback onOpenCropHelp;

  const _OcrPreviewView({
    required this.imageFile,
    required this.onStartOcr,
    required this.onStartProductionOcr,
    this.warningMessage,
    required this.onRetake,
    required this.onOpenCropHelp,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fotoğraf Önizleme',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 240,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(imageFile, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blueGrey[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blueGrey[100]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kontrol etmeden önce',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const _BulletLine(text: 'Yazının tamamı kadrajda olsun'),
                const _BulletLine(text: 'Işığın yansımamasına dikkat et'),
                const _BulletLine(text: 'Fotoğrafı mümkün olduğunca net çek'),
              ],
            ),
          ),
          if (warningMessage != null) ...[
            const SizedBox(height: 12),
            _WarningCard(
              message: 'Gelişmiş OCR tamamlanamadı.',
              subMessage: warningMessage!,
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Hızlı OCR'),
              onPressed: onStartOcr,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Gelişmiş OCR ile Tara'),
              onPressed: onStartProductionOcr,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.crop),
              label: const Text('Kırpma Yardımı'),
              onPressed: onOpenCropHelp,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Çek'),
              onPressed: onRetake,
            ),
          ),
        ],
      ),
    );
  }
}

class _OcrResultView extends StatelessWidget {
  final OcrState ocrState;
  final VoidCallback onRetake;
  final VoidCallback onProductionOcr;
  final VoidCallback onEditText;
  final VoidCallback onContinue;

  const _OcrResultView({
    required this.ocrState,
    required this.onRetake,
    required this.onProductionOcr,
    required this.onEditText,
    required this.onContinue,
  });

  static String _resultLabel(OcrTextResult result, {required bool isAdvanced}) {
    final title = isAdvanced ? 'Gelişmiş OCR sonucu' : 'Okunan metin';
    if (result.confidence <= 0) {
      return '$title — Güven skoru hesaplanamadı';
    }
    return '$title (${result.confidence}% güvenilirlik)';
  }

  @override
  Widget build(BuildContext context) {
    final extractedText = ocrState.extractedText!;
    final isAdvanced = ocrState.hasStructuredExtractionResult;
    // Guard: never show JSON or fenced content to the user.
    final rawCandidate = ocrState.editableText ?? extractedText.text;
    final trimmed = rawCandidate.trimLeft();
    final displayText =
        (trimmed.startsWith('{') ||
            trimmed.startsWith('[') ||
            trimmed.startsWith('`'))
        ? ''
        : rawCandidate;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fotoğraf Önizleme',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (ocrState.imageFile != null)
            Container(
              width: double.infinity,
              height: 220,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(ocrState.imageFile!.path),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (ocrState.isLowQualityText && !isAdvanced)
            Column(
              children: [
                _WarningCard(
                  message: 'Türkçe metin daha iyi okunabilir.',
                  subMessage:
                      'Tekrar fotoğraf çekebilir ya da gelişmiş OCR deneyebilirsin.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tekrar Fotoğraf Çek'),
                        onPressed: onRetake,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Gelişmiş OCR ile Tara'),
                        onPressed: onProductionOcr,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          if (ocrState.hasRemoteError) ...[
            const SizedBox(height: 12),
            _WarningCard(
              message: 'Sunucuda daha iyi tarama başarısız oldu.',
              subMessage: ocrState.remoteError ?? 'Lütfen tekrar dene.',
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Colors.green[700],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _resultLabel(extractedText, isAdvanced: isAdvanced),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  displayText,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
          if (kDebugMode && _showOcrDebugJson && isAdvanced) ...[
            const SizedBox(height: 8),
            _DebugJsonSection(result: ocrState.structuredExtractionResult!),
          ],
          const SizedBox(height: 8),
          Text(
            'Metni kontrol edip gerekli düzeltmeleri yapabilirsin',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: const Text('Metni elle düzenle'),
              onPressed: onEditText,
            ),
          ),
          if (ocrState.shouldOfferServerFallback && !isAdvanced) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Gelişmiş OCR ile Tara'),
                onPressed: onProductionOcr,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('İçeriği Analiz Et'),
              onPressed: onContinue,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Fotoğraf Çek'),
              onPressed: onRetake,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  final String message;
  final String subMessage;

  const _WarningCard({required this.message, required this.subMessage});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.amber[800]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(subMessage, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  final String message;
  final String subMessage;

  const _LoadingView({required this.message, required this.subMessage});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              subMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 24),
            Text(
              'Metin Tanımlanamadı',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
              onPressed: onRetry,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Çek'),
              onPressed: onReset,
            ),
          ],
        ),
      ),
    );
  }
}

class _BulletLine extends StatelessWidget {
  final String text;

  const _BulletLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.blueGrey[700],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Collapsible raw-JSON panel — only shown in debug builds.
class _DebugJsonSection extends StatefulWidget {
  final StructuredIngredientExtractionResult result;

  const _DebugJsonSection({required this.result});

  @override
  State<_DebugJsonSection> createState() => _DebugJsonSectionState();
}

class _DebugJsonSectionState extends State<_DebugJsonSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.code, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Teknik JSON',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                widget.result.toJson().toString(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: Colors.grey[700],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
