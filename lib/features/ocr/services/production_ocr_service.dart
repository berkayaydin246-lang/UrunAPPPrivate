import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
  final String _apiKey;

  const HttpProductionOcrService({
    required Dio dio,
    required String baseUrl,
    String endpointPath = '/ocr/ingredients',
    String apiKey = '',
  }) : _dio = dio,
       _baseUrl = baseUrl,
       _endpointPath = endpointPath,
       _apiKey = apiKey;

  // TODO(production): Flutter must not call the OCR backend directly with a
  // client-embedded secret. Preferred production flow:
  //   Flutter → Supabase Edge Function (secure proxy) → OCR backend → Claude
  // Until the Edge Function proxy is implemented, production builds use the
  // OCR_BACKEND_URL without an embedded key. The release validator already
  // rejects OCR_BACKEND_API_KEY in .env.client for release/profile builds.
  factory HttpProductionOcrService.fromEnv() {
    return HttpProductionOcrService(
      dio: Dio(),
      baseUrl: dotenv.env['OCR_BACKEND_URL'] ?? '',
      endpointPath: '/ocr/ingredients',
      apiKey: dotenv.env['OCR_BACKEND_API_KEY'] ?? '',
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
        throw StateError('Fotoğraf OCR için yüklenemedi. Lütfen tekrar dene.');
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
              headers: _buildHeaders(),
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
    } on TimeoutException {
      throw StateError(
        'Gelişmiş OCR zaman aşımına uğradı. Lütfen tekrar dene.',
      );
    } on DioException catch (e) {
      throw StateError(_mapDioError(e));
    } finally {
      if (uploadedUrl != null) {
        await StorageService.deleteFile('ocr-temp', tempPath);
      }
    }
  }

  Map<String, dynamic> _buildHeaders() => {
    'Content-Type': 'application/json',
    if (_apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${_apiKey.trim()}',
  };

  static String _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'Gelişmiş OCR yetkilendirmesi başarısız. Lütfen OCR yapılandırmasını kontrol et.';
    }
    if (status != null && status >= 500) {
      return 'Gelişmiş OCR servisi şu anda yanıt veremiyor.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Gelişmiş OCR zaman aşımına uğradı. Lütfen tekrar dene.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'Gelişmiş OCR servisine ulaşılamadı.';
    }
    return 'Gelişmiş OCR isteği başarısız.';
  }

  @visibleForTesting
  Map<String, dynamic> headersForTest() => _buildHeaders();

  @visibleForTesting
  static String mapDioError(DioException e) => _mapDioError(e);
}
