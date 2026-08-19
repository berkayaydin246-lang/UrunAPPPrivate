import 'dart:convert';

import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_snapshot_builder.dart';

import '../scoring_test_fixtures.dart';

Product auditProductFromInput(
  EtiketlyScoringInput input, {
  String id = 'audit-product',
  String name = 'Audit Test Product',
  String? barcode = '8690000000001',
  String ingredientsText = 'Su',
  String? brand = 'Test Brand',
  String? imageUrl,
  String? source,
  DateTime? updatedAt,
}) {
  final timestamp = updatedAt ?? DateTime.utc(2026, 8, 8);
  return Product(
    id: id,
    barcode: barcode,
    name: name,
    brand: brand,
    imageUrl: imageUrl,
    ingredientsText: ingredientsText,
    nutritionText: jsonEncode(const {'energy_kcal': 100}),
    source: source,
    verificationStatus: 'verified',
    scoringEvidence: ScoringEvidenceSnapshot(
      nutritionBasis: input.nutritionBasis,
      // Basis remediation Section E: EtiketlyPublicScoreAuditGate now
      // requires trusted basis provenance (declaredLabel/adminVerified)
      // before treating a snapshot as currently publishable. This fixture
      // represents a fully complete, ready-to-score product — its basis is
      // exactly as genuinely proven as the caller's own `input` already
      // asserts, so it is tagged the same way real proven evidence is.
      nutritionBasisEvidence: input.nutritionBasis == NutritionBasis.unknown
          ? null
          : EvidenceValue<NutritionBasis>(
              value: input.nutritionBasis,
              provenance: EvidenceProvenance.declaredLabel,
              verification: EvidenceVerification.verified,
            ),
      nutritionProductState: input.productState,
      nutrition: input.nutrition,
      fvlEvidence: input.fvlEvidence,
      nnsEvidence: input.nnsEvidence,
      ingredientEvidenceCompleteness: input.ingredientEvidenceCompleteness,
      categoryEvidence: input.categoryEvidence,
      classificationFacts: input.classificationFacts,
    ),
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

EtiketlyScoreAuditSnapshot buildAuditSnapshot({
  required Product product,
  required CanonicalAdditiveAssessment assessment,
  ProductEtiketlyScoreOrchestrator orchestrator =
      const ProductEtiketlyScoreOrchestrator(),
}) {
  final evaluation = orchestrator.calculate(
    product: product,
    canonicalAssessment: assessment,
  );
  if (evaluation == null || !evaluation.isCalculated) {
    throw StateError('Audit test fixture must be scoring-ready.');
  }
  return const EtiketlyScoreAuditSnapshotBuilder().build(
    product: product,
    evaluation: evaluation,
  );
}

/// Builds a snapshot modeling a HISTORICAL audit row created before the
/// pre-APPLY trust correction — fully self-consistent (correctly
/// fingerprinted) with `resolved_input.nutrition_basis_provenance` equal
/// to [provenance] (including null, for a pre-remediation row that never
/// recorded provenance at all).
///
/// Going forward, [buildAuditSnapshot] can never again produce a
/// calculated evaluation for untrusted basis provenance — see
/// ScoringEvidenceSnapshot.toScoringInput, which now downgrades an
/// untrusted-provenance basis to [NutritionBasis.unknown] before
/// readiness is ever evaluated. This helper exists ONLY to make such
/// (frozen, immutable, never-deleted) historical rows constructible in
/// tests: it computes ONE trusted-basis evaluation (so a real score can
/// exist), then builds the actual snapshot from a product whose evidence
/// carries [provenance] instead — exactly mirroring what the pipeline
/// genuinely produced before this correction existed. [EtiketlyScoreAuditSnapshotBuilder.build]
/// reads basis provenance directly from `product.scoringEvidence`, entirely
/// independent of the evaluation's own (enum-only) nutrition basis, so the
/// resulting snapshot is genuinely self-consistent, not JSON-surgeried.
EtiketlyScoreAuditSnapshot buildHistoricalAuditSnapshotWithBasisProvenance(
  EvidenceProvenance? provenance, {
  EtiketlyScoringInput? input,
  String id = 'audit-product',
  String ingredientsText = 'Su',
}) {
  final resolvedInput = input ?? completeInput();
  final trustedProduct = auditProductFromInput(
    resolvedInput,
    id: id,
    ingredientsText: ingredientsText,
  );
  final evaluation = const ProductEtiketlyScoreOrchestrator().calculate(
    product: trustedProduct,
    canonicalAssessment: auditOrdinaryAssessment(),
  );
  if (evaluation == null || !evaluation.isCalculated) {
    throw StateError(
      'Historical audit fixture must be scoring-ready under trusted basis.',
    );
  }
  final base = trustedProduct.scoringEvidence!;
  final historicalEvidence = provenance == null
      ? ScoringEvidenceSnapshot(
          nutritionBasis: base.nutritionBasis,
          nutritionBasisEvidence: null,
          nutritionProductState: base.nutritionProductState,
          nutritionProductStateEvidence: base.nutritionProductStateEvidence,
          nutrition: base.nutrition,
          fvlEvidence: base.fvlEvidence,
          nnsEvidence: base.nnsEvidence,
          ingredientEvidenceCompleteness: base.ingredientEvidenceCompleteness,
          categoryEvidence: base.categoryEvidence,
          classificationFacts: base.classificationFacts,
        )
      : base.copyWith(
          nutritionBasisEvidence: EvidenceValue<NutritionBasis>(
            value: resolvedInput.nutritionBasis,
            provenance: provenance,
            verification: EvidenceVerification.verified,
          ),
        );
  final historicalProduct = Product(
    id: trustedProduct.id,
    barcode: trustedProduct.barcode,
    name: trustedProduct.name,
    brand: trustedProduct.brand,
    ingredientsText: trustedProduct.ingredientsText,
    nutritionText: trustedProduct.nutritionText,
    verificationStatus: trustedProduct.verificationStatus,
    scoringEvidence: historicalEvidence,
    createdAt: trustedProduct.createdAt,
    updatedAt: trustedProduct.updatedAt,
  );
  return const EtiketlyScoreAuditSnapshotBuilder().build(
    product: historicalProduct,
    evaluation: evaluation,
  );
}

Ingredient auditOrdinaryIngredient({String name = 'Su'}) {
  return Ingredient(
    id: 'audit-ordinary-${name.toLowerCase()}',
    name: name,
    normalizedName: name.toLowerCase(),
    riskLevel: 'low',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

CanonicalAdditiveAssessment auditOrdinaryAssessment({String name = 'Su'}) {
  return const CanonicalIngredientRiskService().assessIngredients([
    auditOrdinaryIngredient(name: name),
  ]);
}

CanonicalAdditiveAssessment auditRiskAssessment(String riskLevel) {
  final ingredient = Ingredient(
    id: 'audit-custom-additive',
    name: 'Audit Custom Additive',
    normalizedName: 'audit custom additive',
    additiveGroup: 'preservative',
    riskLevel: riskLevel,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  return const CanonicalIngredientRiskService().assessIngredients([ingredient]);
}
