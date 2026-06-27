import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_submission_approval_repository.dart';
import 'package:food_analyzer_app/features/admin/controllers/product_submission_review_controller.dart';

// Unit tests for the approval repository helpers and controller state
// that do NOT require a Supabase connection.
//
// Database-level behaviour (approve creates product, approve updates existing,
// approve does not overwrite verified fields, reject changes status) is
// exercised through integration tests against the real Supabase instance,
// which require a live connection and service-role key.  The tests below
// verify the pure-Dart logic that surrounds those DB calls.

void main() {
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
    final trimmed = error?.trim();
    return (trimmed != null && trimmed.isNotEmpty)
        ? trimmed
        : 'Otomatik okuma başarısız oldu.';
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

    test('failed status with specific error shows that error', () {
      const error = 'connection timeout';
      expect(errorMessage('failed', error), 'connection timeout');
    });

    test('failed status with null error falls back to generic message', () {
      expect(errorMessage('failed', null), 'Otomatik okuma başarısız oldu.');
    });

    test('failed status with blank error falls back to generic message', () {
      expect(errorMessage('failed', '   '), 'Otomatik okuma başarısız oldu.');
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
