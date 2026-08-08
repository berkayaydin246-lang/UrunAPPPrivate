import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/core/services/storage_service.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';
import 'package:food_analyzer_app/features/ocr/services/ocr_request_headers.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';

enum SubmitMissingProductResult {
  submitted,
  updated,
  validationError,
  uploadError,
  databaseError,
}

class SubmitMissingProductResponse {
  final SubmitMissingProductResult result;
  final String message;
  final bool extractionFailed;

  const SubmitMissingProductResponse({
    required this.result,
    required this.message,
    this.extractionFailed = false,
  });

  bool get isSuccess =>
      result == SubmitMissingProductResult.submitted ||
      result == SubmitMissingProductResult.updated;
}

class LabelExtractionResult {
  final String? ingredientsText;
  final Map<String, dynamic>? nutrition;
  final String status; // not_started, pending, success, failed
  final String? error;

  const LabelExtractionResult({
    this.ingredientsText,
    this.nutrition,
    required this.status,
    this.error,
  });
}

bool hasRequiredSubmissionInputs({
  required String barcode,
  required Uint8List? frontImageBytes,
  required Uint8List? labelImageBytes,
}) {
  return barcode.trim().isNotEmpty &&
      frontImageBytes != null &&
      labelImageBytes != null;
}

class ProductSubmissionRepository {
  final SubmissionOcrExtractor? _ocrExtractor;

  const ProductSubmissionRepository({SubmissionOcrExtractor? ocrExtractor})
    : _ocrExtractor = ocrExtractor;

  Future<SubmitMissingProductResponse> submitMissingProduct({
    required String barcode,
    required Uint8List frontImageBytes,
    required Uint8List labelImageBytes,
    required String frontImageName,
    required String labelImageName,
    Uint8List? nutritionImageBytes,
    String? nutritionImageName,
    String? productName,
    String? brand,
    String? notes,
    ScoringEvidenceSnapshot? scoringEvidence,
  }) async {
    if (!hasRequiredSubmissionInputs(
      barcode: barcode,
      frontImageBytes: frontImageBytes,
      labelImageBytes: labelImageBytes,
    )) {
      return const SubmitMissingProductResponse(
        result: SubmitMissingProductResult.validationError,
        message:
            'Ürünü ekleyebilmemiz için ön yüz ve içindekiler fotoğrafları gereklidir.',
      );
    }

    try {
      final client = SupabaseService.client;
      final normalizedBarcode = barcode.trim();

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final safeFrontName = frontImageName.trim().isEmpty
          ? 'front.jpg'
          : frontImageName.trim();
      final safeLabelName = labelImageName.trim().isEmpty
          ? 'label.jpg'
          : labelImageName.trim();
      final frontPath = '$normalizedBarcode/${stamp}_front_$safeFrontName';
      final labelPath = '$normalizedBarcode/${stamp}_label_$safeLabelName';

      final frontImageUrl = await StorageService.uploadFileBytes(
        'product-submissions',
        frontPath,
        frontImageBytes,
      );
      final labelImageUrl = await StorageService.uploadFileBytes(
        'product-submissions',
        labelPath,
        labelImageBytes,
      );

      if (frontImageUrl == null || labelImageUrl == null) {
        return const SubmitMissingProductResponse(
          result: SubmitMissingProductResult.uploadError,
          message: 'Fotoğraflar yüklenemedi. Lütfen tekrar deneyin.',
        );
      }

      String? nutritionImageUrl;
      if (nutritionImageBytes != null) {
        final safeNutritionName = nutritionImageName?.trim().isNotEmpty == true
            ? nutritionImageName!.trim()
            : 'nutrition.jpg';
        final nutritionPath =
            '$normalizedBarcode/${stamp}_nutrition_$safeNutritionName';
        nutritionImageUrl = await StorageService.uploadFileBytes(
          'product-submissions',
          nutritionPath,
          nutritionImageBytes,
        );
        if (nutritionImageUrl == null) {
          _debugSubmissionLog(
            '[Submission] optional nutrition image could not be uploaded',
          );
        }
      }

      _debugSubmissionLog('[Submission] label image uploaded');
      _debugSubmissionLog(
        '[Submission] extraction started for barcode: $normalizedBarcode',
      );
      final extractor = _ocrExtractor ?? SubmissionOcrExtractor.fromEnv();
      final labelExtraction = await extractor.extractFromLabelImage(
        labelImageUrl,
      );
      final extraction = nutritionImageUrl == null
          ? labelExtraction
          : mergeLabelExtractionResults(
              labelExtraction,
              await extractor.extractFromLabelImage(nutritionImageUrl),
            );
      _debugSubmissionLog(
        '[Submission] extraction status: ${extraction.status}',
      );
      _debugSubmissionLog(
        '[Submission] extracted ingredients length: '
        '${extraction.ingredientsText?.length ?? 0}',
      );
      _debugSubmissionLog(
        '[Submission] extracted nutrition hasAnyData: '
        '${extraction.nutrition != null && extraction.nutrition!.isNotEmpty}',
      );

      // Check if a pending submission already exists for this barcode.
      final existing = await client
          .from('product_submissions')
          .select('id')
          .eq('barcode', normalizedBarcode)
          .eq('status', 'pending')
          .maybeSingle();

      final payload = <String, dynamic>{
        'barcode': normalizedBarcode,
        if (productName != null && productName.trim().isNotEmpty)
          'product_name': productName.trim(),
        if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'front_image_url': frontImageUrl,
        'label_image_url': labelImageUrl,
        'nutrition_image_url': ?nutritionImageUrl,
        // Backward compatibility for legacy reads.
        'image_url': frontImageUrl,
        if (extraction.ingredientsText != null &&
            extraction.ingredientsText!.trim().isNotEmpty)
          'extracted_ingredients_text': extraction.ingredientsText!.trim(),
        if (extraction.nutrition != null)
          'extracted_nutrition': extraction.nutrition,
        if (scoringEvidence != null)
          'scoring_evidence': scoringEvidence.toJson(),
        'extraction_status': extraction.status,
        if (extraction.error != null && extraction.error!.trim().isNotEmpty)
          'extraction_error': extraction.error,
        'status': 'pending',
        'source': 'barcode_missing',
        'submitted_by': client.auth.currentUser?.id,
      };

      if (existing != null) {
        await client
            .from('product_submissions')
            .update(payload)
            .eq('id', existing['id'] as String);

        final extractionMessage = extraction.status == 'failed'
            ? 'Fotoğraflar gönderildi ancak içerik otomatik okunamadı. İnceleme sırasında kontrol edilecek.'
            : 'Bu ürün inceleme kuyruğunda güncellendi.';
        return SubmitMissingProductResponse(
          result: SubmitMissingProductResult.updated,
          message: extractionMessage,
          extractionFailed: extraction.status == 'failed',
        );
      }

      await client.from('product_submissions').insert(payload);

      final extractionMessage = extraction.status == 'failed'
          ? 'Fotoğraflar gönderildi ancak içerik otomatik okunamadı. İnceleme sırasında kontrol edilecek.'
          : 'Ürün inceleme için gönderildi.';
      return SubmitMissingProductResponse(
        result: SubmitMissingProductResult.submitted,
        message: extractionMessage,
        extractionFailed: extraction.status == 'failed',
      );
    } catch (_) {
      return const SubmitMissingProductResponse(
        result: SubmitMissingProductResult.databaseError,
        message: 'Gönderim kaydedilemedi. Lütfen tekrar deneyin.',
      );
    }
  }
}

class SubmissionOcrExtractor {
  final Dio _dio;
  final String _baseUrl;
  final String _backendApiKey;
  final String _supabaseAnonKey;

  const SubmissionOcrExtractor({
    required Dio dio,
    required String baseUrl,
    String backendApiKey = '',
    String supabaseAnonKey = '',
  }) : _dio = dio,
       _baseUrl = baseUrl,
       _backendApiKey = backendApiKey,
       _supabaseAnonKey = supabaseAnonKey;

  factory SubmissionOcrExtractor.fromEnv() {
    return SubmissionOcrExtractor(
      dio: Dio(),
      baseUrl: dotenv.env['OCR_BACKEND_URL'] ?? '',
      backendApiKey: dotenv.env['OCR_BACKEND_API_KEY'] ?? '',
      supabaseAnonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    );
  }

  bool get _isSupabaseEdge => isSupabaseFunctionsUrl(_baseUrl);

  String get _normalizedBaseUrl =>
      _baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');

  Map<String, dynamic> get _headers => buildOcrRequestHeaders(
    baseUrl: _baseUrl,
    backendApiKey: _backendApiKey,
    supabaseAnonKey: _supabaseAnonKey,
  );

  @visibleForTesting
  Map<String, dynamic> get headersForTest => _headers;

  Future<LabelExtractionResult> extractFromLabelImage(String imageUrl) async {
    if (_normalizedBaseUrl.isEmpty) {
      _debugSubmissionLog(
        '[Submission] OCR_BACKEND_URL not set — skipping extraction',
      );
      return const LabelExtractionResult(status: 'not_started');
    }

    if ((_isSupabaseEdge && _supabaseAnonKey.trim().isEmpty) ||
        (!_isSupabaseEdge && _backendApiKey.trim().isEmpty)) {
      _debugSubmissionLog('[Submission] OCR authentication is not configured');
      return const LabelExtractionResult(
        status: 'failed',
        error: UserMessage.submissionOcrAuth,
      );
    }

    final combined = await _extractProductLabel(imageUrl);
    if (combined != null) return combined;

    return _extractIngredients(imageUrl);
  }

  Future<LabelExtractionResult?> _extractProductLabel(String imageUrl) async {
    const sendTimeout = Duration(seconds: 20);
    const receiveTimeout = Duration(seconds: 60);

    try {
      _debugSubmissionLog('[Submission] calling /ocr/product-label');
      final response = await _dio
          .postUri(
            Uri.parse('$_normalizedBaseUrl/ocr/product-label'),
            data: {'image_url': imageUrl, 'language_hint': 'tr'},
            options: Options(
              headers: _headers,
              sendTimeout: sendTimeout,
              receiveTimeout: receiveTimeout,
            ),
          )
          .timeout(const Duration(seconds: 65));

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const LabelExtractionResult(
          status: 'failed',
          error: UserMessage.submissionOcrGeneric,
        );
      }

      final status = (data['extraction_status'] as String?) ?? 'failed';
      final ingredientsValue = data['ingredients'];
      final ingredientsData = ingredientsValue is Map
          ? Map<String, dynamic>.from(ingredientsValue)
          : null;
      final nutritionValue = data['nutrition'];
      final nutritionRaw = nutritionValue is Map
          ? normalizeNutritionMap(Map<String, dynamic>.from(nutritionValue))
          : null;

      String? ingredientsText;
      if (ingredientsData != null) {
        final parsed = StructuredIngredientExtractionResult.fromJson(
          ingredientsData,
        );
        final names = parsed.confirmedIngredientNames.join(', ').trim();
        ingredientsText = names.isNotEmpty ? names : parsed.cleanedText.trim();
        if (ingredientsText.isEmpty) ingredientsText = null;
      }

      _debugSubmissionLog(
        '[Submission] /ocr/product-label success — '
        'status=$status ingredients=${ingredientsText?.length ?? 0} chars '
        'nutrition=${nutritionRaw != null}',
      );

      final succeeded = status == 'success' || status == 'partial';
      return LabelExtractionResult(
        status: succeeded ? 'success' : 'failed',
        ingredientsText: ingredientsText,
        nutrition: nutritionRaw,
        error: succeeded ? null : UserMessage.submissionOcrUnreadable,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _debugSubmissionLog(
          '[Submission] /ocr/product-label not found (404) — '
          'falling back to /ocr/ingredients',
        );
        return null;
      }

      final message = UserMessage.forSubmissionOcr(e);
      _debugSubmissionLog('[Submission] /ocr/product-label failed: $message');
      return LabelExtractionResult(status: 'failed', error: message);
    } catch (e) {
      final message = UserMessage.forSubmissionOcr(e);
      _debugSubmissionLog('[Submission] /ocr/product-label failed: $message');
      return LabelExtractionResult(status: 'failed', error: message);
    }
  }

  Future<LabelExtractionResult> _extractIngredients(String imageUrl) async {
    const sendTimeout = Duration(seconds: 20);
    const receiveTimeout = Duration(seconds: 60);

    try {
      _debugSubmissionLog('[Submission] calling /ocr/ingredients');
      final response = await _dio
          .postUri(
            Uri.parse('$_normalizedBaseUrl/ocr/ingredients'),
            data: {
              'image_url': imageUrl,
              'language_hint': 'tr',
              'mode': 'ingredients_label',
            },
            options: Options(
              headers: _headers,
              sendTimeout: sendTimeout,
              receiveTimeout: receiveTimeout,
            ),
          )
          .timeout(const Duration(seconds: 65));

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const LabelExtractionResult(
          status: 'failed',
          error: UserMessage.submissionOcrGeneric,
        );
      }

      final parsed = StructuredIngredientExtractionResult.fromJson(data);
      final text = parsed.confirmedIngredientNames.join(', ').trim();
      final ingredientsText = text.isNotEmpty
          ? text
          : parsed.cleanedText.trim();

      _debugSubmissionLog(
        '[Submission] /ocr/ingredients success — '
        '${ingredientsText.length} chars',
      );

      return LabelExtractionResult(
        status: ingredientsText.isNotEmpty ? 'success' : 'failed',
        ingredientsText: ingredientsText.isNotEmpty ? ingredientsText : null,
        nutrition: null,
        error: ingredientsText.isNotEmpty
            ? null
            : UserMessage.submissionOcrUnreadable,
      );
    } catch (e) {
      final message = UserMessage.forSubmissionOcr(e);
      _debugSubmissionLog('[Submission] /ocr/ingredients failed: $message');
      return LabelExtractionResult(status: 'failed', error: message);
    }
  }
}

@visibleForTesting
LabelExtractionResult mergeLabelExtractionResults(
  LabelExtractionResult labelResult,
  LabelExtractionResult nutritionResult,
) {
  final ingredientsText = labelResult.ingredientsText?.trim().isNotEmpty == true
      ? labelResult.ingredientsText!.trim()
      : nutritionResult.ingredientsText?.trim();
  final nutrition =
      normalizeNutritionMap(nutritionResult.nutrition) ??
      normalizeNutritionMap(labelResult.nutrition);
  final hasData = ingredientsText?.isNotEmpty == true || nutrition != null;

  return LabelExtractionResult(
    status: hasData ? 'success' : 'failed',
    ingredientsText: ingredientsText?.isNotEmpty == true
        ? ingredientsText
        : null,
    nutrition: nutrition,
    error: hasData ? null : (nutritionResult.error ?? labelResult.error),
  );
}

void _debugSubmissionLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}
