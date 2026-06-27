import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';

import 'package:food_analyzer_app/core/services/storage_service.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';

abstract class ProductionOcrService {
  Future<StructuredIngredientExtractionResult> extractIngredients(
    XFile imageFile, {
    String languageHint = 'tr',
  });
}

class HttpProductionOcrService implements ProductionOcrService {
  final Dio _dio;
  final String _baseUrl;
  final String _endpointPath;

  const HttpProductionOcrService({
    required Dio dio,
    required String baseUrl,
    String endpointPath = '/ocr/ingredients',
  }) : _dio = dio,
       _baseUrl = baseUrl,
       _endpointPath = endpointPath;

  factory HttpProductionOcrService.fromEnv() {
    return HttpProductionOcrService(
      dio: Dio(),
      baseUrl: dotenv.env['OCR_BACKEND_URL'] ?? '',
      endpointPath: '/ocr/ingredients',
    );
  }

  @override
  Future<StructuredIngredientExtractionResult> extractIngredients(
    XFile imageFile, {
    String languageHint = 'tr',
  }) async {
    if (_baseUrl.trim().isEmpty) {
      throw StateError('Gelişmiş OCR servisi henüz yapılandırılmadı.');
    }

    final bytes = Uint8List.fromList(await imageFile.readAsBytes());
    final tempPath = 'ocr-prod/${DateTime.now().millisecondsSinceEpoch}.jpg';
    String? uploadedUrl;

    try {
      uploadedUrl = await StorageService.uploadFileBytes(
        'ocr-temp',
        tempPath,
        bytes,
      );

      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw StateError('Görsel üretim OCR servisine yüklenemedi.');
      }

      final response = await _dio
          .postUri(
            Uri.parse('$_baseUrl$_endpointPath'),
            data: {
              'image_url': uploadedUrl,
              'language_hint': languageHint,
              'mode': 'ingredients_label',
            },
            options: Options(
              headers: {'Content-Type': 'application/json'},
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 40),
            ),
          )
          .timeout(const Duration(seconds: 45));

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw StateError('Üretim OCR yanıtı okunamadı.');
      }

      return StructuredIngredientExtractionResult.fromJson(data);
    } on DioException catch (e) {
      throw StateError(
        'Gelişmiş OCR isteği başarısız: ${e.message ?? e.toString()}',
      );
    } finally {
      if (uploadedUrl != null) {
        await StorageService.deleteFile('ocr-temp', tempPath);
      }
    }
  }
}
