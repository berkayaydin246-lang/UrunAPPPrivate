import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:food_analyzer_app/features/ocr/models/ocr_engine_type.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';

abstract class RemoteOcrClient {
  Future<OcrTextResult> recognizeImage({
    required String imageUrl,
    required OcrEngineType engineType,
    String languageHint = 'tr',
  });
}

class HttpRemoteOcrClient implements RemoteOcrClient {
  final Dio _dio;
  final String _baseUrl;
  final String _endpointPath;
  final RemoteOcrClient? _fallbackClient;

  const HttpRemoteOcrClient({
    required Dio dio,
    required String baseUrl,
    required String endpointPath,
    RemoteOcrClient? fallbackClient,
  }) : _dio = dio,
       _baseUrl = baseUrl,
       _endpointPath = endpointPath,
       _fallbackClient = fallbackClient;

  factory HttpRemoteOcrClient.fromEnv() {
    final baseUrl =
        dotenv.env['OCR_SERVER_URL'] ?? dotenv.env['OCR_REMOTE_BASE_URL'] ?? '';
    final endpointPath = dotenv.env['OCR_REMOTE_ENDPOINT_PATH'] ?? '/ocr';
    final mockText = dotenv.env['OCR_REMOTE_MOCK_TEXT'];
    final hasServerUrl = baseUrl.trim().isNotEmpty;

    return HttpRemoteOcrClient(
      dio: Dio(),
      baseUrl: baseUrl,
      endpointPath: endpointPath,
      fallbackClient: hasServerUrl
          ? (mockText != null && mockText.trim().isNotEmpty
                ? MockRemoteOcrClient(mockText.trim())
                : null)
          : MockRemoteOcrClient(
              mockText != null && mockText.trim().isNotEmpty
                  ? mockText.trim()
                  : 'İçindekiler: su, şeker, tuz',
            ),
    );
  }

  @override
  Future<OcrTextResult> recognizeImage({
    required String imageUrl,
    required OcrEngineType engineType,
    String languageHint = 'tr',
  }) async {
    if (_baseUrl.trim().isEmpty) {
      final fallback = _fallbackClient;
      if (fallback != null) {
        return fallback.recognizeImage(
          imageUrl: imageUrl,
          engineType: engineType,
          languageHint: languageHint,
        );
      }
      throw StateError('Uzak OCR sunucusu yapılandırılmadı.');
    }

    final startedAt = DateTime.now();
    final response = await _dio
        .postUri(
          Uri.parse('$_baseUrl$_endpointPath'),
          data: {
            'image_url': imageUrl,
            'engine': engineType.apiValue,
            'language_hint': languageHint,
          },
          options: Options(
            headers: {'Content-Type': 'application/json'},
            sendTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
          ),
        )
        .timeout(const Duration(seconds: 35));

    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw StateError('Uzak OCR yanıtı okunamadı.');
    }

    final rawText =
        (data['raw_text'] ?? data['text'] ?? data['ocr_text'] ?? '')
            ?.toString()
            .trim() ??
        '';
    final cleanedText =
        (data['cleaned_text'] ?? data['text'] ?? data['ocr_text'] ?? '')
            ?.toString()
            .trim() ??
        '';

    if (rawText.isEmpty && cleanedText.isEmpty) {
      throw StateError('Uzak OCR metin döndürmedi.');
    }

    final confidenceScore =
        ((data['confidence_score'] ?? data['confidence'] ?? 0) as num?)
            ?.toDouble() ??
        0.9;
    final processingTimeMs =
        (data['processing_time_ms'] as num?)?.toInt() ?? elapsedMs;
    final warnings =
        (data['warnings'] as List<dynamic>?)
            ?.map((item) => item.toString())
            .where((item) => item.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final responseEngine =
        (data['engine'] ?? data['engine_type'])
            ?.toString()
            .trim()
            .toLowerCase() ??
        engineType.apiValue;
    final responseLanguage =
        (data['language_hint'] ?? languageHint)?.toString() ?? languageHint;

    return OcrTextResult(
      engineType: _engineTypeFromApiValue(responseEngine) ?? engineType,
      rawText: rawText.isNotEmpty ? rawText : cleanedText,
      cleanedText: cleanedText.isNotEmpty ? cleanedText : rawText,
      confidenceScore: confidenceScore.clamp(0.0, 1.0),
      processingTimeMs: processingTimeMs,
      warnings: warnings,
      languageHint: responseLanguage,
    );
  }

  OcrEngineType? _engineTypeFromApiValue(String apiValue) {
    for (final value in OcrEngineType.values) {
      if (value.apiValue == apiValue) {
        return value;
      }
    }
    return null;
  }
}

class MockRemoteOcrClient implements RemoteOcrClient {
  final String mockText;

  const MockRemoteOcrClient([this.mockText = 'İçindekiler: su, şeker, tuz']);

  @override
  Future<OcrTextResult> recognizeImage({
    required String imageUrl,
    required OcrEngineType engineType,
    String languageHint = 'tr',
  }) async {
    return OcrTextResult(
      engineType: engineType,
      rawText: mockText,
      cleanedText: mockText,
      confidenceScore: 0.94,
      processingTimeMs: 180,
      warnings: const <String>['Mock OCR sonucu'],
      languageHint: languageHint,
    );
  }
}
