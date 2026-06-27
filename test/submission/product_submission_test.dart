import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
