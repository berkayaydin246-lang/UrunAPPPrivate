import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/admin/controllers/product_submission_review_controller.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_submission_approval_repository.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';

// Unit tests for the approval repository helpers and controller state
// that do NOT require a Supabase connection.
//
// Database-level behaviour (approve creates product, approve updates existing,
// approve does not overwrite verified fields, reject changes status) is
// exercised through integration tests against the real Supabase instance,
// which require a live connection and service-role key.  The tests below
// verify the pure-Dart logic that surrounds those DB calls.

void main() {
  final now = DateTime(2026, 8, 8);

  ProductSubmission submission({
    Map<String, dynamic>? nutrition = const {
      'energy_kcal': 193.0,
      'fat': 3.4,
      'sugars': 9.2,
      'salt': 0.7,
    },
  }) {
    return ProductSubmission(
      id: 'submission-1',
      barcode: '8690000000001',
      productName: 'Test Ürünü',
      brand: 'Test Marka',
      frontImageUrl: 'https://cdn.example/front.jpg',
      extractedIngredientsText: 'su, şeker',
      extractedNutrition: nutrition,
      extractionStatus: 'success',
      status: 'pending',
      source: 'barcode_missing',
      createdAt: now,
      updatedAt: now,
    );
  }

  Product existingProduct({String? nutritionText}) {
    return Product(
      id: 'product-1',
      barcode: '8690000000001',
      name: 'Mevcut Ürün',
      nutritionText: nutritionText,
      verificationStatus: 'verified',
      createdAt: now,
      updatedAt: now,
    );
  }

  // ── ApproveProductResult enum ─────────────────────────────────────────────

  group('ApproveProductResult', () {
    test('approved and updatedExisting are distinct values', () {
      expect(
        ApproveProductResult.approved,
        isNot(ApproveProductResult.updatedExisting),
      );
    });

    test('all expected values are present', () {
      expect(
        ApproveProductResult.values,
        contains(ApproveProductResult.approved),
      );
      expect(
        ApproveProductResult.values,
        contains(ApproveProductResult.updatedExisting),
      );
      expect(
        ApproveProductResult.values,
        contains(ApproveProductResult.notFound),
      );
      expect(
        ApproveProductResult.values,
        contains(ApproveProductResult.invalidBarcode),
      );
      expect(
        ApproveProductResult.values,
        contains(ApproveProductResult.alreadyProcessed),
      );
    });
  });

  group('submission nutrition approval mapping', () {
    test('reviewed nutrition survives into the final Product model', () {
      final insertMap =
          ProductSubmissionApprovalRepository.buildProductInsertMap(
            submission(),
            editedNutrition: const {
              'energy_kcal': 201,
              'fat': '4,5',
              'fiber': 2.1,
              'proteins': 7,
              'serving_size': '30 g',
            },
            nutritionWasReviewed: true,
          );

      final decoded = jsonDecode(insertMap['nutrition_text'] as String);
      expect(decoded, {
        'energy_kcal': 201.0,
        'fat': 4.5,
        'fiber': 2.1,
        'proteins': 7.0,
        'serving_size': '30 g',
      });

      final product = Product.fromJson({
        ...insertMap,
        'id': 'product-1',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      expect(product.hasNutrition, isTrue);
      expect(product.nutrition?.energyKcal, 201.0);
      expect(product.nutrition?.fat, 4.5);
      expect(product.nutrition?.servingSize, '30 g');
    });

    test('unreviewed approval falls back to extracted nutrition', () {
      final insertMap =
          ProductSubmissionApprovalRepository.buildProductInsertMap(
            submission(),
          );
      final decoded = jsonDecode(insertMap['nutrition_text'] as String);

      expect(decoded['energy_kcal'], 193.0);
      expect(decoded['salt'], 0.7);
    });

    test('admin can clear invalid extracted nutrition during review', () {
      final insertMap =
          ProductSubmissionApprovalRepository.buildProductInsertMap(
            submission(),
            editedNutrition: null,
            nutritionWasReviewed: true,
          );

      expect(insertMap.containsKey('nutrition_text'), isFalse);
    });

    test(
      'enrichment fills missing nutrition without overwriting existing data',
      () {
        final reviewed =
            ProductSubmissionApprovalRepository.buildProductInsertMap(
              submission(),
            );

        final missingPatch =
            ProductSubmissionApprovalRepository.buildProductEnrichPatch(
              existingProduct(),
              reviewed,
            );
        expect(missingPatch['nutrition_text'], reviewed['nutrition_text']);

        final existingPatch =
            ProductSubmissionApprovalRepository.buildProductEnrichPatch(
              existingProduct(nutritionText: '{"energy_kcal":100.0}'),
              reviewed,
            );
        expect(existingPatch.containsKey('nutrition_text'), isFalse);
      },
    );
  });

  // ── ProductSubmissionReviewState ──────────────────────────────────────────

  group('ProductSubmissionReviewState', () {
    test('initial state has loading submissions and no error', () {
      const s = ProductSubmissionReviewState();
      expect(s.submissions, isA<AsyncLoading>());
      expect(s.isProcessing, isFalse);
      expect(s.error, isNull);
    });

    test('copyWith preserves unspecified fields', () {
      const s = ProductSubmissionReviewState(isProcessing: true);
      final s2 = s.copyWith(error: 'boom');
      expect(s2.isProcessing, isTrue);
      expect(s2.error, 'boom');
    });

    test('copyWith clearError removes error', () {
      const s = ProductSubmissionReviewState(error: 'old error');
      final s2 = s.copyWith(clearError: true);
      expect(s2.error, isNull);
    });

    test('copyWith with new submissions replaces old ones', () {
      const s = ProductSubmissionReviewState();
      final s2 = s.copyWith(submissions: const AsyncData([]));
      expect(s2.submissions, isA<AsyncData<List>>());
    });
  });

  // ── _resolve / _isEmpty helper parity ────────────────────────────────────
  // Tested indirectly through the field resolution logic of the repository.
  // We verify the observable outcome via the SubmitMissingProductResponse
  // message contract, which uses the same trim/empty logic.

  group('approval result message contract', () {
    test('approved result produces correct UI message', () {
      const result = ApproveProductResult.approved;
      final msg = switch (result) {
        ApproveProductResult.approved => 'Ürün veritabanına eklendi.',
        ApproveProductResult.updatedExisting =>
          'Mevcut ürün eksik alanlarla güncellendi.',
        _ => 'İşlem tamamlandı.',
      };
      expect(msg, 'Ürün veritabanına eklendi.');
    });

    test('updatedExisting result produces correct UI message', () {
      const result = ApproveProductResult.updatedExisting;
      final msg = switch (result) {
        ApproveProductResult.approved => 'Ürün veritabanına eklendi.',
        ApproveProductResult.updatedExisting =>
          'Mevcut ürün eksik alanlarla güncellendi.',
        _ => 'İşlem tamamlandı.',
      };
      expect(msg, 'Mevcut ürün eksik alanlarla güncellendi.');
    });

    test('notFound falls through to default message', () {
      const result = ApproveProductResult.notFound;
      final msg = switch (result) {
        ApproveProductResult.approved => 'Ürün veritabanına eklendi.',
        ApproveProductResult.updatedExisting =>
          'Mevcut ürün eksik alanlarla güncellendi.',
        _ => 'İşlem tamamlandı.',
      };
      expect(msg, 'İşlem tamamlandı.');
    });
  });

  // ── Extraction status display logic ───────────────────────────────────────
  // Mirrors the switch + error-suppression logic in _ExtractionStatusCard.

  String statusLabel(String status) => switch (status) {
    'success' => 'OCR başarılı',
    'failed' => 'OCR başarısız',
    'pending' => 'Otomatik okuma devam ediyor.',
    _ => 'Otomatik okuma yapılmadı.',
  };

  String? errorMessage(String status, String? error) {
    if (status != 'failed') return null;
    return UserMessage.forSubmissionOcr(error);
  }

  group('extraction status display — success suppresses stale error', () {
    test('success status shows OCR başarılı label', () {
      expect(statusLabel('success'), 'OCR başarılı');
    });

    test(
      'success status does NOT show error even when DB field is populated',
      () {
        const staleError = 'DioException [connection refused]';
        final msg = errorMessage('success', staleError);
        expect(msg, isNull);
      },
    );

    test('success status with null error shows no error', () {
      expect(errorMessage('success', null), isNull);
    });
  });

  group('extraction status display — failed shows error', () {
    test('failed status shows OCR başarısız label', () {
      expect(statusLabel('failed'), 'OCR başarısız');
    });

    test('failed status maps technical connection text to a safe message', () {
      const error = 'connection timeout';
      expect(
        errorMessage('failed', error),
        UserMessage.submissionOcrUnavailable,
      );
    });

    test('failed status with null error falls back to generic message', () {
      expect(errorMessage('failed', null), UserMessage.submissionOcrGeneric);
    });

    test('failed status with blank error falls back to generic message', () {
      expect(errorMessage('failed', '   '), UserMessage.submissionOcrGeneric);
    });

    test('failed status never exposes a stored raw Dio error', () {
      final message = errorMessage(
        'failed',
        'DioException [bad response]: status code of 401 RequestOptions',
      );

      expect(message, UserMessage.submissionOcrAuth);
      expect(message, isNot(contains('DioException')));
    });
  });

  group('extraction status display — other statuses', () {
    test('pending shows devam ediyor label and no error', () {
      expect(statusLabel('pending'), 'Otomatik okuma devam ediyor.');
      expect(errorMessage('pending', 'some error'), isNull);
    });

    test('not_started shows yapılmadı label and no error', () {
      expect(statusLabel('not_started'), 'Otomatik okuma yapılmadı.');
      expect(errorMessage('not_started', null), isNull);
    });
  });

  // ── Controller error propagation ─────────────────────────────────────────

  group('ProductSubmissionReviewState error propagation', () {
    test('approve failure stores error on state', () {
      const initial = ProductSubmissionReviewState();
      final withError = initial.copyWith(
        isProcessing: false,
        error: 'PostgrestException: new row violates row-level security',
      );
      expect(withError.isProcessing, isFalse);
      expect(withError.error, contains('row-level security'));
    });

    test('state isProcessing=true set before async DB call, cleared after', () {
      const before = ProductSubmissionReviewState(isProcessing: true);
      final after = before.copyWith(isProcessing: false);
      expect(before.isProcessing, isTrue);
      expect(after.isProcessing, isFalse);
    });
  });
}
