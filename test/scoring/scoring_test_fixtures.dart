import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

EvidenceValue<T> verifiedValue<T>(
  T value, {
  EvidenceProvenance provenance = EvidenceProvenance.declaredLabel,
}) {
  return EvidenceValue<T>(
    value: value,
    provenance: provenance,
    verification: EvidenceVerification.verified,
  );
}

ScoringCategoryEvidence explicitCategory(ScoringCategory category) {
  return ScoringCategoryEvidence(
    resolvedCategory: category,
    source: CategoryEvidenceSource.explicitScoringMetadata,
    evidenceValues: [category.name],
    reasons: const [CategoryResolutionReason.resolvedFromExplicitMetadata],
  );
}

ScoringNutritionData completeNutrition({
  bool includeEnergyKj = true,
  bool includeTotalFat = true,
  bool includeSaturatedFat = true,
  bool includeSugars = true,
  bool includeSalt = true,
  bool includeProtein = true,
  bool includeFiber = true,
  EvidenceValue<double>? energyKj,
  EvidenceValue<double>? totalFat,
  EvidenceValue<double>? saturatedFat,
  EvidenceValue<double>? sugars,
  EvidenceValue<double>? salt,
  EvidenceValue<double>? protein,
  EvidenceValue<double>? fiber,
}) {
  return ScoringNutritionData(
    energyKj: includeEnergyKj
        ? energyKj ?? verifiedValue(420)
        : const EvidenceValue<double>.unknown(),
    totalFat: includeTotalFat
        ? totalFat ?? verifiedValue(8)
        : const EvidenceValue<double>.unknown(),
    saturatedFat: includeSaturatedFat
        ? saturatedFat ?? verifiedValue(2)
        : const EvidenceValue<double>.unknown(),
    sugars: includeSugars
        ? sugars ?? verifiedValue(4)
        : const EvidenceValue<double>.unknown(),
    salt: includeSalt
        ? salt ?? verifiedValue(0.4)
        : const EvidenceValue<double>.unknown(),
    protein: includeProtein
        ? protein ?? verifiedValue(6)
        : const EvidenceValue<double>.unknown(),
    fiber: includeFiber
        ? fiber ?? verifiedValue(3)
        : const EvidenceValue<double>.unknown(),
  );
}

EtiketlyScoringInput completeInput({
  ScoringCategory category = ScoringCategory.generalFood,
  ScoringCategoryEvidence? categoryEvidence,
  NutritionBasis? basis,
  NutritionProductState productState = NutritionProductState.asSold,
  ScoringNutritionData? nutrition,
  CompositionPercentageEvidence fvlEvidence =
      const CompositionPercentageEvidence.provenAbsent(
        provenance: EvidenceProvenance.declaredLabel,
        verification: EvidenceVerification.verified,
      ),
  PresenceEvidence nnsEvidence = const PresenceEvidence.absent(
    provenance: EvidenceProvenance.declaredLabel,
    verification: EvidenceVerification.verified,
  ),
  IngredientEvidenceCompleteness ingredientCompleteness =
      IngredientEvidenceCompleteness.complete,
}) {
  final resolvedBasis =
      basis ??
      (category == ScoringCategory.beverage
          ? NutritionBasis.per100ml
          : NutritionBasis.per100g);
  return EtiketlyScoringInput(
    nutrition: nutrition ?? completeNutrition(),
    nutritionBasis: resolvedBasis,
    productState: productState,
    categoryEvidence: categoryEvidence ?? explicitCategory(category),
    fvlEvidence: fvlEvidence,
    nnsEvidence: nnsEvidence,
    ingredientEvidenceCompleteness: ingredientCompleteness,
  );
}
