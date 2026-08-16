import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_admin_review_service.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_evidence_ocr_candidate_builder.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

/// Forward-path verification (NOT a legacy recovery / basis-remediation
/// pass): proves the CURRENT, already-shipped ingestion pipeline correctly
/// carries an explicit product-label OCR basis suggestion all the way to a
/// publicly displayable numeric score, through the SAME trusted-basis
/// contract the legacy remediation work established —
/// ScoringEvidenceOcrCandidateBuilder (OCR, always `ocrDeclaredLabel` /
/// `unverified`) -> ScoringEvidenceAdminReviewService (admin confirmation,
/// `adminVerified` / `verified`) -> ProductScoringLifecycleService (the
/// single write path) -> EtiketlyPublicScoreAuditGate (the single display
/// gate). No production code under test here is modified by this file.
void main() {
  const nutritionValues = {
    'energy_kj': 420,
    'saturated_fat': 2,
    'sugars': 4,
    'salt': 0.4,
    'proteins': 6,
    'fiber': 3,
  };
  const ingredientsText = 'Su, şeker, tuz';

  test(
    'A. explicit OCR per_100g, admin-confirmed, sufficient evidence -> '
    'current audit snapshot exists AND the public gate allows numeric '
    'display',
    () async {
      // Step 1: the product-label OCR response reaches the scoring
      // evidence model as a CANDIDATE only.
      final ocrCandidate = const ScoringEvidenceOcrCandidateBuilder().build(
        nutrition: nutritionValues,
        evidenceCandidates: const {'nutrition_basis': 'per100g'},
        ingredientsText: ingredientsText,
      );
      expect(ocrCandidate, isNotNull);
      expect(ocrCandidate!.nutritionBasisEvidence?.value, NutritionBasis.per100g);
      expect(
        ocrCandidate.nutritionBasisEvidence?.provenance,
        EvidenceProvenance.ocrDeclaredLabel,
        reason: 'OCR alone is never trusted — see docs/scoring/README.md',
      );
      expect(
        ocrCandidate.nutritionBasisEvidence?.verification,
        EvidenceVerification.unverified,
      );

      // The raw OCR candidate, standing alone, must NOT be scorable yet —
      // ScoringEvidenceSnapshot.toScoringInput() degrades an untrusted
      // basis provenance to NutritionBasis.unknown before readiness is
      // ever evaluated (the frozen trusted-basis contract).
      const readinessEvaluator = ScoringReadinessEvaluator();
      final ocrOnlyReadiness = readinessEvaluator.evaluate(
        ocrCandidate.toScoringInput(),
      );
      expect(
        ocrOnlyReadiness.isScorable,
        isFalse,
        reason: 'an admin-unconfirmed OCR suggestion must never itself '
            'produce a scoreable input',
      );

      // Step 2: admin reviews and confirms — the ONLY mechanism that
      // upgrades ocrDeclaredLabel/unverified to a trusted provenance.
      final review = const ScoringEvidenceAdminReviewService().build(
        ScoringEvidenceAdminDraft(
          reviewedNutrition: nutritionValues,
          ingredientText: ingredientsText,
          nutritionBasis: ocrCandidate.nutritionBasisEvidence!.value!,
          productState: NutritionProductState.asSold,
          ingredientCompleteness: IngredientEvidenceCompleteness.complete,
          fvlState: CompositionPercentageState.provenAbsent,
          nnsState: PresenceEvidenceState.absent,
          category: ScoringCategory.generalFood,
          verifiedBy: 'admin-1',
          verifiedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(review.isValid, isTrue, reason: review.validationIssues.join(', '));
      expect(
        review.evidence.nutritionBasisEvidence?.provenance,
        EvidenceProvenance.adminVerified,
      );
      expect(
        review.evidence.nutritionBasisEvidence?.verification,
        EvidenceVerification.verified,
      );
      expect(review.readiness.isScorable, isTrue);

      // Step 3: the central lifecycle service is the single write path.
      final product = _productWithoutEvidence(id: 'forward-scan-consistent');
      final dataSource = _MemoryLifecycleDataSource(
        product: product,
        catalogue: [_ordinaryIngredient()],
      );
      final lifecycle = ProductScoringLifecycleService(dataSource: dataSource);

      final result = await lifecycle.processCurrent(
        product.id,
        triggerSource: ScoreAuditTriggerSource.verifiedCorrection,
        evidenceResolver: (currentProduct, catalogue) async {
          return ProductScoringEvidenceResolution(
            evidence: review.evidence,
            blockerReasons: const [],
          );
        },
      );

      expect(result.evidenceStatus, ProductScoringEvidenceStatus.persisted);
      expect(result.finalScoreReady, isTrue);
      expect(result.auditStatus, ProductScoringAuditStatus.inserted);
      expect(result.calculatedScore, isNotNull);
      expect(dataSource.audits, hasLength(1));

      // Step 4: public displayability is governed ONLY by the frozen
      // public audit gate.
      final current = dataSource.audits.single;
      const gate = EtiketlyPublicScoreAuditGate();
      final decision = gate.evaluate(current: current, trusted: current);
      expect(decision.status, PublicScoreAuditStatus.matching);
      expect(decision.mayDisplayNumericScore, isTrue);
    },
  );

  test(
    'B. generic/unknown OCR basis never reaches a public numeric score, '
    'even with otherwise sufficient evidence',
    () async {
      // The product-label OCR response never named an explicit basis
      // (e.g. only a combined/generic declaration was on the label) — the
      // candidate builder correctly produces no basis evidence at all.
      final ocrCandidate = const ScoringEvidenceOcrCandidateBuilder().build(
        nutrition: nutritionValues,
        evidenceCandidates: const {'nutrition_basis': 'unknown'},
        ingredientsText: ingredientsText,
      );
      expect(
        ocrCandidate?.nutritionBasisEvidence,
        isNull,
        reason: 'a generic/unknown OCR basis must never be treated as '
            'evidence at all',
      );

      // Even when everything else about this product is otherwise fully
      // reviewed/trusted, missing basis alone must block the score.
      final review = const ScoringEvidenceAdminReviewService().build(
        ScoringEvidenceAdminDraft(
          reviewedNutrition: nutritionValues,
          ingredientText: ingredientsText,
          nutritionBasis: NutritionBasis.unknown,
          productState: NutritionProductState.asSold,
          ingredientCompleteness: IngredientEvidenceCompleteness.complete,
          fvlState: CompositionPercentageState.provenAbsent,
          nnsState: PresenceEvidenceState.absent,
          category: ScoringCategory.generalFood,
          verifiedBy: 'admin-1',
          verifiedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(review.evidence.nutritionBasisEvidence, isNull);
      expect(review.readiness.isScorable, isFalse);

      final product = _productWithoutEvidence(id: 'forward-scan-generic-basis');
      final dataSource = _MemoryLifecycleDataSource(
        product: product,
        catalogue: [_ordinaryIngredient()],
      );
      final lifecycle = ProductScoringLifecycleService(dataSource: dataSource);

      final result = await lifecycle.processCurrent(
        product.id,
        triggerSource: ScoreAuditTriggerSource.verifiedCorrection,
        evidenceResolver: (currentProduct, catalogue) async {
          return ProductScoringEvidenceResolution(
            evidence: review.evidence,
            blockerReasons: const ['nutrition:unknownNutritionBasis'],
          );
        },
      );

      expect(result.finalScoreReady, isFalse);
      expect(result.auditStatus, isNot(ProductScoringAuditStatus.inserted));
      expect(
        dataSource.audits,
        isEmpty,
        reason: 'no current audit snapshot may ever be created for an '
            'unscoreable product',
      );
    },
  );
}

Product _productWithoutEvidence({required String id}) {
  return Product(
    id: id,
    name: 'Forward Scan Test Product',
    source: 'web_scraper:migros',
    sourceUrl: 'https://www.migros.com.tr/forward-scan-p-abc123',
    verificationStatus: 'imported',
    ingredientsText: 'Su, şeker, tuz',
    nutritionText: '{"energy_kcal": 100}',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

Ingredient _ordinaryIngredient() {
  return Ingredient(
    id: 'forward-scan-ordinary-su',
    name: 'Su',
    normalizedName: 'su',
    riskLevel: 'low',
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}

/// In-memory [ProductScoringLifecycleDataSource] — same shape as the
/// established fake in product_scoring_lifecycle_test.dart, duplicated
/// locally (private to that file) rather than shared, matching this
/// codebase's existing convention of small per-test-file fakes.
class _MemoryLifecycleDataSource implements ProductScoringLifecycleDataSource {
  _MemoryLifecycleDataSource({
    required this.product,
    required List<Ingredient> catalogue,
  }) : catalogue = [...catalogue];

  Product product;
  final List<Ingredient> catalogue;
  final List<EtiketlyScoreAuditSnapshot> audits = [];

  @override
  Future<Product?> fetchProduct(String productId) async {
    return product.id == productId ? product : null;
  }

  @override
  Future<List<Ingredient>> fetchIngredientCatalogue() async => catalogue;

  @override
  Future<bool> writeScoringEvidence(
    String productId,
    ScoringEvidenceSnapshot evidence, {
    required ScoringEvidenceSnapshot? expectedCurrent,
  }) async {
    if (product.id != productId) return false;
    product = Product(
      id: product.id,
      barcode: product.barcode,
      name: product.name,
      normalizedName: product.normalizedName,
      brand: product.brand,
      categoryId: product.categoryId,
      imageUrl: product.imageUrl,
      ingredientsText: product.ingredientsText,
      nutritionText: product.nutritionText,
      source: product.source,
      sourceUrl: product.sourceUrl,
      verificationStatus: product.verificationStatus,
      searchKeywords: product.searchKeywords,
      categoryTags: product.categoryTags,
      canonicalCategory: product.canonicalCategory,
      canonicalSubcategory: product.canonicalSubcategory,
      scoringEvidence: evidence,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt.add(const Duration(seconds: 1)),
    );
    return true;
  }

  @override
  Future<EtiketlyScoreAuditSnapshot?> fetchMatchingSnapshot(
    EtiketlyScoreAuditSnapshot current,
  ) async {
    return audits
        .where(
          (snapshot) =>
              snapshot.productId == current.productId &&
              snapshot.inputFingerprint == current.inputFingerprint &&
              snapshot.scoreVersion == current.scoreVersion &&
              snapshot.nutritionMethodologyVersion ==
                  current.nutritionMethodologyVersion &&
              snapshot.nutritionTransformVersion ==
                  current.nutritionTransformVersion &&
              snapshot.additiveTransformVersion == current.additiveTransformVersion,
        )
        .lastOrNull;
  }

  @override
  Future<ScoreAuditSnapshotWriteResult> insertSnapshot(
    EtiketlyScoreAuditSnapshot snapshot, {
    required ScoreAuditTriggerSource triggerSource,
  }) async {
    final existing = await fetchMatchingSnapshot(snapshot);
    if (existing != null) {
      return const ScoreAuditSnapshotWriteResult(
        snapshotId: 'existing',
        inserted: false,
      );
    }
    audits.add(snapshot);
    return ScoreAuditSnapshotWriteResult(
      snapshotId: 'snapshot-${audits.length}',
      inserted: true,
    );
  }
}
