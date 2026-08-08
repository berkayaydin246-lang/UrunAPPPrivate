import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';

class ProductScoringInputAdapter {
  final ScoringCategoryResolver categoryResolver;

  const ProductScoringInputAdapter({
    this.categoryResolver = const ScoringCategoryResolver(),
  });

  EtiketlyScoringInput fromProduct(Product product) {
    final categoryEvidence = categoryResolver.resolve(
      ScoringCategoryResolverInput(
        categoryTags: product.categoryTags ?? const [],
        canonicalCategory: product.canonicalCategory,
        canonicalSubcategory: product.canonicalSubcategory,
        taxonomyProvenance: EvidenceProvenance.databaseImport,
        taxonomyVerification: EvidenceVerification.unverified,
      ),
    );

    return EtiketlyScoringInput(
      nutrition: fromLegacyNutrition(product.nutrition),
      nutritionBasis: NutritionBasis.unknown,
      productState: NutritionProductState.unknown,
      categoryEvidence: categoryEvidence,
      fvlEvidence: const CompositionPercentageEvidence.unknown(),
      nnsEvidence: const PresenceEvidence.unknown(),
      ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.unknown,
    );
  }

  ScoringNutritionData fromLegacyNutrition(NutritionData? nutrition) {
    if (nutrition == null) return const ScoringNutritionData();

    EvidenceValue<double> imported(double? value) => value == null
        ? const EvidenceValue<double>.unknown()
        : EvidenceValue<double>(
            value: value,
            provenance: EvidenceProvenance.databaseImport,
            verification: EvidenceVerification.unverified,
          );

    final energyKcal = imported(nutrition.energyKcal);
    final energyKj = nutrition.energyKcal == null
        ? const EvidenceValue<double>.unknown()
        : EvidenceValue<double>(
            value: nutrition.energyKcal! * 4.184,
            provenance: EvidenceProvenance.derivedFromKcal,
            verification: EvidenceVerification.unverified,
          );
    final salt = nutrition.salt != null
        ? imported(nutrition.salt)
        : nutrition.sodium != null
        ? EvidenceValue<double>(
            value: nutrition.sodium! * 2.5,
            provenance: EvidenceProvenance.derivedFromSodium,
            verification: EvidenceVerification.unverified,
          )
        : const EvidenceValue<double>.unknown();

    return ScoringNutritionData(
      energyKj: energyKj,
      energyKcal: energyKcal,
      totalFat: imported(nutrition.fat),
      saturatedFat: imported(nutrition.saturatedFat),
      sugars: imported(nutrition.sugars),
      protein: imported(nutrition.proteins),
      fiber: imported(nutrition.fiber),
      salt: salt,
      sodium: imported(nutrition.sodium),
    );
  }
}
