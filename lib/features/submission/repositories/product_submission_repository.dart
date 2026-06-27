import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:food_analyzer_app/core/services/storage_service.dart';
import 'package:food_analyzer_app/core/services/supabase_service.dart';
import 'package:food_analyzer_app/features/ocr/models/structured_ingredient_extraction_result.dart';

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
  const ProductSubmissionRepository();

  Future<SubmitMissingProductResponse> submitMissingProduct({
    required String barcode,
    required Uint8List frontImageBytes,
    required Uint8List labelImageBytes,
    required String frontImageName,
    required String labelImageName,
    String? productName,
    String? brand,
    String? notes,
  }) async {
    if (!hasRequiredSubmissionInputs(
      barcode: barcode,
      frontImageBytes: frontImageBytes,
      labelImageBytes: labelImageBytes,
    )) {
      return const SubmitMissingProductResponse(
        result: SubmitMissingProductResult.validationError,
        message:
            'Ürünü ekleyebilmemiz için ön yüz ve içerik/besin etiketi fotoğrafları gereklidir.',
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

      _debugSubmissionLog('[Submission] label image uploaded');
      _debugSubmissionLog(
        '[Submission] extraction started for barcode: $normalizedBarcode',
      );
      final extraction = await _extractFromLabelImage(labelImageUrl);
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
        // Backward compatibility for legacy reads.
        'image_url': frontImageUrl,
        if (extraction.ingredientsText != null &&
            extraction.ingredientsText!.trim().isNotEmpty)
          'extracted_ingredients_text': extraction.ingredientsText!.trim(),
        if (extraction.nutrition != null)
          'extracted_nutrition': extraction.nutrition,
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

  Future<LabelExtractionResult> _extractFromLabelImage(String imageUrl) async {
    final baseUrl = (dotenv.env['OCR_BACKEND_URL'] ?? '').trim();
    if (baseUrl.isEmpty) {
      _debugSubmissionLog(
        '[Submission] OCR_BACKEND_URL not set — skipping extraction',
      );
      return const LabelExtractionResult(status: 'not_started');
    }

    final dio = Dio();
    const headers = <String, dynamic>{'Content-Type': 'application/json'};
    const sendTimeout = Duration(seconds: 20);
    const receiveTimeout = Duration(seconds: 60);

    // Attempt the combined product-label endpoint first (ingredients + nutrition).
    try {
      _debugSubmissionLog('[Submission] calling /ocr/product-label');
      final response = await dio
          .postUri(
            Uri.parse('$baseUrl/ocr/product-label'),
            data: {'image_url': imageUrl, 'language_hint': 'tr'},
            options: Options(
              headers: headers,
              sendTimeout: sendTimeout,
              receiveTimeout: receiveTimeout,
            ),
          )
          .timeout(const Duration(seconds: 65));

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const LabelExtractionResult(
          status: 'failed',
          error: 'product-label yanıtı okunamadı',
        );
      }

      final status = (data['extraction_status'] as String?) ?? 'failed';
      final ingredientsData = data['ingredients'] as Map<String, dynamic>?;
      final nutritionRaw = data['nutrition'] as Map<String, dynamic>?;

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

      return LabelExtractionResult(
        status: status == 'success' || status == 'partial'
            ? 'success'
            : 'failed',
        ingredientsText: ingredientsText,
        nutrition: nutritionRaw,
      );
    } on DioException catch (e) {
      // 404 means the backend doesn't have this endpoint yet — fall back.
      if (e.response?.statusCode == 404) {
        _debugSubmissionLog(
          '[Submission] /ocr/product-label not found (404) — '
          'falling back to /ocr/ingredients',
        );
      } else {
        _debugSubmissionLog('[Submission] /ocr/product-label error: $e');
        return LabelExtractionResult(status: 'failed', error: e.toString());
      }
    } catch (e) {
      _debugSubmissionLog(
        '[Submission] /ocr/product-label unexpected error: $e',
      );
      return LabelExtractionResult(status: 'failed', error: e.toString());
    }

    // Fallback: /ocr/ingredients (ingredients only, no nutrition).
    try {
      _debugSubmissionLog('[Submission] calling /ocr/ingredients (fallback)');
      final response = await dio
          .postUri(
            Uri.parse('$baseUrl/ocr/ingredients'),
            data: {
              'image_url': imageUrl,
              'language_hint': 'tr',
              'mode': 'ingredients_label',
            },
            options: Options(
              headers: headers,
              sendTimeout: sendTimeout,
              receiveTimeout: receiveTimeout,
            ),
          )
          .timeout(const Duration(seconds: 65));

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return const LabelExtractionResult(
          status: 'failed',
          error: 'OCR yanıtı okunamadı',
        );
      }

      final parsed = StructuredIngredientExtractionResult.fromJson(data);
      final text = parsed.confirmedIngredientNames.join(', ').trim();
      final ingredientsText = text.isNotEmpty
          ? text
          : parsed.cleanedText.trim();

      _debugSubmissionLog(
        '[Submission] /ocr/ingredients fallback success — '
        '${ingredientsText.length} chars',
      );

      // TODO: nutrition extraction not supported by /ocr/ingredients endpoint.
      return LabelExtractionResult(
        status: ingredientsText.isNotEmpty ? 'success' : 'failed',
        ingredientsText: ingredientsText.isNotEmpty ? ingredientsText : null,
        nutrition: null,
      );
    } catch (e) {
      _debugSubmissionLog('[Submission] /ocr/ingredients fallback error: $e');
      return LabelExtractionResult(status: 'failed', error: e.toString());
    }
  }
}

void _debugSubmissionLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}
