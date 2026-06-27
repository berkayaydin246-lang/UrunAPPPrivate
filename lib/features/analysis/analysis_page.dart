import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_analyzer_app/features/analysis/controllers/analysis_controller.dart';
import 'package:food_analyzer_app/features/analysis/models/analysis_route_args.dart';
import 'package:food_analyzer_app/features/analysis/models/product_analysis_result.dart';
import 'package:food_analyzer_app/features/analysis/widgets/analysis_result_widget.dart';
import 'package:food_analyzer_app/features/ocr/controllers/ocr_controller.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  final AnalysisRouteArgs? routeArgs;

  const AnalysisScreen({super.key, this.routeArgs});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _triggerAnalysisIfNeeded();
  }

  @override
  void didUpdateWidget(covariant AnalysisScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeArgs != widget.routeArgs) {
      _started = false;
      _triggerAnalysisIfNeeded();
    }
  }

  void _triggerAnalysisIfNeeded() {
    if (_started) return;
    final args = widget.routeArgs;
    if (args == null || args.ocrText.trim().isEmpty) return;

    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(analysisNotifierProvider.notifier)
          .analyzeFromOcr(
            args.ocrText,
            category: args.category,
            structuredIngredients: args.structuredIngredients,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final analysisState = ref.watch(analysisNotifierProvider);
    final analysisNotifier = ref.read(analysisNotifierProvider.notifier);
    final ocrNotifier = ref.read(ocrProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('İçerik Analizi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: analysisState.isProcessing
            ? const _LoadingState()
            : analysisState.error != null
            ? _AnalysisErrorState(
                message: analysisState.error!,
                onRetry: () {
                  final text = widget.routeArgs?.ocrText.trim() ?? '';
                  if (text.isNotEmpty) {
                    analysisNotifier.analyzeFromOcr(
                      text,
                      category: widget.routeArgs?.category,
                      structuredIngredients:
                          widget.routeArgs?.structuredIngredients,
                    );
                  }
                },
                onReset: () {
                  analysisNotifier.reset();
                  ocrNotifier.reset();
                  context.goNamed('ocr');
                },
              )
            : _buildContent(
                context,
                analysisState,
                analysisNotifier,
                ocrNotifier,
              ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AnalysisState analysisState,
    AnalysisNotifier analysisNotifier,
    OcrNotifier ocrNotifier,
  ) {
    final result = analysisState.result;

    if (result == null) {
      final text = widget.routeArgs?.ocrText.trim() ?? '';
      return _EmptyState(
        title: 'Analiz için metin bekleniyor',
        message: text.isEmpty
            ? 'Önce içindekiler fotoğrafı çekip OCR metnini onayla.'
            : 'Analiz başlatılmadı. Devam etmek için tekrar dene.',
        onPrimary: text.isEmpty
            ? () {
                ocrNotifier.reset();
                context.goNamed('ocr');
              }
            : () {
                analysisNotifier.analyzeFromOcr(
                  text,
                  category: widget.routeArgs?.category,
                  structuredIngredients:
                      widget.routeArgs?.structuredIngredients,
                );
              },
        primaryLabel: text.isEmpty ? 'Tekrar Tara' : 'Analizi Başlat',
      );
    }

    final matchingResult = analysisState.matchingResult;
    final hasNoImportantOrNeutralMatches =
        matchingResult == null ||
        (result.detectedRiskIngredients.isEmpty &&
            result.otherRecognizedIngredients.isEmpty &&
            matchingResult.reviewRequiredCount == 0);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopSummaryCard(result: result),
          const SizedBox(height: 12),
          if (hasNoImportantOrNeutralMatches)
            _NoticeCard(
              icon: Icons.info_outline,
              title: 'Tespit edilen önemli içerik bulunamadı',
              message:
                  'Metindeki içerikler veritabanında bulunamadı veya risk açısından öne çıkan içerik tespit edilmedi. Metni düzeltip tekrar deneyebilirsin.',
            ),
          if (hasNoImportantOrNeutralMatches) const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AnalysisResultWidget(
                result: result,
                onLowConfidenceDecision: (originalToken, approved) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        approved
                            ? 'İçerik analize eklendi'
                            : 'İçerik analizden çıkarıldı',
                      ),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    ),
                  );
                  analysisNotifier.updateLowConfidenceDecision(
                    originalToken,
                    approved,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ActionButtons(
            onRescan: () {
              analysisNotifier.reset();
              ocrNotifier.reset();
              context.goNamed('ocr');
            },
            onHome: () {
              analysisNotifier.reset();
              ocrNotifier.reset();
              context.goNamed('home');
            },
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              'İçerikler analiz ediliyor...',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Lütfen bekleyin. İçerik eşleştirme ve değerlendirme yapılıyor.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  const _AnalysisErrorState({
    required this.message,
    required this.onRetry,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 72, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              'Analiz tamamlanamadı',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Tekrar Tara'),
                onPressed: onRetry,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.home),
                label: const Text('Ana Sayfa'),
                onPressed: onReset,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onPrimary;
  final String primaryLabel;

  const _EmptyState({
    required this.title,
    required this.message,
    required this.onPrimary,
    required this.primaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 72,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopSummaryCard extends StatelessWidget {
  final ProductAnalysisResult result;

  const _TopSummaryCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final scoreColor = scoreLabelColor(result.scoreLabel);
    final statusText = switch (result.scoreLabel) {
      AnalysisScoreLabel.iyiSecim => 'Genel Olarak Uygun',
      AnalysisScoreLabel.orta => 'Dengeye Dikkat',
      AnalysisScoreLabel.dikkatliTuket => 'Dikkat Gerektirir',
      AnalysisScoreLabel.sikTuketme => 'Sıklığı Sınırla',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Genel Değerlendirme',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: scoreColor.withValues(alpha: 0.18)),
            ),
            child: Text(
              statusText,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scoreColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            result.summary,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatChip(
                label: 'Tespit edilen',
                value: '${result.recognizedIngredients.length}',
              ),
              _StatChip(
                label: 'Öne çıkan',
                value: '${result.detectedRiskIngredients.length}',
              ),
              if (result.reviewRequiredMatches.isNotEmpty)
                _StatChip(
                  label: 'Emin olunamayan',
                  value: '${result.reviewRequiredMatches.length}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.amber[800]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onRescan;
  final VoidCallback onHome;

  const _ActionButtons({required this.onRescan, required this.onHome});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onRescan,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Tekrar Tara'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onHome,
            icon: const Icon(Icons.home),
            label: const Text('Ana Sayfa'),
          ),
        ),
      ],
    );
  }
}
