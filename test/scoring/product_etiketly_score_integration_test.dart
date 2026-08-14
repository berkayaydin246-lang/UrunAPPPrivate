import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/core/theme/app_theme.dart';
import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/controllers/product_detail_controller.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/product/models/product_review.dart';
import 'package:food_analyzer_app/features/product/product_page.dart';
import 'package:food_analyzer_app/features/product/repositories/product_repository.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/application/product_score_audit_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/controllers/product_etiketly_score_controller.dart';
import 'package:food_analyzer_app/features/scoring/data/score_audit_snapshot_repository.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/validated_nutrition_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_snapshot_builder.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_readiness_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_raw_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';
import 'package:food_analyzer_app/features/scoring/widgets/etiketly_score_card.dart';
import 'package:food_analyzer_app/features/user_library/repositories/user_product_library_repository.dart';

import 'scoring_test_fixtures.dart';
import 'support/additive_quality_test_support.dart';

void main() {
  const orchestrator = ProductEtiketlyScoreOrchestrator();

  group('Product Detail Etiketly score integration', () {
    testWidgets(
      '21. fully scoring-ready Product Detail displays a real score',
      (tester) async {
        final input = completeInput();
        final product = _productFromInput(input);
        final repository = _FakeProductRepository(
          product: product,
          allIngredients: [_ordinaryIngredient()],
        );
        final auditSnapshot = _matchingAuditSnapshot(product);

        await _pumpProductScreen(
          tester,
          repository,
          auditSnapshot: auditSnapshot,
        );

        expect(
          find.byKey(const ValueKey('etiketly-score-calculated')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('etiketly-score-value')),
          findsOneWidget,
        );
        expect(repository.getAllIngredientsCalls, 1);
      },
    );

    testWidgets(
      'ordinary unmatched food with matching audit displays numeric score',
      (tester) async {
        final product = _productFromInput(
          completeInput(),
          ingredientsText: 'Pirinç unu',
        );
        final catalogue = [_ordinaryIngredient()];
        final repository = _FakeProductRepository(
          product: product,
          allIngredients: catalogue,
        );
        final audit = await const ProductScoreAuditEvaluator().evaluate(
          product,
          catalogue,
        );

        expect(audit.additiveReady, isTrue);
        expect(audit.finalScoreReady, isTrue);
        await _pumpProductScreen(
          tester,
          repository,
          auditSnapshot: audit.snapshot,
        );

        expect(
          find.byKey(const ValueKey('etiketly-score-calculated')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('etiketly-score-value')),
          findsOneWidget,
        );
        expect(repository.getAllIngredientsCalls, 1);
      },
    );

    testWidgets('unresolved E-code still blocks Product Detail score', (
      tester,
    ) async {
      final product = _productFromInput(
        completeInput(),
        ingredientsText: 'E9999',
      );
      final catalogue = [_ordinaryIngredient()];
      final repository = _FakeProductRepository(
        product: product,
        allIngredients: catalogue,
      );
      final audit = await const ProductScoreAuditEvaluator().evaluate(
        product,
        catalogue,
      );

      expect(audit.additiveReady, isFalse);
      expect(audit.finalScoreReady, isFalse);
      await _pumpProductScreen(tester, repository);

      _expectUnavailableWithoutNumber();
      expect(
        find.text('Bazı katkı maddeleri henüz doğrulanmamış.'),
        findsOneWidget,
      );
    });

    test(
      'score provider assessment and audit evaluator build matching snapshots',
      () async {
        final product = _productFromInput(
          completeInput(),
          ingredientsText: 'Pirinç unu',
        );
        final catalogue = [_ordinaryIngredient()];
        final repository = _FakeProductRepository(
          product: product,
          allIngredients: catalogue,
        );
        final container = ProviderContainer(
          overrides: [productRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        final providerAssessment = await container.read(
          productScoringAdditiveAssessmentProvider(product.id).future,
        );
        final providerEvaluation = orchestrator.calculate(
          product: product,
          canonicalAssessment: providerAssessment,
        )!;
        final providerSnapshot = const EtiketlyScoreAuditSnapshotBuilder()
            .build(product: product, evaluation: providerEvaluation);
        final auditEvaluation = await const ProductScoreAuditEvaluator()
            .evaluate(product, catalogue);

        expect(providerEvaluation.isCalculated, isTrue);
        expect(auditEvaluation.finalScoreReady, isTrue);
        expect(
          providerSnapshot.finalScore,
          auditEvaluation.snapshot!.finalScore,
        );
        expect(
          providerSnapshot.inputFingerprint,
          auditEvaluation.snapshot!.inputFingerprint,
        );
      },
    );

    testWidgets(
      'audit 22. scoring-ready product without audit shows no number',
      (tester) async {
        final product = _productFromInput(completeInput());
        final repository = _FakeProductRepository(
          product: product,
          allIngredients: [_ordinaryIngredient()],
        );

        await _pumpProductScreen(tester, repository);

        _expectUnavailableWithoutNumber();
        expect(find.text('Puan kaydı güncelleniyor.'), findsOneWidget);
      },
    );

    testWidgets('audit 23. stale fingerprint shows no number', (tester) async {
      final product = _productFromInput(completeInput());
      final staleProduct = Product(
        id: product.id,
        name: product.name,
        ingredientsText: 'Yulaf ezmesi, su',
        nutritionText: product.nutritionText,
        verificationStatus: product.verificationStatus,
        scoringEvidence: product.scoringEvidence,
        createdAt: product.createdAt,
        updatedAt: product.updatedAt,
      );
      final repository = _FakeProductRepository(
        product: product,
        allIngredients: [_ordinaryIngredient()],
      );

      await _pumpProductScreen(
        tester,
        repository,
        auditSnapshot: _matchingAuditSnapshot(staleProduct),
      );

      _expectUnavailableWithoutNumber();
      expect(find.text('Puan kaydı güncelleniyor.'), findsOneWidget);
    });

    testWidgets('audit 24. invalid audit shows no number', (tester) async {
      final product = _productFromInput(completeInput());
      final json = _matchingAuditSnapshot(product).toJson()
        ..['final_score'] = 99.0;
      final invalid = EtiketlyScoreAuditSnapshot.tryFromJson(json)!;
      final repository = _FakeProductRepository(
        product: product,
        allIngredients: [_ordinaryIngredient()],
      );

      await _pumpProductScreen(tester, repository, auditSnapshot: invalid);

      _expectUnavailableWithoutNumber();
      expect(find.text('Puan kaydı güncelleniyor.'), findsOneWidget);
    });

    testWidgets('22. displayed score equals the real final calculator result', (
      tester,
    ) async {
      final input = completeInput();
      final product = _productFromInput(input);
      final assessment = assessmentForCodes(const ['E211']);
      final state = orchestrator.evaluate(
        product: product,
        canonicalAssessment: assessment,
      );
      final expected = _calculateExpected(input, assessment);

      await _pumpScoreCard(tester, state);

      expect(state.displayScore, expected);
      expect(_displayedScore(tester), '$expected');
      expect(
        find.text('Etiketly katkı değerlendirmesi: 1 orta düzey.'),
        findsOneWidget,
      );
    });

    testWidgets('23. incomplete nutrition evidence is unavailable', (
      tester,
    ) async {
      final input = completeInput(
        nutrition: completeNutrition(includeSugars: false),
      );

      await _pumpScoreCard(
        tester,
        orchestrator.evaluate(
          product: _productFromInput(input),
          canonicalAssessment: ordinaryAssessment(),
        ),
      );

      _expectUnavailableWithoutNumber();
      expect(
        find.text('Gerekli besin değerleri eksik veya doğrulanmamış.'),
        findsOneWidget,
      );
    });

    testWidgets('24. missing fiber is unavailable', (tester) async {
      final input = completeInput(
        nutrition: completeNutrition(includeFiber: false),
      );

      await _pumpScoreCard(
        tester,
        orchestrator.evaluate(
          product: _productFromInput(input),
          canonicalAssessment: ordinaryAssessment(),
        ),
      );

      _expectUnavailableWithoutNumber();
      expect(find.text('Lif bilgisi eksik.'), findsOneWidget);
    });

    testWidgets('25. unknown nutrition basis is unavailable', (tester) async {
      final input = completeInput(basis: NutritionBasis.unknown);

      await _pumpScoreCard(
        tester,
        orchestrator.evaluate(
          product: _productFromInput(input),
          canonicalAssessment: ordinaryAssessment(),
        ),
      );

      _expectUnavailableWithoutNumber();
      expect(
        find.text('Besin değerlerinin 100 g / 100 ml temeli doğrulanmamış.'),
        findsOneWidget,
      );
    });

    testWidgets('26. incomplete ingredient list is unavailable', (
      tester,
    ) async {
      final input = completeInput(
        ingredientCompleteness: IngredientEvidenceCompleteness.incomplete,
      );

      await _pumpScoreCard(
        tester,
        orchestrator.evaluate(
          product: _productFromInput(input),
          canonicalAssessment: ordinaryAssessment(),
        ),
      );

      _expectUnavailableWithoutNumber();
      expect(find.text('İçerik listesi tam doğrulanmamış.'), findsOneWidget);
    });

    testWidgets('27. unresolved additive evidence is unavailable', (
      tester,
    ) async {
      final input = completeInput();

      await _pumpScoreCard(
        tester,
        orchestrator.evaluate(
          product: _productFromInput(input),
          canonicalAssessment: unresolvedAssessment(),
        ),
      );

      _expectUnavailableWithoutNumber();
      expect(
        find.text('Bazı katkı maddeleri henüz doğrulanmamış.'),
        findsOneWidget,
      );
    });

    testWidgets('28. unknown additive risk is unavailable', (tester) async {
      final input = completeInput();
      final unknownAdditive = const CanonicalIngredientRiskService()
          .assessIngredients([
            reviewedIngredientForCode(
              'E999',
              riskLevel: 'unknown',
              additiveGroup: 'koruyucu',
            ),
          ]);

      await _pumpScoreCard(
        tester,
        orchestrator.evaluate(
          product: _productFromInput(input),
          canonicalAssessment: unknownAdditive,
        ),
      );

      _expectUnavailableWithoutNumber();
      expect(
        find.text('Bazı katkı maddeleri henüz doğrulanmamış.'),
        findsOneWidget,
      );
    });

    testWidgets('29. ordinary recognized ingredient does not block score', (
      tester,
    ) async {
      final state = orchestrator.evaluate(
        product: _productFromInput(completeInput()),
        canonicalAssessment: ordinaryAssessment(),
      );

      await _pumpScoreCard(tester, state);

      expect(state.isCalculated, isTrue);
      expect(
        find.byKey(const ValueKey('etiketly-score-calculated')),
        findsOneWidget,
      );
    });

    testWidgets('30. complete zero-additive product displays a score', (
      tester,
    ) async {
      final state = orchestrator.evaluate(
        product: _productFromInput(completeInput()),
        canonicalAssessment: ordinaryAssessment(),
      );

      await _pumpScoreCard(tester, state);

      expect(state.isCalculated, isTrue);
      expect(
        find.text(
          'Etiketly katkı değerlendirmesi: puanlamaya dahil edilen katkı bulunmadı.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('31. qualifying beverage NNS is not double penalized', (
      tester,
    ) async {
      final input = completeInput(
        category: ScoringCategory.beverage,
        nnsEvidence: const PresenceEvidence.present(
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
        ),
      );
      final state = orchestrator.evaluate(
        product: _productFromInput(input),
        canonicalAssessment: assessmentForCodes(const [
          'E951',
        ], category: ScoringCategory.beverage),
      );

      await _pumpScoreCard(tester, state);

      expect(state.isCalculated, isTrue);
      expect(state.additiveDisplayScore, 100);
      expect(
        find.byKey(const ValueKey('etiketly-nns-overlap-note')),
        findsOneWidget,
      );
    });

    testWidgets('32. legacy Product Detail still renders without a score', (
      tester,
    ) async {
      final product = _legacyProduct();
      final repository = _FakeProductRepository(
        product: product,
        allIngredients: [_ordinaryIngredient()],
      );

      await _pumpProductScreen(tester, repository);

      expect(find.text(product.name), findsOneWidget);
      expect(find.text('Etiketly Puanı hesaplanamadı'), findsOneWidget);
      expect(find.byKey(const ValueKey('etiketly-score-value')), findsNothing);
      expect(find.byKey(const Key('product-report-card')), findsOneWidget);
    });

    testWidgets(
      'generic flavouring does not produce an additive unavailable reason',
      (tester) async {
        final product = _legacyProduct(ingredientsText: 'aroma vericiler');
        final repository = _FakeProductRepository(product: product);

        await _pumpProductScreen(tester, repository);

        expect(
          find.text('Bazı katkı maddeleri henüz doğrulanmamış.'),
          findsNothing,
        );
        expect(
          find.text('Gerekli puanlama kanıtları henüz tamamlanmamış.'),
          findsOneWidget,
        );
        expect(
          find.text('Besin değerlerinin 100 g / 100 ml temeli doğrulanmamış.'),
          findsNothing,
        );
        expect(
          find.text('Ürünün puanlama kategorisi henüz doğrulanmamış.'),
          findsNothing,
        );
        expect(
          find.text('Ürünün değerlendirme durumu henüz doğrulanmamış.'),
          findsNothing,
        );
      },
    );

    testWidgets('33. scoring error does not break Product Detail', (
      tester,
    ) async {
      final product = _productFromInput(completeInput());
      final repository = _FakeProductRepository(
        product: product,
        allIngredientsError: StateError('DioException secret payload'),
      );

      await _pumpProductScreen(tester, repository);

      expect(find.text(product.name), findsOneWidget);
      expect(find.text('Puan şu anda hesaplanamadı.'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing);
      expect(find.byKey(const Key('product-report-card')), findsOneWidget);
    });
  });
}

int _calculateExpected(
  EtiketlyScoringInput input,
  CanonicalAdditiveAssessment assessment,
) {
  final nutritionReadiness = const ScoringReadinessEvaluator().evaluate(input);
  final raw = const NutritionRawScoreCalculator().calculate(
    ValidatedNutritionScoringInput.validate(input),
  );
  final nutritionQuality = const NutritionQualityTransformer().transform(raw);
  final additiveQuality = const AdditiveQualityTransformer().transform(
    assessment,
  );
  final finalReadiness = const EtiketlyScoreReadinessEvaluator().evaluate(
    nutritionReadiness: nutritionReadiness,
    ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness,
    additiveQuality: additiveQuality,
  );
  return const EtiketlyScoreCalculator()
      .calculate(
        nutritionQuality: nutritionQuality,
        additiveQuality: additiveQuality,
        readiness: finalReadiness,
      )
      .futureDisplayScore!;
}

Product _productFromInput(
  EtiketlyScoringInput input, {
  String ingredientsText = 'Yulaf ezmesi',
}) {
  final now = DateTime.utc(2026, 8, 8);
  return Product(
    id: 'score-product',
    name: 'Yulaflı Test Ürünü',
    brand: 'Etiketly Test',
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(const {
      'energy_kcal': 100,
      'fat': 8,
      'saturated_fat': 2,
      'sugars': 4,
      'proteins': 6,
      'fiber': 3,
      'salt': 0.4,
    }),
    verificationStatus: 'verified',
    scoringEvidence: ScoringEvidenceSnapshot(
      nutritionBasis: input.nutritionBasis,
      nutritionProductState: input.productState,
      nutrition: input.nutrition,
      fvlEvidence: input.fvlEvidence,
      nnsEvidence: input.nnsEvidence,
      ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness,
      categoryEvidence: input.categoryEvidence,
      classificationFacts: input.classificationFacts,
    ),
    createdAt: now,
    updatedAt: now,
  );
}

Product _legacyProduct({String ingredientsText = 'Yulaf ezmesi'}) {
  final now = DateTime.utc(2026, 8, 8);
  return Product(
    id: 'score-product',
    name: 'Eski Katalog Ürünü',
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(const {'energy_kcal': 100, 'fiber': 3}),
    verificationStatus: 'verified',
    createdAt: now,
    updatedAt: now,
  );
}

Ingredient _ordinaryIngredient() {
  final now = DateTime.utc(2026, 8, 8);
  return Ingredient(
    id: 'ordinary-oats',
    name: 'Yulaf ezmesi',
    normalizedName: 'yulaf ezmesi',
    riskLevel: 'low',
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpScoreCard(
  WidgetTester tester,
  ProductEtiketlyScoreState state,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme(useGoogleFonts: false),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: EtiketlyScoreCard(state: state),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpProductScreen(
  WidgetTester tester,
  _FakeProductRepository repository, {
  EtiketlyScoreAuditSnapshot? auditSnapshot,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        productRepositoryProvider.overrideWithValue(repository),
        scoreAuditSnapshotRepositoryProvider.overrideWithValue(
          _FakeAuditSnapshotRepository(auditSnapshot),
        ),
        userProductLibraryStorageProvider.overrideWithValue(_MemoryStorage()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme(useGoogleFonts: false),
        home: const ProductScreen(productId: 'score-product'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

EtiketlyScoreAuditSnapshot _matchingAuditSnapshot(Product product) {
  final assessment = const CanonicalIngredientRiskService().assessIngredients([
    _ordinaryIngredient(),
  ]);
  final evaluation = const ProductEtiketlyScoreOrchestrator().calculate(
    product: product,
    canonicalAssessment: assessment,
  )!;
  return const EtiketlyScoreAuditSnapshotBuilder().build(
    product: product,
    evaluation: evaluation,
  );
}

String _displayedScore(WidgetTester tester) {
  return tester
      .widget<Text>(find.byKey(const ValueKey('etiketly-score-value')))
      .data!;
}

void _expectUnavailableWithoutNumber() {
  expect(
    find.byKey(const ValueKey('etiketly-score-unavailable')),
    findsOneWidget,
  );
  expect(find.byKey(const ValueKey('etiketly-score-value')), findsNothing);
}

class _FakeProductRepository extends ProductRepository {
  _FakeProductRepository({
    required this.product,
    this.allIngredients = const [],
    this.allIngredientsError,
  });

  final Product product;
  final List<Ingredient> allIngredients;
  final Object? allIngredientsError;
  int _allIngredientCalls = 0;

  int get getAllIngredientsCalls => _allIngredientCalls;

  @override
  Future<Product?> getProductById(String id) async {
    return id == product.id ? product : null;
  }

  @override
  Future<ProductReview?> getProductReviewByProductId(String productId) async {
    return null;
  }

  @override
  Future<List<Ingredient>> getProductIngredients(String productId) async {
    return const [];
  }

  @override
  Future<List<Ingredient>> getAllIngredients() async {
    _allIngredientCalls++;
    final error = allIngredientsError;
    if (error != null) throw error;
    return allIngredients;
  }
}

class _MemoryStorage implements UserProductLibraryStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }
}

class _FakeAuditSnapshotRepository implements ScoreAuditSnapshotRepository {
  const _FakeAuditSnapshotRepository(this.snapshot);

  final EtiketlyScoreAuditSnapshot? snapshot;

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatching(
    EtiketlyScoreAuditSnapshot current,
  ) async => snapshot;

  @override
  Future<ScoreAuditSnapshotWriteResult> insertTrusted(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  }) {
    throw UnsupportedError('Widget test repository is read-only.');
  }
}
