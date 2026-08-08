import 'dart:convert';

import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class ScoringEvidenceConflict {
  final String field;
  final Object? existingValue;
  final Object? incomingValue;
  final bool incomingSelected;

  const ScoringEvidenceConflict({
    required this.field,
    required this.existingValue,
    required this.incomingValue,
    required this.incomingSelected,
  });
}

class ScoringEvidenceMergeResult {
  final ScoringEvidenceSnapshot? evidence;
  final List<ScoringEvidenceConflict> conflicts;
  final bool changed;

  const ScoringEvidenceMergeResult({
    required this.evidence,
    this.conflicts = const [],
    required this.changed,
  });
}

/// Conservatively merges evidence without letting lower-trust data replace
/// higher-trust or admin-verified facts.
class ScoringEvidenceMerger {
  const ScoringEvidenceMerger();

  ScoringEvidenceMergeResult merge(
    ScoringEvidenceSnapshot? existing,
    ScoringEvidenceSnapshot? incoming,
  ) {
    if (incoming == null) {
      return ScoringEvidenceMergeResult(evidence: existing, changed: false);
    }
    if (existing == null) {
      return ScoringEvidenceMergeResult(evidence: incoming, changed: true);
    }

    final conflicts = <ScoringEvidenceConflict>[];
    final nutrition = ScoringNutritionData(
      energyKj: _mergeEvidenceValue(
        'nutrition.energy_kj',
        existing.nutrition.energyKj,
        incoming.nutrition.energyKj,
        conflicts,
      ),
      energyKcal: _mergeEvidenceValue(
        'nutrition.energy_kcal',
        existing.nutrition.energyKcal,
        incoming.nutrition.energyKcal,
        conflicts,
      ),
      totalFat: _mergeEvidenceValue(
        'nutrition.total_fat',
        existing.nutrition.totalFat,
        incoming.nutrition.totalFat,
        conflicts,
      ),
      saturatedFat: _mergeEvidenceValue(
        'nutrition.saturated_fat',
        existing.nutrition.saturatedFat,
        incoming.nutrition.saturatedFat,
        conflicts,
      ),
      sugars: _mergeEvidenceValue(
        'nutrition.sugars',
        existing.nutrition.sugars,
        incoming.nutrition.sugars,
        conflicts,
      ),
      protein: _mergeEvidenceValue(
        'nutrition.protein',
        existing.nutrition.protein,
        incoming.nutrition.protein,
        conflicts,
      ),
      fiber: _mergeEvidenceValue(
        'nutrition.fiber',
        existing.nutrition.fiber,
        incoming.nutrition.fiber,
        conflicts,
      ),
      salt: _mergeEvidenceValue(
        'nutrition.salt',
        existing.nutrition.salt,
        incoming.nutrition.salt,
        conflicts,
      ),
      sodium: _mergeEvidenceValue(
        'nutrition.sodium',
        existing.nutrition.sodium,
        incoming.nutrition.sodium,
        conflicts,
      ),
    );

    final merged = ScoringEvidenceSnapshot(
      nutritionBasis: _mergeUnknownableEnum(
        'nutrition_basis',
        existing.nutritionBasis,
        incoming.nutritionBasis,
        NutritionBasis.unknown,
        conflicts,
      ),
      nutritionProductState: _mergeUnknownableEnum(
        'nutrition_product_state',
        existing.nutritionProductState,
        incoming.nutritionProductState,
        NutritionProductState.unknown,
        conflicts,
      ),
      nutrition: nutrition,
      fvlEvidence: _mergeFvl(
        existing.fvlEvidence,
        incoming.fvlEvidence,
        conflicts,
      ),
      nnsEvidence: _mergePresence(
        existing.nnsEvidence,
        incoming.nnsEvidence,
        conflicts,
      ),
      ingredientEvidenceCompleteness: _mergeUnknownableEnum(
        'ingredient_evidence_completeness',
        existing.ingredientEvidenceCompleteness,
        incoming.ingredientEvidenceCompleteness,
        IngredientEvidenceCompleteness.unknown,
        conflicts,
      ),
      categoryEvidence: _mergeCategoryEvidence(
        existing.categoryEvidence,
        incoming.categoryEvidence,
        conflicts,
      ),
      classificationFacts: _mergeClassificationFacts(
        existing.classificationFacts,
        incoming.classificationFacts,
        conflicts,
      ),
      adminVerification:
          existing.adminVerification ?? incoming.adminVerification,
    );
    final changed =
        jsonEncode(existing.toJson()) != jsonEncode(merged.toJson());
    return ScoringEvidenceMergeResult(
      evidence: merged,
      conflicts: List.unmodifiable(conflicts),
      changed: changed,
    );
  }

  EvidenceValue<T> _mergeEvidenceValue<T>(
    String field,
    EvidenceValue<T> existing,
    EvidenceValue<T> incoming,
    List<ScoringEvidenceConflict> conflicts,
  ) {
    if (!incoming.hasValue) return existing;
    if (!existing.hasValue) return incoming;

    final incomingWins =
        _evidenceRank(incoming.provenance, incoming.verification) >
        _evidenceRank(existing.provenance, existing.verification);
    if (existing.value != incoming.value) {
      conflicts.add(
        ScoringEvidenceConflict(
          field: field,
          existingValue: existing.value,
          incomingValue: incoming.value,
          incomingSelected: incomingWins,
        ),
      );
    }
    return incomingWins ? incoming : existing;
  }

  CompositionPercentageEvidence _mergeFvl(
    CompositionPercentageEvidence existing,
    CompositionPercentageEvidence incoming,
    List<ScoringEvidenceConflict> conflicts,
  ) {
    if (incoming.state == CompositionPercentageState.unknown) return existing;
    if (existing.state == CompositionPercentageState.unknown) return incoming;
    final incomingWins =
        _evidenceRank(incoming.provenance, incoming.verification) >
        _evidenceRank(existing.provenance, existing.verification);
    if (existing.state != incoming.state ||
        existing.percentage != incoming.percentage) {
      conflicts.add(
        ScoringEvidenceConflict(
          field: 'fvl_evidence',
          existingValue: '${existing.state.name}:${existing.percentage}',
          incomingValue: '${incoming.state.name}:${incoming.percentage}',
          incomingSelected: incomingWins,
        ),
      );
    }
    return incomingWins ? incoming : existing;
  }

  PresenceEvidence _mergePresence(
    PresenceEvidence existing,
    PresenceEvidence incoming,
    List<ScoringEvidenceConflict> conflicts,
  ) {
    if (incoming.state == PresenceEvidenceState.unknown) return existing;
    if (existing.state == PresenceEvidenceState.unknown) return incoming;
    final incomingWins =
        _evidenceRank(incoming.provenance, incoming.verification) >
        _evidenceRank(existing.provenance, existing.verification);
    if (existing.state != incoming.state) {
      conflicts.add(
        ScoringEvidenceConflict(
          field: 'nns_evidence',
          existingValue: existing.state.name,
          incomingValue: incoming.state.name,
          incomingSelected: incomingWins,
        ),
      );
    }
    return incomingWins ? incoming : existing;
  }

  ScoringCategoryEvidence _mergeCategoryEvidence(
    ScoringCategoryEvidence existing,
    ScoringCategoryEvidence incoming,
    List<ScoringEvidenceConflict> conflicts,
  ) {
    if (!incoming.isSufficient) return existing;
    if (!existing.isSufficient) return incoming;
    final incomingWins =
        _categorySourceRank(incoming.source) >
        _categorySourceRank(existing.source);
    if (existing.resolvedCategory != incoming.resolvedCategory) {
      conflicts.add(
        ScoringEvidenceConflict(
          field: 'category_evidence.resolved_category',
          existingValue: existing.resolvedCategory.name,
          incomingValue: incoming.resolvedCategory.name,
          incomingSelected: incomingWins,
        ),
      );
    }
    return incomingWins ? incoming : existing;
  }

  ScoringClassificationFacts _mergeClassificationFacts(
    ScoringClassificationFacts existing,
    ScoringClassificationFacts incoming,
    List<ScoringEvidenceConflict> conflicts,
  ) {
    return ScoringClassificationFacts(
      isPlainWater: _mergeOptionalEvidence(
        'classification_facts.is_plain_water',
        existing.isPlainWater,
        incoming.isPlainWater,
        conflicts,
      ),
      redMeatPercentage: _mergeOptionalEvidence(
        'classification_facts.red_meat_percentage',
        existing.redMeatPercentage,
        incoming.redMeatPercentage,
        conflicts,
      ),
      redMeatIsPrimaryIngredient: _mergeOptionalEvidence(
        'classification_facts.red_meat_is_primary_ingredient',
        existing.redMeatIsPrimaryIngredient,
        incoming.redMeatIsPrimaryIngredient,
        conflicts,
      ),
      nutSeedPercentage: _mergeOptionalEvidence(
        'classification_facts.nut_seed_percentage',
        existing.nutSeedPercentage,
        incoming.nutSeedPercentage,
        conflicts,
      ),
      isPlantBasedCheeseAlternative: _mergeOptionalEvidence(
        'classification_facts.is_plant_based_cheese_alternative',
        existing.isPlantBasedCheeseAlternative,
        incoming.isPlantBasedCheeseAlternative,
        conflicts,
      ),
      isCompoundProduct: _mergeOptionalEvidence(
        'classification_facts.is_compound_product',
        existing.isCompoundProduct,
        incoming.isCompoundProduct,
        conflicts,
      ),
      isDrinkableDairy: _mergeOptionalEvidence(
        'classification_facts.is_drinkable_dairy',
        existing.isDrinkableDairy,
        incoming.isDrinkableDairy,
        conflicts,
      ),
      isBeverage: _mergeOptionalEvidence(
        'classification_facts.is_beverage',
        existing.isBeverage,
        incoming.isBeverage,
        conflicts,
      ),
      isFoodSupplement: _mergeOptionalEvidence(
        'classification_facts.is_food_supplement',
        existing.isFoodSupplement,
        incoming.isFoodSupplement,
        conflicts,
      ),
      isInfantFood: _mergeOptionalEvidence(
        'classification_facts.is_infant_food',
        existing.isInfantFood,
        incoming.isInfantFood,
        conflicts,
      ),
      isMedicalFood: _mergeOptionalEvidence(
        'classification_facts.is_medical_food',
        existing.isMedicalFood,
        incoming.isMedicalFood,
        conflicts,
      ),
      isSportsNutrition: _mergeOptionalEvidence(
        'classification_facts.is_sports_nutrition',
        existing.isSportsNutrition,
        incoming.isSportsNutrition,
        conflicts,
      ),
      isMealReplacement: _mergeOptionalEvidence(
        'classification_facts.is_meal_replacement',
        existing.isMealReplacement,
        incoming.isMealReplacement,
        conflicts,
      ),
    );
  }

  EvidenceValue<T>? _mergeOptionalEvidence<T>(
    String field,
    EvidenceValue<T>? existing,
    EvidenceValue<T>? incoming,
    List<ScoringEvidenceConflict> conflicts,
  ) {
    if (incoming == null || !incoming.hasValue) return existing;
    if (existing == null || !existing.hasValue) return incoming;
    return _mergeEvidenceValue(field, existing, incoming, conflicts);
  }

  T _mergeUnknownableEnum<T extends Enum>(
    String field,
    T existing,
    T incoming,
    T unknown,
    List<ScoringEvidenceConflict> conflicts,
  ) {
    if (incoming == unknown) return existing;
    if (existing == unknown) return incoming;
    if (existing != incoming) {
      conflicts.add(
        ScoringEvidenceConflict(
          field: field,
          existingValue: existing.name,
          incomingValue: incoming.name,
          incomingSelected: false,
        ),
      );
    }
    return existing;
  }

  int _evidenceRank(
    EvidenceProvenance provenance,
    EvidenceVerification verification,
  ) {
    if (verification == EvidenceVerification.rejected) return -1;
    final provenanceRank = switch (provenance) {
      EvidenceProvenance.adminVerified => 70,
      EvidenceProvenance.declaredLabel => 60,
      EvidenceProvenance.ocrDeclaredLabel => 50,
      EvidenceProvenance.databaseImport => 40,
      EvidenceProvenance.derivedFromSodium ||
      EvidenceProvenance.derivedFromKcal => 30,
      EvidenceProvenance.unknown => 0,
    };
    final verificationRank = switch (verification) {
      EvidenceVerification.verified => 2,
      EvidenceVerification.unverified => 1,
      EvidenceVerification.unknown || EvidenceVerification.rejected => 0,
    };
    return provenanceRank + verificationRank;
  }

  int _categorySourceRank(CategoryEvidenceSource source) {
    return switch (source) {
      CategoryEvidenceSource.manualAdminVerification => 70,
      CategoryEvidenceSource.explicitScoringMetadata => 60,
      CategoryEvidenceSource.classificationFacts => 50,
      CategoryEvidenceSource.trustedCategoryTag => 40,
      CategoryEvidenceSource.trustedCanonicalSubcategory => 30,
      CategoryEvidenceSource.trustedCanonicalCategory => 20,
      CategoryEvidenceSource.unknown => 0,
    };
  }
}
