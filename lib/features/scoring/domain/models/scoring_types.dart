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
  // Deterministic, code-derived nutrition-basis fallback from an explicit,
  // unambiguous taxonomy-tag allowlist (never AI, never product-name
  // fuzzy matching, never the broad ScoringCategory alone) — see
  // CategoryDerivedBasisResolver. Distinct from `declaredLabel` (the
  // source itself declared the exact unit) and `adminVerified` (a human
  // confirmed it): this is neither — it is a controlled, reviewable
  // policy inference, trusted for the SAME public/readiness purposes but
  // never silently conflated with genuinely proven source evidence.
  categoryDerived,
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
  saturatedFatExceedsTotalFat,
  nonPositiveTotalFatForFatCategory,
  plainWaterCategoryMismatch,
}

enum ScoringReadinessWarning {
  saltDerivedFromSodium,
  containsUnverifiedEvidence,
  containsDatabaseImportedEvidence,
}

enum ScoringEvidenceQuality { high, moderate, low, unknown }
