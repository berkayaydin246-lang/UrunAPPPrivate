import 'dart:convert';

import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_audit_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_audit_snapshot_builder.dart';

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
}) {
  final evaluation = const ProductEtiketlyScoreOrchestrator().calculate(
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
