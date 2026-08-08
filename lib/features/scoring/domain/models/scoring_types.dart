enum ScoringCategory {
  generalFood,
  cheese,
  redMeat,
  fatsOilsNutsSeeds,
  beverage,
  unknown,
  outOfScope,
}

enum NutritionBasis { per100g, per100ml, perServing, unknown }

enum NutritionProductState { asSold, asPrepared, unknown }

enum EvidenceProvenance {
  declaredLabel,
  ocrDeclaredLabel,
  databaseImport,
  derivedFromSodium,
  derivedFromKcal,
  adminVerified,
  unknown,
}

enum EvidenceVerification { verified, unverified, unknown, rejected }

enum EvidenceDependency { none, completeIngredientList }

enum IngredientEvidenceCompleteness { complete, incomplete, unknown }

enum CompositionPercentageState { known, provenAbsent, unknown }

enum PresenceEvidenceState { present, absent, unknown }

enum CategoryEvidenceSource {
  explicitScoringMetadata,
  trustedCategoryTag,
  trustedCanonicalSubcategory,
  trustedCanonicalCategory,
  manualAdminVerification,
  classificationFacts,
  unknown,
}

enum CategoryResolutionReason {
  resolvedFromExplicitMetadata,
  resolvedFromTrustedTag,
  resolvedFromTrustedCanonicalSubcategory,
  resolvedFromTrustedCanonicalCategory,
  resolvedFromClassificationFacts,
  plainWaterConfirmed,
  outOfScopeFact,
  redMeatEvidenceIncomplete,
  nutSeedPercentageUnknown,
  cheeseEvidenceIncomplete,
  conflictingEvidence,
  untrustedTaxonomyEvidence,
  insufficientEvidence,
  resolvedFromLegacyTaxonomy,
}

enum ScoringRequirement {
  nutritionBasis,
  productState,
  scoringCategory,
  energyKj,
  totalFat,
  saturatedFat,
  sugars,
  salt,
  protein,
  fiber,
  fvlPercentage,
  nnsPresence,
  ingredientCompleteness,
}

enum ScoringReadinessBlocker {
  unknownNutritionBasis,
  unsupportedPerServingOnly,
  nutritionBasisDoesNotMatchCategory,
  unknownProductState,
  unknownScoringCategory,
  conflictingCategoryEvidence,
  redMeatEvidenceIncomplete,
  nutSeedPercentageUnknown,
  cheeseEvidenceIncomplete,
  outOfScopeProduct,
  missingEnergyKj,
  energyKjNotDeclared,
  missingTotalFatForFatCategory,
  missingSaturatedFat,
  missingSugars,
  missingSalt,
  missingProtein,
  missingFiber,
  unknownFvlPercentage,
  unknownNnsPresence,
  incompleteIngredientEvidence,
  unknownNutritionProvenance,
  unknownCompositionEvidenceProvenance,
  unknownNnsEvidenceProvenance,
  invalidEvidenceValue,
  rejectedEvidence,
}

enum ScoringReadinessWarning {
  saltDerivedFromSodium,
  containsUnverifiedEvidence,
  containsDatabaseImportedEvidence,
}

enum ScoringEvidenceQuality { high, moderate, low, unknown }
