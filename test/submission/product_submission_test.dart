import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';
import 'package:food_analyzer_app/features/submission/repositories/product_submission_repository.dart';

void main() {
  group('ProductSubmission.fromJson', () {
    test('parses all fields', () {
      final now = DateTime(2026, 5, 30, 12, 0, 0).toUtc();
      final json = {
        'id': 'abc-123',
        'barcode': '8699118005551',
        'product_name': 'Wawa Tuna',
        'brand': 'Wawa',
        'image_url': null,
        'front_image_url': 'https://cdn/front.jpg',
        'label_image_url': 'https://cdn/label.jpg',
        'nutrition_image_url': 'https://cdn/nutrition.jpg',
        'extracted_ingredients_text': 'su, tuz',
        'extracted_nutrition': {'sugars': 12.3},
        'extraction_status': 'success',
        'extraction_error': null,
        'notes': 'test',
        'submitted_by': null,
        'status': 'pending',
        'source': 'barcode_missing',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final submission = ProductSubmission.fromJson(json);

      expect(submission.id, 'abc-123');
      expect(submission.barcode, '8699118005551');
      expect(submission.productName, 'Wawa Tuna');
      expect(submission.brand, 'Wawa');
      expect(submission.imageUrl, isNull);
      expect(submission.frontImageUrl, 'https://cdn/front.jpg');
      expect(submission.labelImageUrl, 'https://cdn/label.jpg');
      expect(submission.nutritionImageUrl, 'https://cdn/nutrition.jpg');
      expect(submission.extractedIngredientsText, 'su, tuz');
      expect(submission.extractedNutrition?['sugars'], 12.3);
      expect(submission.extractionStatus, 'success');
      expect(submission.extractionError, isNull);
      expect(submission.notes, 'test');
      expect(submission.submittedBy, isNull);
      expect(submission.status, 'pending');
      expect(submission.source, 'barcode_missing');
      expect(submission.createdAt, now);
    });

    test('defaults status to pending when absent', () {
      final now = DateTime(2026, 5, 30).toUtc();
      final json = {
        'id': 'x',
        'barcode': '123',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final submission = ProductSubmission.fromJson(json);
      expect(submission.status, 'pending');
      expect(submission.source, 'barcode_missing');
      expect(submission.extractionStatus, 'not_started');
    });

    test('nullable optional fields are null when absent', () {
      final now = DateTime(2026, 5, 30).toUtc();
      final json = {
        'id': 'x',
        'barcode': '123',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final submission = ProductSubmission.fromJson(json);
      expect(submission.productName, isNull);
      expect(submission.brand, isNull);
      expect(submission.imageUrl, isNull);
      expect(submission.frontImageUrl, isNull);
      expect(submission.labelImageUrl, isNull);
      expect(submission.nutritionImageUrl, isNull);
      expect(submission.extractedIngredientsText, isNull);
      expect(submission.extractedNutrition, isNull);
      expect(submission.extractionError, isNull);
      expect(submission.notes, isNull);
      expect(submission.submittedBy, isNull);
    });
  });

  // ── LabelExtractionResult ────────────────────────────────────────────────

  group('LabelExtractionResult', () {
    test('success status with ingredients text', () {
      const result = LabelExtractionResult(
        status: 'success',
        ingredientsText: 'su, tuz, şeker',
      );
      expect(result.status, 'success');
      expect(result.ingredientsText, 'su, tuz, şeker');
      expect(result.nutrition, isNull);
      expect(result.error, isNull);
    });

    test('success status with nutrition populated', () {
      const result = LabelExtractionResult(
        status: 'success',
        ingredientsText: 'su, tuz',
        nutrition: {'energy_kcal': 190.0, 'proteins': 24.8, 'salt': 1.6725},
      );
      expect(result.nutrition!['energy_kcal'], 190.0);
      expect(result.nutrition!['proteins'], 24.8);
      expect(result.nutrition!['salt'], 1.6725);
    });

    test('failed status keeps error and null ingredients', () {
      const result = LabelExtractionResult(
        status: 'failed',
        error: 'connection timeout',
      );
      expect(result.status, 'failed');
      expect(result.ingredientsText, isNull);
      expect(result.nutrition, isNull);
      expect(result.error, 'connection timeout');
    });

    test('not_started status when no OCR backend configured', () {
      const result = LabelExtractionResult(status: 'not_started');
      expect(result.status, 'not_started');
      expect(result.ingredientsText, isNull);
      expect(result.nutrition, isNull);
    });
  });

  group('SubmissionOcrExtractor', () {
    const edgeUrl = 'https://dzsmkmwatwvuxigynimq.supabase.co/functions/v1';

    test(
      'Edge Function request sends anon headers and parses product-label nutrition',
      () async {
        final adapter = _RecordingAdapter(
          statusCode: 200,
          responseBody: jsonEncode({
            'ingredients': {
              'raw_text': 'su, şeker',
              'cleaned_text': 'su, şeker',
              'ingredients': [
                {'name': 'su', 'original_text': 'su', 'confidence': 0.99},
                {'name': 'şeker', 'original_text': 'şeker', 'confidence': 0.98},
              ],
              'quality_score': 0.95,
            },
            'nutrition': {
              'energy_kcal': 193,
              'fat': '3,4',
              'sugars': 9.2,
              'salt': 0.7,
              'fiber': 'not_visible',
            },
            'extraction_status': 'success',
          }),
        );
        final dio = Dio()..httpClientAdapter = adapter;
        final extractor = SubmissionOcrExtractor(
          dio: dio,
          baseUrl: '$edgeUrl/',
          supabaseAnonKey: 'anon-jwt-value',
        );

        final result = await extractor.extractFromLabelImage(
          'https://cdn.example/label.jpg',
        );

        expect(adapter.callCount, 1);
        expect(
          adapter.lastRequest?.uri.toString(),
          '$edgeUrl/ocr/product-label',
        );
        expect(adapter.lastRequest?.headers['apikey'], 'anon-jwt-value');
        expect(
          adapter.lastRequest?.headers['Authorization'],
          'Bearer anon-jwt-value',
        );
        expect(
          adapter.lastRequest?.headers['Content-Type'],
          'application/json',
        );
        expect(result.status, 'success');
        expect(result.ingredientsText, 'su, şeker');
        expect(result.nutrition, {
          'energy_kcal': 193.0,
          'fat': 3.4,
          'sugars': 9.2,
          'salt': 0.7,
        });
        expect(result.error, isNull);
      },
    );

    test(
      '404 product-label response falls back to ingredients endpoint',
      () async {
        final adapter = _QueuedAdapter([
          _AdapterResponse(404, jsonEncode({'error': 'Not found'})),
          _AdapterResponse(
            200,
            jsonEncode({
              'raw_text': 'su, tuz',
              'cleaned_text': 'su, tuz',
              'ingredients': [
                {'name': 'su', 'original_text': 'su', 'confidence': 0.99},
                {'name': 'tuz', 'original_text': 'tuz', 'confidence': 0.99},
              ],
              'quality_score': 0.9,
            }),
          ),
        ]);
        final dio = Dio()..httpClientAdapter = adapter;
        final extractor = SubmissionOcrExtractor(
          dio: dio,
          baseUrl: edgeUrl,
          supabaseAnonKey: 'anon-jwt-value',
        );

        final result = await extractor.extractFromLabelImage(
          'https://cdn.example/label.jpg',
        );

        expect(adapter.paths, [
          '$edgeUrl/ocr/product-label',
          '$edgeUrl/ocr/ingredients',
        ]);
        expect(result.status, 'success');
        expect(result.ingredientsText, 'su, tuz');
        expect(result.nutrition, isNull);
      },
    );

    test('HTTP 401 maps to the clean submission OCR auth message', () async {
      final adapter = _RecordingAdapter(
        statusCode: 401,
        responseBody: jsonEncode({'error': 'Unauthorized'}),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final extractor = SubmissionOcrExtractor(
        dio: dio,
        baseUrl: edgeUrl,
        supabaseAnonKey: 'anon-jwt-value',
      );

      final result = await extractor.extractFromLabelImage(
        'https://cdn.example/label.jpg',
      );

      expect(result.status, 'failed');
      expect(result.error, UserMessage.submissionOcrAuth);
      expect(result.error, isNot(contains('DioException')));
      expect(result.error, isNot(contains('status code')));
    });

    test('Edge Function is not called without an anon key', () async {
      final adapter = _RecordingAdapter(statusCode: 200, responseBody: '{}');
      final dio = Dio()..httpClientAdapter = adapter;
      final extractor = SubmissionOcrExtractor(dio: dio, baseUrl: edgeUrl);

      final result = await extractor.extractFromLabelImage(
        'https://cdn.example/label.jpg',
      );

      expect(adapter.callCount, 0);
      expect(result.status, 'failed');
      expect(result.error, UserMessage.submissionOcrAuth);
    });
  });

  group('mergeLabelExtractionResults', () {
    test('keeps ingredients and prefers nutrition-photo values', () {
      const ingredientsResult = LabelExtractionResult(
        status: 'success',
        ingredientsText: 'su, şeker',
        nutrition: {'sugars': 8.0},
      );
      const nutritionResult = LabelExtractionResult(
        status: 'success',
        nutrition: {'sugars': 9.5, 'salt': 0.4},
      );

      final merged = mergeLabelExtractionResults(
        ingredientsResult,
        nutritionResult,
      );

      expect(merged.status, 'success');
      expect(merged.ingredientsText, 'su, şeker');
      expect(merged.nutrition, {'sugars': 9.5, 'salt': 0.4});
      expect(merged.error, isNull);
    });

    test('nutrition OCR failure does not discard extracted ingredients', () {
      const merged = LabelExtractionResult(
        status: 'success',
        ingredientsText: 'su, tuz',
      );
      final result = mergeLabelExtractionResults(
        merged,
        const LabelExtractionResult(
          status: 'failed',
          error: UserMessage.submissionOcrUnreadable,
        ),
      );

      expect(result.status, 'success');
      expect(result.ingredientsText, 'su, tuz');
      expect(result.nutrition, isNull);
      expect(result.error, isNull);
    });
  });

  // ── hasRequiredSubmissionInputs ──────────────────────────────────────────

  group('hasRequiredSubmissionInputs', () {
    final bytes = Uint8List.fromList([1, 2, 3]);

    test('returns true when barcode and both images provided', () {
      expect(
        hasRequiredSubmissionInputs(
          barcode: '8699118005551',
          frontImageBytes: bytes,
          labelImageBytes: bytes,
        ),
        isTrue,
      );
    });

    test('returns false when barcode is blank', () {
      expect(
        hasRequiredSubmissionInputs(
          barcode: '   ',
          frontImageBytes: bytes,
          labelImageBytes: bytes,
        ),
        isFalse,
      );
    });

    test('returns false when front image is missing', () {
      expect(
        hasRequiredSubmissionInputs(
          barcode: '123',
          frontImageBytes: null,
          labelImageBytes: bytes,
        ),
        isFalse,
      );
    });

    test('returns false when label image is missing', () {
      expect(
        hasRequiredSubmissionInputs(
          barcode: '123',
          frontImageBytes: bytes,
          labelImageBytes: null,
        ),
        isFalse,
      );
    });
  });

  // ── SubmitMissingProductResponse ─────────────────────────────────────────

  group('SubmitMissingProductResponse.isSuccess', () {
    test('submitted result is success', () {
      const r = SubmitMissingProductResponse(
        result: SubmitMissingProductResult.submitted,
        message: 'Ürün inceleme için gönderildi.',
      );
      expect(r.isSuccess, isTrue);
    });

    test('updated result is success', () {
      const r = SubmitMissingProductResponse(
        result: SubmitMissingProductResult.updated,
        message: 'Güncellendi.',
      );
      expect(r.isSuccess, isTrue);
    });

    test('uploadError result is not success', () {
      const r = SubmitMissingProductResponse(
        result: SubmitMissingProductResult.uploadError,
        message: 'Yüklenemedi.',
      );
      expect(r.isSuccess, isFalse);
    });

    test('extractionFailed flag defaults to false', () {
      const r = SubmitMissingProductResponse(
        result: SubmitMissingProductResult.submitted,
        message: '',
      );
      expect(r.extractionFailed, isFalse);
    });

    test('extractionFailed flag can be set true', () {
      const r = SubmitMissingProductResponse(
        result: SubmitMissingProductResult.submitted,
        message: 'Fotoğraflar gönderildi ancak içerik otomatik okunamadı.',
        extractionFailed: true,
      );
      expect(r.isSuccess, isTrue);
      expect(r.extractionFailed, isTrue);
    });
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.statusCode, required this.responseBody});

  final int statusCode;
  final String responseBody;
  RequestOptions? lastRequest;
  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount += 1;
    lastRequest = options;
    return ResponseBody.fromString(
      responseBody,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AdapterResponse {
  const _AdapterResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

class _QueuedAdapter implements HttpClientAdapter {
  _QueuedAdapter(this.responses);

  final List<_AdapterResponse> responses;
  final List<String> paths = [];
  int _index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.uri.toString());
    final response = responses[_index++];
    return ResponseBody.fromString(
      response.body,
      response.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
