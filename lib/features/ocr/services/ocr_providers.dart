import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';

import 'package:food_analyzer_app/core/services/storage_service.dart';
import 'package:food_analyzer_app/features/ocr/models/ocr_result.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_service.dart';

/// Local OCR remains the default because it is fast, offline and preserves the
/// current user flow even when network connectivity is poor.
abstract class OcrTextProvider {
  Future<OcrTextResult> recognize(XFile imageFile);
}

class LocalMlKitOcrProvider implements OcrTextProvider {
  final OcrService _service;

  const LocalMlKitOcrProvider(this._service);

  @override
  Future<OcrTextResult> recognize(XFile imageFile) {
    return _service.extractTextFromImage(imageFile);
  }
}

/// Remote OCR is a fallback only.
///
/// Server-side OCR is preferred for hard images because it can use heavier
/// models without increasing app size or battery usage on the device.
class PaddleOcrRemoteProvider implements OcrTextProvider {
  final Dio _dio;
  final String _baseUrl;
  final String _endpointPath;
  final String? _mockText;

  const PaddleOcrRemoteProvider({
    required Dio dio,
    required String baseUrl,
    required String endpointPath,
    String? mockText,
  }) : _dio = dio,
       _baseUrl = baseUrl,
       _endpointPath = endpointPath,
       _mockText = mockText;

  factory PaddleOcrRemoteProvider.fromEnv() {
    return PaddleOcrRemoteProvider(
      dio: Dio(),
      baseUrl: dotenv.env['PADDLE_OCR_BASE_URL'] ?? '',
      endpointPath: dotenv.env['PADDLE_OCR_ENDPOINT_PATH'] ?? '/ocr/paddle',
      mockText: dotenv.env['PADDLE_OCR_MOCK_TEXT'],
    );
  }

  @override
  Future<OcrTextResult> recognize(XFile imageFile) async {
    if (_mockText != null && _mockText.trim().isNotEmpty) {
      return OcrTextResult(text: _mockText.trim(), confidence: 95);
    }

    if (_baseUrl.trim().isEmpty) {
      throw StateError('Sunucu OCR yapılandırması bulunamadı.');
    }

    final bytes = await imageFile.readAsBytes();
    final tempPath = 'ocr-temp/${DateTime.now().millisecondsSinceEpoch}.jpg';
    String? uploadedUrl;

    try {
      uploadedUrl = await StorageService.uploadFileBytes(
        'ocr-temp',
        tempPath,
        Uint8List.fromList(bytes),
      );

      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw StateError('Görsel sunucuya yüklenemedi.');
      }

      final response = await _dio
          .postUri(
            Uri.parse('$_baseUrl$_endpointPath'),
            data: {'image_url': uploadedUrl},
            options: Options(
              headers: {'Content-Type': 'application/json'},
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ),
          )
          .timeout(const Duration(seconds: 30));

      final data = response.data;
      if (data is Map<String, dynamic>) {
        final text =
            (data['text'] ?? data['ocr_text'] ?? '')?.toString().trim() ?? '';
        if (text.isEmpty) {
          throw StateError('Sunucu OCR metin döndürmedi.');
        }

        final confidence = (data['confidence'] as num?)?.toInt() ?? 90;
        return OcrTextResult(text: text, confidence: confidence.clamp(0, 100));
      }

      throw StateError('Sunucu OCR yanıtı okunamadı.');
    } on DioException catch (e) {
      throw StateError(
        'Sunucu OCR isteği başarısız: ${e.message ?? e.toString()}',
      );
    } finally {
      if (uploadedUrl != null) {
        // Best-effort cleanup: delete the temporary file after OCR completes.
        await StorageService.deleteFile('ocr-temp', tempPath);
      }
    }
  }
}
