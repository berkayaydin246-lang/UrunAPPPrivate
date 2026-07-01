import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/ocr/controllers/ocr_controller.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_engine_type.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_repository.dart';

class OcrBenchmarkPage extends ConsumerStatefulWidget {
  const OcrBenchmarkPage({super.key});

  @override
  ConsumerState<OcrBenchmarkPage> createState() => _OcrBenchmarkPageState();
}

class _OcrBenchmarkPageState extends ConsumerState<OcrBenchmarkPage> {
  final ImagePicker _imagePicker = ImagePicker();

  XFile? _imageFile;
  bool _isRunning = false;
  String? _error;
  OcrEngineType _remoteEngine = OcrEngineType.paddleOcr;
  OcrRecognitionResult? _localResult;
  OcrRecognitionResult? _remoteResult;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (pickedFile == null) {
        return;
      }

      setState(() {
        _imageFile = pickedFile;
        _error = null;
        _localResult = null;
        _remoteResult = null;
      });
    } catch (_) {
      setState(() {
        _error = 'Görsel seçilemedi. Lütfen tekrar deneyin.';
      });
    }
  }

  Future<void> _runBenchmark() async {
    final imageFile = _imageFile;
    if (imageFile == null) {
      setState(() {
        _error = 'Önce bir görsel seçin.';
      });
      return;
    }

    setState(() {
      _isRunning = true;
      _error = null;
      _localResult = null;
      _remoteResult = null;
    });

    final repository = ref.read(ocrRepositoryProvider);

    try {
      final local = await repository.recognizeLocally(imageFile);
      final remote = await repository.recognizeWithServer(
        imageFile,
        engineType: _remoteEngine,
      );

      if (!mounted) return;
      setState(() {
        _localResult = local;
        _remoteResult = remote;
        _isRunning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserMessage.forOcr(e);
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OCR Benchmark')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoCard(
              title: 'İç kullanım ekranı',
              body:
                  'Bu ekran yerel OCR ile sunucu OCR sonucunu karşılaştırmak içindir.',
            ),
            const SizedBox(height: 16),
            if (_imageFile != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(_imageFile!.path),
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Galeriden Seç'),
                    onPressed: _isRunning
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Kameradan Al'),
                    onPressed: _isRunning
                        ? null
                        : () => _pickImage(ImageSource.camera),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<OcrEngineType>(
              initialValue: _remoteEngine,
              decoration: const InputDecoration(
                labelText: 'Uzak OCR motoru',
                border: OutlineInputBorder(),
              ),
              items:
                  const [
                    OcrEngineType.paddleOcr,
                    OcrEngineType.googleVision,
                    OcrEngineType.tesseractTr,
                  ].map((engine) {
                    return DropdownMenuItem(
                      value: engine,
                      child: Text(engine.label),
                    );
                  }).toList(),
              onChanged: _isRunning
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _remoteEngine = value;
                      });
                    },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Benchmarki Çalıştır'),
                onPressed: _isRunning ? null : _runBenchmark,
              ),
            ),
            if (_isRunning) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorCard(message: _error!),
            ],
            if (_localResult != null || _remoteResult != null) ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 700;
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(
                          child: _ResultCard(
                            title: 'Yerel sonuç',
                            result: _localResult,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ResultCard(
                            title: 'Uzak sonuç',
                            result: _remoteResult,
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      _ResultCard(title: 'Yerel sonuç', result: _localResult),
                      const SizedBox(height: 12),
                      _ResultCard(title: 'Uzak sonuç', result: _remoteResult),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;

  const _InfoCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blueGrey[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Text(message, style: TextStyle(color: Colors.red[800])),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final OcrRecognitionResult? result;

  const _ResultCard({required this.title, required this.result});

  @override
  Widget build(BuildContext context) {
    final data = result;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (data != null &&
              data.result.warnings.any(
                (warning) => warning.toLowerCase().contains('mock'),
              )) ...[
            const SizedBox(height: 8),
            const _DemoLabel(),
          ],
          const SizedBox(height: 8),
          if (data == null)
            const Text('Henüz sonuç yok.')
          else ...[
            _MetaLine(label: 'Motor', value: data.result.engineType.label),
            _MetaLine(
              label: 'Süre',
              value: '${data.result.processingTimeMs} ms',
            ),
            _MetaLine(
              label: 'Güvenirlik',
              value: '${data.result.confidence}% ',
            ),
            if (data.result.hasWarnings)
              _MetaLine(
                label: 'Uyarılar',
                value: data.result.warnings.join(' · '),
              ),
            const SizedBox(height: 10),
            Text(
              data.result.text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _DemoLabel extends StatelessWidget {
  const _DemoLabel();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Text(
          'Demo OCR sonucu',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.orange[900],
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  final String label;
  final String value;

  const _MetaLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
