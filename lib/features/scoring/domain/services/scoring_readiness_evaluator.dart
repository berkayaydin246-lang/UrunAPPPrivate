import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class ScoringReadinessEvaluator {
  const ScoringReadinessEvaluator();

  static const _categoryRequirements = {
    ScoringCategory.generalFood: {
      ScoringRequirement.energyKj,
      ScoringRequirement.saturatedFat,
      ScoringRequirement.sugars,
      ScoringRequirement.salt,
      ScoringRequirement.protein,
      ScoringRequirement.fiber,
      ScoringRequirement.fvlPercentage,
    },
    ScoringCategory.cheese: {
      ScoringRequirement.energyKj,
      ScoringRequirement.saturatedFat,
      ScoringRequirement.sugars,
      ScoringRequirement.salt,
      ScoringRequirement.protein,
      ScoringRequirement.fiber,
      ScoringRequirement.fvlPercentage,
    },
    ScoringCategory.redMeat: {
      ScoringRequirement.energyKj,
      ScoringRequirement.saturatedFat,
      ScoringRequirement.sugars,
      ScoringRequirement.salt,
      ScoringRequirement.protein,
      ScoringRequirement.fiber,
      ScoringRequirement.fvlPercentage,
    },
    ScoringCategory.fatsOilsNutsSeeds: {
      ScoringRequirement.totalFat,
      ScoringRequirement.saturatedFat,
      ScoringRequirement.sugars,
      ScoringRequirement.salt,
      ScoringRequirement.protein,
      ScoringRequirement.fiber,
      ScoringRequirement.fvlPercentage,
    },
    ScoringCategory.beverage: {
      ScoringRequirement.energyKj,
      ScoringRequirement.saturatedFat,
      ScoringRequirement.sugars,
      ScoringRequirement.salt,
      ScoringRequirement.protein,
      ScoringRequirement.fiber,
      ScoringRequirement.fvlPercentage,
      ScoringRequirement.nnsPresence,
    },
  };

  static const _expectedBasis = {
    ScoringCategory.generalFood: NutritionBasis.per100g,
    ScoringCategory.cheese: NutritionBasis.per100g,
    ScoringCategory.redMeat: NutritionBasis.per100g,
    ScoringCategory.fatsOilsNutsSeeds: NutritionBasis.per100g,
    ScoringCategory.beverage: NutritionBasis.per100ml,
  };

  ScoringReadinessResult evaluate(EtiketlyScoringInput input) {
    final blockers = <ScoringReadinessBlocker>{};
    final warnings = <ScoringReadinessWarning>{};
    final missing = <ScoringRequirement>{};
    final needsEvidence = <ScoringRequirement>{};
    final category = input.categoryEvidence.resolvedCategory;

    if (category == ScoringCategory.outOfScope) {
      blockers.add(ScoringReadinessBlocker.outOfScopeProduct);
      return _result(
        category: category,
        blockers: blockers,
        warnings: warnings,
        missing: missing,
        needsEvidence: needsEvidence,
      );
    }

    if (category == ScoringCategory.unknown ||
        !input.categoryEvidence.isSufficient) {
      blockers.add(ScoringReadinessBlocker.unknownScoringCategory);
      missing.add(ScoringRequirement.scoringCategory);
      _addCategoryEvidenceBlockers(input, blockers);
    }

    _checkBasis(input, category, blockers, missing);
    if (input.productState == NutritionProductState.unknown) {
      blockers.add(ScoringReadinessBlocker.unknownProductState);
      missing.add(ScoringRequirement.productState);
    }

    final requirements = _categoryRequirements[category];
    if (requirements != null) {
      for (final requirement in requirements) {
        switch (requirement) {
          case ScoringRequirement.energyKj:
          case ScoringRequirement.totalFat:
          case ScoringRequirement.saturatedFat:
          case ScoringRequirement.sugars:
          case ScoringRequirement.salt:
          case ScoringRequirement.protein:
          case ScoringRequirement.fiber:
            _checkNutritionRequirement(
              requirement,
              _nutritionEvidence(input, requirement),
              blockers,
              warnings,
              missing,
              needsEvidence,
            );
          case ScoringRequirement.fvlPercentage:
            _checkFvl(input, blockers, warnings, missing, needsEvidence);
          case ScoringRequirement.nnsPresence:
            _checkNns(input, blockers, warnings, missing, needsEvidence);
          case ScoringRequirement.nutritionBasis:
          case ScoringRequirement.productState:
          case ScoringRequirement.scoringCategory:
          case ScoringRequirement.ingredientCompleteness:
            break;
        }
      }
    }

    return _result(
      category: category,
      blockers: blockers,
      warnings: warnings,
      missing: missing,
      needsEvidence: needsEvidence,
    );
  }

  void _checkBasis(
    EtiketlyScoringInput input,
    ScoringCategory category,
    Set<ScoringReadinessBlocker> blockers,
    Set<ScoringRequirement> missing,
  ) {
    switch (input.nutritionBasis) {
      case NutritionBasis.unknown:
        blockers.add(ScoringReadinessBlocker.unknownNutritionBasis);
        missing.add(ScoringRequirement.nutritionBasis);
      case NutritionBasis.perServing:
        blockers.add(ScoringReadinessBlocker.unsupportedPerServingOnly);
        missing.add(ScoringRequirement.nutritionBasis);
      case NutritionBasis.per100g:
      case NutritionBasis.per100ml:
        final expected = _expectedBasis[category];
        if (expected != null && input.nutritionBasis != expected) {
          blockers.add(
            ScoringReadinessBlocker.nutritionBasisDoesNotMatchCategory,
          );
        }
    }
  }

  void _checkNutritionRequirement(
    ScoringRequirement requirement,
    EvidenceValue<double> evidence,
    Set<ScoringReadinessBlocker> blockers,
    Set<ScoringReadinessWarning> warnings,
    Set<ScoringRequirement> missing,
    Set<ScoringRequirement> needsEvidence,
  ) {
    final value = evidence.value;
    if (value == null) {
      blockers.add(_missingBlocker(requirement));
      missing.add(requirement);
      return;
    }
    if (!value.isFinite || value < 0) {
      blockers.add(ScoringReadinessBlocker.invalidEvidenceValue);
      needsEvidence.add(requirement);
      return;
    }
    if (evidence.isRejected) {
      blockers.add(ScoringReadinessBlocker.rejectedEvidence);
      needsEvidence.add(requirement);
      return;
    }

    if (requirement == ScoringRequirement.energyKj &&
        !_isDeclaredEnergy(evidence.provenance)) {
      blockers.add(ScoringReadinessBlocker.energyKjNotDeclared);
      needsEvidence.add(requirement);
    } else if (!evidence.hasKnownProvenance) {
      blockers.add(ScoringReadinessBlocker.unknownNutritionProvenance);
      needsEvidence.add(requirement);
    }

    if (requirement == ScoringRequirement.salt &&
        evidence.provenance == EvidenceProvenance.derivedFromSodium) {
      warnings.add(ScoringReadinessWarning.saltDerivedFromSodium);
    }
    if (evidence.provenance == EvidenceProvenance.databaseImport) {
      warnings.add(ScoringReadinessWarning.containsDatabaseImportedEvidence);
    }
    if (evidence.verification != EvidenceVerification.verified) {
      warnings.add(ScoringReadinessWarning.containsUnverifiedEvidence);
    }
  }

  void _checkFvl(
    EtiketlyScoringInput input,
    Set<ScoringReadinessBlocker> blockers,
    Set<ScoringReadinessWarning> warnings,
    Set<ScoringRequirement> missing,
    Set<ScoringRequirement> needsEvidence,
  ) {
    final evidence = input.fvlEvidence;
    if (!evidence.hasDeterministicValue) {
      blockers.add(ScoringReadinessBlocker.unknownFvlPercentage);
      missing.add(ScoringRequirement.fvlPercentage);
      return;
    }
    if (evidence.percentage == null ||
        !evidence.percentage!.isFinite ||
        evidence.percentage! < 0 ||
        evidence.percentage! > 100) {
      blockers.add(ScoringReadinessBlocker.invalidEvidenceValue);
      needsEvidence.add(ScoringRequirement.fvlPercentage);
      return;
    }
    if (evidence.isRejected) {
      blockers.add(ScoringReadinessBlocker.rejectedEvidence);
      needsEvidence.add(ScoringRequirement.fvlPercentage);
      return;
    }
    if (evidence.provenance == EvidenceProvenance.unknown) {
      blockers.add(
        ScoringReadinessBlocker.unknownCompositionEvidenceProvenance,
      );
      needsEvidence.add(ScoringRequirement.fvlPercentage);
    }
    _checkIngredientDependency(evidence.dependency, input, blockers, missing);
    if (evidence.verification != EvidenceVerification.verified) {
      warnings.add(ScoringReadinessWarning.containsUnverifiedEvidence);
    }
  }

  void _checkNns(
    EtiketlyScoringInput input,
    Set<ScoringReadinessBlocker> blockers,
    Set<ScoringReadinessWarning> warnings,
    Set<ScoringRequirement> missing,
    Set<ScoringRequirement> needsEvidence,
  ) {
    final evidence = input.nnsEvidence;
    if (!evidence.isKnown) {
      blockers.add(ScoringReadinessBlocker.unknownNnsPresence);
      missing.add(ScoringRequirement.nnsPresence);
      return;
    }
    if (evidence.isRejected) {
      blockers.add(ScoringReadinessBlocker.rejectedEvidence);
      needsEvidence.add(ScoringRequirement.nnsPresence);
      return;
    }
    if (evidence.provenance == EvidenceProvenance.unknown) {
      blockers.add(ScoringReadinessBlocker.unknownNnsEvidenceProvenance);
      needsEvidence.add(ScoringRequirement.nnsPresence);
    }
    _checkIngredientDependency(evidence.dependency, input, blockers, missing);
    if (evidence.verification != EvidenceVerification.verified) {
      warnings.add(ScoringReadinessWarning.containsUnverifiedEvidence);
    }
  }

  void _checkIngredientDependency(
    EvidenceDependency dependency,
    EtiketlyScoringInput input,
    Set<ScoringReadinessBlocker> blockers,
    Set<ScoringRequirement> missing,
  ) {
    if (dependency == EvidenceDependency.completeIngredientList &&
        input.ingredientEvidenceCompleteness !=
            IngredientEvidenceCompleteness.complete) {
      blockers.add(ScoringReadinessBlocker.incompleteIngredientEvidence);
      missing.add(ScoringRequirement.ingredientCompleteness);
    }
  }

  void _addCategoryEvidenceBlockers(
    EtiketlyScoringInput input,
    Set<ScoringReadinessBlocker> blockers,
  ) {
    final reasons = input.categoryEvidence.reasons;
    if (reasons.contains(CategoryResolutionReason.conflictingEvidence)) {
      blockers.add(ScoringReadinessBlocker.conflictingCategoryEvidence);
    }
    if (reasons.contains(CategoryResolutionReason.redMeatEvidenceIncomplete)) {
      blockers.add(ScoringReadinessBlocker.redMeatEvidenceIncomplete);
    }
    if (reasons.contains(CategoryResolutionReason.nutSeedPercentageUnknown)) {
      blockers.add(ScoringReadinessBlocker.nutSeedPercentageUnknown);
    }
    if (reasons.contains(CategoryResolutionReason.cheeseEvidenceIncomplete)) {
      blockers.add(ScoringReadinessBlocker.cheeseEvidenceIncomplete);
    }
  }

  EvidenceValue<double> _nutritionEvidence(
    EtiketlyScoringInput input,
    ScoringRequirement requirement,
  ) {
    final nutrition = input.nutrition;
    return switch (requirement) {
      ScoringRequirement.energyKj => nutrition.energyKj,
      ScoringRequirement.totalFat => nutrition.totalFat,
      ScoringRequirement.saturatedFat => nutrition.saturatedFat,
      ScoringRequirement.sugars => nutrition.sugars,
      ScoringRequirement.salt => nutrition.salt,
      ScoringRequirement.protein => nutrition.protein,
      ScoringRequirement.fiber => nutrition.fiber,
      _ => const EvidenceValue<double>.unknown(),
    };
  }

  ScoringReadinessBlocker _missingBlocker(ScoringRequirement requirement) {
    return switch (requirement) {
      ScoringRequirement.energyKj => ScoringReadinessBlocker.missingEnergyKj,
      ScoringRequirement.totalFat =>
        ScoringReadinessBlocker.missingTotalFatForFatCategory,
      ScoringRequirement.saturatedFat =>
        ScoringReadinessBlocker.missingSaturatedFat,
      ScoringRequirement.sugars => ScoringReadinessBlocker.missingSugars,
      ScoringRequirement.salt => ScoringReadinessBlocker.missingSalt,
      ScoringRequirement.protein => ScoringReadinessBlocker.missingProtein,
      ScoringRequirement.fiber => ScoringReadinessBlocker.missingFiber,
      _ => ScoringReadinessBlocker.invalidEvidenceValue,
    };
  }

  bool _isDeclaredEnergy(EvidenceProvenance provenance) {
    return provenance == EvidenceProvenance.declaredLabel ||
        provenance == EvidenceProvenance.ocrDeclaredLabel ||
        provenance == EvidenceProvenance.adminVerified;
  }

  ScoringReadinessResult _result({
    required ScoringCategory category,
    required Set<ScoringReadinessBlocker> blockers,
    required Set<ScoringReadinessWarning> warnings,
    required Set<ScoringRequirement> missing,
    required Set<ScoringRequirement> needsEvidence,
  }) {
    final isScorable = blockers.isEmpty;
    final quality = !isScorable
        ? ScoringEvidenceQuality.low
        : warnings.isEmpty
        ? ScoringEvidenceQuality.high
        : ScoringEvidenceQuality.moderate;
    return ScoringReadinessResult(
      isScorable: isScorable,
      resolvedCategory: category,
      missingRequirements: missing,
      requirementsNeedingEvidence: needsEvidence,
      blockingReasons: blockers,
      warningReasons: warnings,
      evidenceQuality: quality,
    );
  }
}
