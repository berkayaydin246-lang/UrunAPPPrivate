import 'package:flutter_test/flutter_test.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_scoring_lifecycle.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/score_audit_write.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/category_derived_basis_resolver.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_public_score_audit_gate.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

import 'scoring_test_fixtures.dart';

/// Proves the controlled category-derived nutrition-basis fallback
/// (product decision) can carry a product all the way through the central
/// lifecycle write path to a publicly displayable numeric score, exactly
/// like declaredLabel/adminVerified evidence already can — and that its
/// provenance stays honestly `categoryDerived` throughout, never silently
/// relabeled. No production code under test here is modified by this file.
void main() {
  test(
    'category-derived basis (biscuit taxonomy tag) passes readiness, '
    'produces a current audit snapshot, and the public gate allows numeric '
    'display — with all other evidence otherwise sufficient',
    () async {
      // Deterministically resolved the SAME way
      // legacy_scoring_evidence_recovery.dart resolves it: from an
      // unambiguous taxonomy tag, never a product id/name.
      final resolvedBasis = const CategoryDerivedBasisResolver().resolve([
        'biskuvi',
      ]);
      expect(resolvedBasis, NutritionBasis.per100g);

      final input = completeInput(category: ScoringCategory.generalFood);
      final evidence = ScoringEvidenceSnapshot(
        nutritionBasis: resolvedBasis,
        nutritionBasisEvidence: EvidenceValue<NutritionBasis>(
          value: resolvedBasis,
          provenance: EvidenceProvenance.categoryDerived,
          verification: EvidenceVerification.verified,
        ),
        nutritionProductState: input.productState,
        nutrition: input.nutrition,
        fvlEvidence: input.fvlEvidence,
        nnsEvidence: input.nnsEvidence,
        ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness,
        categoryEvidence: input.categoryEvidence,
        classificationFacts: input.classificationFacts,
      );

      final readiness = const ScoringReadinessEvaluator().evaluate(
        evidence.toScoringInput(),
      );
      expect(readiness.isScorable, isTrue);

      final product = Product(
        id: 'category-derived-basis-p1',
        name: 'Category-Derived Basis Test Product',
        source: 'web_scraper:migros',
        sourceUrl: 'https://www.migros.com.tr/category-derived-p-abc123',
        verificationStatus: 'imported',
        ingredientsText: 'Su, şeker, tuz',
        nutritionText: '{"energy_kcal": 100}',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final dataSource = _MemoryLifecycleDataSource(
        product: product,
        catalogue: [
          Ingredient(
            id: 'category-derived-ordinary-su',
            name: 'Su',
            normalizedName: 'su',
            riskLevel: 'low',
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      final lifecycle = ProductScoringLifecycleService(dataSource: dataSource);

      final result = await lifecycle.processCurrent(
        product.id,
        triggerSource: ScoreAuditTriggerSource.catalogueChange,
        evidenceResolver: (currentProduct, catalogue) async {
          return ProductScoringEvidenceResolution(
            evidence: evidence,
            blockerReasons: const [],
          );
        },
      );

      expect(result.finalScoreReady, isTrue);
      expect(result.auditStatus, ProductScoringAuditStatus.inserted);
      expect(dataSource.audits, hasLength(1));

      final current = dataSource.audits.single;
      expect(
        current.resolvedInput.nutritionBasisProvenance,
        'categoryDerived',
        reason: 'the real provenance is persisted into the audit snapshot, '
            'never silently relabeled as declaredLabel',
      );

      const gate = EtiketlyPublicScoreAuditGate();
      final decision = gate.evaluate(current: current, trusted: current);
      expect(decision.status, PublicScoreAuditStatus.matching);
      expect(decision.mayDisplayNumericScore, isTrue);
    },
  );

  test(
    'an ambiguous/unresolved category (no allowlisted tag) never produces a '
    'displayable score, even with otherwise identical evidence',
    () async {
      final unresolved = const CategoryDerivedBasisResolver().resolve([
        'sos',
      ]);
      expect(unresolved, NutritionBasis.unknown);

      final input = completeInput(category: ScoringCategory.generalFood);
      final evidence = ScoringEvidenceSnapshot(
        nutritionBasis: unresolved,
        nutritionBasisEvidence: null,
        nutritionProductState: input.productState,
        nutrition: input.nutrition,
        fvlEvidence: input.fvlEvidence,
        nnsEvidence: input.nnsEvidence,
        ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness,
        categoryEvidence: input.categoryEvidence,
        classificationFacts: input.classificationFacts,
      );

      final readiness = const ScoringReadinessEvaluator().evaluate(
        evidence.toScoringInput(),
      );
      expect(readiness.isScorable, isFalse);
    },
  );
}

/// In-memory [ProductScoringLifecycleDataSource] — same shape as the
/// established fake in product_scoring_lifecycle_test.dart, duplicated
/// locally rather than shared, matching this codebase's existing
/// convention of small per-test-file fakes.
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
