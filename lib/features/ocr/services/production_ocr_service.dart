import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';

import 'package:food_analyzer_app/core/services/storage_service.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_request_headers.dart';

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
  // Direct-backend secret (local/Render dev). Release validator rejects this in
  // .env.client for production builds — see app_environment.dart.
  final String _apiKey;
  // Supabase anon key used when routing through Supabase Edge Functions.
  // This is the public JWT, not a secret — safe to embed in the client.
  final String _supabaseAnonKey;

  const HttpProductionOcrService({
    required Dio dio,
    required String baseUrl,
    String endpointPath = '/ocr/ingredients',
    String apiKey = '',
    String supabaseAnonKey = '',
  }) : _dio = dio,
       _baseUrl = baseUrl,
       _endpointPath = endpointPath,
       _apiKey = apiKey,
       _supabaseAnonKey = supabaseAnonKey;

  factory HttpProductionOcrService.fromEnv() {
    return HttpProductionOcrService(
      dio: Dio(),
      baseUrl: dotenv.env['OCR_BACKEND_URL'] ?? '',
      endpointPath: '/ocr/ingredients',
      apiKey: dotenv.env['OCR_BACKEND_API_KEY'] ?? '',
      supabaseAnonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );
  }

  // True when OCR_BACKEND_URL points at a Supabase Edge Function.
  // In that case, authentication uses the Supabase anon JWT, not a backend
  // secret. CLAUDE_API_KEY and service-role keys are never read here.
  bool get _isSupabaseFunctionsUrl => isSupabaseFunctionsUrl(_baseUrl);

  @override
  Future<StructuredIngredientExtractionResult> extractIngredients(
    XFile imageFile, {
    String languageHint = 'tr',
  }) async {
    if (_baseUrl.trim().isEmpty) {
      throw StateError('Gelişmiş OCR servisi henüz yapılandırılmadı.');
    }

    if (_isSupabaseFunctionsUrl && _supabaseAnonKey.trim().isEmpty) {
      throw StateError('Gelişmiş OCR yapılandırması eksik.');
    }

    if (!_isSupabaseFunctionsUrl && _apiKey.trim().isEmpty) {
      throw StateError('Gelişmiş OCR yapılandırması eksik.');
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

  // Mode A — direct backend: sends only the backend API key.
  // Mode B — Supabase Edge Function: sends Supabase anon JWT in both the
  //          standard apikey header and the Authorization Bearer header.
  // Neither mode sends CLAUDE_API_KEY or any service-role key.
  Map<String, dynamic> _buildHeaders() {
    return buildOcrRequestHeaders(
      baseUrl: _baseUrl,
      backendApiKey: _apiKey,
      supabaseAnonKey: _supabaseAnonKey,
    );
  }

  static String _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'Gelişmiş OCR yetkilendirmesi başarısız.';
    }
    if (status == 404) {
      return 'Gelişmiş OCR adresi bulunamadı. Lütfen yapılandırmayı kontrol et.';
    }
    if (status == 429) {
      return 'Çok fazla deneme yapıldı. Lütfen biraz sonra tekrar deneyin.';
    }
    if (status == 400 || status == 422) {
      return 'Görsel işlenemedi. Lütfen daha net ve okunur bir fotoğraf çekin.';
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
  bool get isSupabaseFunctionsUrlForTest => _isSupabaseFunctionsUrl;

  @visibleForTesting
  static String mapDioError(DioException e) => _mapDioError(e);
}
