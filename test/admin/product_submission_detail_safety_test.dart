import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/admin/controllers/product_submission_review_controller.dart';
import 'package:food_analyzer_app/features/admin/pages/product_submission_detail_page.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_submission_approval_repository.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';

class _FakeApprovalRepository extends ProductSubmissionApprovalRepository {
  const _FakeApprovalRepository();

  @override
  Future<List<ProductSubmission>> fetchPendingSubmissions() async => const [];
}

void main() {
  testWidgets(
    'failed submission hides raw OCR error and remains manually reviewable',
    (tester) async {
      final now = DateTime(2026, 8, 8);
      final submission = ProductSubmission(
        id: 'submission-1',
        barcode: '8690000000001',
        productName: 'Test Ürünü',
        brand: 'Test Marka',
        frontImageUrl: 'https://cdn.example/front.jpg',
        labelImageUrl: 'https://cdn.example/label.jpg',
        extractionStatus: 'failed',
        extractionError:
            'DioException [bad response]: status code of 401. '
            'See https://developer.mozilla.org and RequestOptions.',
        status: 'pending',
        source: 'barcode_missing',
        createdAt: now,
        updatedAt: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productSubmissionApprovalRepositoryProvider.overrideWithValue(
              const _FakeApprovalRepository(),
            ),
          ],
          child: MaterialApp(
            home: ProductSubmissionDetailPage(
              submissionId: submission.id,
              submission: submission,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('DioException'), findsNothing);
      expect(find.textContaining('developer.mozilla.org'), findsNothing);
      expect(find.textContaining('status code'), findsNothing);
      expect(find.textContaining('RequestOptions'), findsNothing);
      expect(find.textContaining('OCR servisi doğrulanamadı'), findsOneWidget);
      expect(find.text(UserMessage.submissionOcrAuth), findsOneWidget);
      expect(
        find.byKey(const ValueKey('submission-missing-nutrition')),
        findsOneWidget,
      );
      final energyField = tester.widget<TextField>(
        find.byKey(const ValueKey('submission-nutrition-energy_kcal')),
      );
      expect(energyField.controller?.text, isEmpty);
      expect(find.text('null'), findsNothing);
      expect(find.text('NaN'), findsNothing);
      expect(
        find.byKey(const ValueKey('submission-front-image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('submission-label-image')),
        findsOneWidget,
      );
      expect(find.widgetWithText(ElevatedButton, 'Onayla'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Reddet'), findsOneWidget);
    },
  );

  testWidgets('nutrition values and optional image are editable for review', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 8);
    final submission = ProductSubmission(
      id: 'submission-2',
      barcode: '8690000000002',
      productName: 'Besinli Ürün',
      brand: 'Test Marka',
      frontImageUrl: 'https://cdn.example/front.jpg',
      labelImageUrl: 'https://cdn.example/label.jpg',
      nutritionImageUrl: 'https://cdn.example/nutrition.jpg',
      extractedIngredientsText: 'su, şeker',
      extractedNutrition: const {
        'energy_kcal': 193.0,
        'fat': 3.4,
        'saturated_fat': 1.2,
        'carbohydrates': 27.0,
        'sugars': 5.5,
        'fiber': 2.0,
        'proteins': 8.0,
        'salt': 0.7,
        'sodium': 0.28,
        'serving_size': '30 g',
      },
      extractionStatus: 'success',
      status: 'pending',
      source: 'barcode_missing',
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productSubmissionApprovalRepositoryProvider.overrideWithValue(
            const _FakeApprovalRepository(),
          ),
        ],
        child: MaterialApp(
          home: ProductSubmissionDetailPage(
            submissionId: submission.id,
            submission: submission,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('submission-missing-nutrition')),
      findsNothing,
    );
    final energyField = tester.widget<TextField>(
      find.byKey(const ValueKey('submission-nutrition-energy_kcal')),
    );
    final fatField = tester.widget<TextField>(
      find.byKey(const ValueKey('submission-nutrition-fat')),
    );
    final servingField = tester.widget<TextField>(
      find.byKey(const ValueKey('submission-nutrition-serving-size')),
    );
    expect(energyField.controller?.text, '193');
    expect(fatField.controller?.text, '3.4');
    expect(servingField.controller?.text, '30 g');
    expect(
      find.byKey(const ValueKey('submission-nutrition-image')),
      findsOneWidget,
    );
    expect(find.widgetWithText(ElevatedButton, 'Onayla'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reddet'), findsOneWidget);
  });
}
