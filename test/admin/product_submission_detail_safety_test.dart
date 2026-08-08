import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/errors/user_message.dart';
import 'package:food_analyzer_app/features/admin/controllers/product_submission_review_controller.dart';
import 'package:food_analyzer_app/features/admin/pages/product_submission_detail_page.dart';
import 'package:food_analyzer_app/features/admin/repositories/product_submission_approval_repository.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_admin_review_service.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_merger.dart';
import 'package:food_analyzer_app/features/submission/models/product_submission.dart';

class _FakeApprovalRepository extends ProductSubmissionApprovalRepository {
  const _FakeApprovalRepository();

  @override
  Future<List<ProductSubmission>> fetchPendingSubmissions() async => const [];
}

class _RecordingApprovalRepository extends ProductSubmissionApprovalRepository {
  final ProductSubmission submission;
  ScoringEvidenceSnapshot? savedEvidence;
  Map<String, dynamic>? savedNutrition;

  _RecordingApprovalRepository(this.submission);

  @override
  Future<List<ProductSubmission>> fetchPendingSubmissions() async => const [];

  @override
  Future<ProductSubmission?> fetchById(String submissionId) async {
    return ProductSubmission(
      id: submission.id,
      barcode: submission.barcode,
      productName: submission.productName,
      brand: submission.brand,
      extractedIngredientsText: submission.extractedIngredientsText,
      extractedNutrition: savedNutrition ?? submission.extractedNutrition,
      scoringEvidence: savedEvidence ?? submission.scoringEvidence,
      extractionStatus: submission.extractionStatus,
      status: submission.status,
      source: submission.source,
      createdAt: submission.createdAt,
      updatedAt: submission.updatedAt,
    );
  }

  @override
  Future<void> saveScoringEvidenceReview(
    String submissionId, {
    required Map<String, dynamic>? reviewedNutrition,
    required ScoringEvidenceSnapshot evidence,
  }) async {
    savedNutrition = reviewedNutrition;
    savedEvidence = evidence;
  }

  @override
  Future<List<ScoringEvidenceConflict>> previewScoringEvidenceConflicts({
    required String barcode,
    required Map<String, dynamic>? reviewedNutrition,
    required ScoringEvidenceSnapshot incomingEvidence,
  }) async => const [];
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
    final energyKjField = tester.widget<TextField>(
      find.byKey(const ValueKey('submission-nutrition-energy_kj')),
    );
    expect(energyKjField.controller?.text, isEmpty);
    expect(fatField.controller?.text, '3.4');
    expect(servingField.controller?.text, '30 g');
    expect(
      find.byKey(const ValueKey('submission-nutrition-image')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('submission-scoring-evidence-section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('submission-scoring-readiness-preview')),
      findsOneWidget,
    );
    expect(find.textContaining('Etiketly 0'), findsNothing);
    expect(find.textContaining('A/B/C/D/E'), findsNothing);
    expect(find.textContaining('Nihai puan'), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Onayla'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Reddet'), findsOneWidget);
  });

  testWidgets('admin scoring evidence survives save and reload', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 8);
    const nutrition = {
      'energy_kj': 840.0,
      'energy_kcal': 200.0,
      'fat': 3.0,
      'saturated_fat': 1.0,
      'sugars': 5.0,
      'fiber': 2.0,
      'proteins': 4.0,
      'salt': 0.5,
      'sodium': 0.2,
    };
    final candidate = const ScoringEvidenceAdminReviewService()
        .build(
          ScoringEvidenceAdminDraft(
            reviewedNutrition: nutrition,
            ingredientText: 'su, şeker',
            nutritionBasis: NutritionBasis.per100g,
            productState: NutritionProductState.asSold,
            ingredientCompleteness: IngredientEvidenceCompleteness.complete,
            fvlState: CompositionPercentageState.known,
            fvlPercentage: 0,
            nnsState: PresenceEvidenceState.absent,
            category: ScoringCategory.generalFood,
            verifiedAt: now,
          ),
        )
        .evidence;
    final submission = ProductSubmission(
      id: 'submission-3',
      barcode: '8690000000003',
      productName: 'Kanıtlı Ürün',
      extractedIngredientsText: 'su, şeker',
      extractedNutrition: nutrition,
      scoringEvidence: candidate,
      extractionStatus: 'success',
      status: 'pending',
      source: 'barcode_missing',
      createdAt: now,
      updatedAt: now,
    );
    final repository = _RecordingApprovalRepository(submission);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productSubmissionApprovalRepositoryProvider.overrideWithValue(
            repository,
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
    final saveButton = find.byKey(
      const ValueKey('save-scoring-evidence-review'),
    );
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repository.savedEvidence, isNotNull);
    expect(
      repository.savedEvidence?.nutrition.energyKj.provenance,
      EvidenceProvenance.adminVerified,
    );
    expect(repository.savedNutrition?['energy_kj'], 840);
    expect(find.text('Puanlama verisi kaydedildi.'), findsOneWidget);
  });
}
