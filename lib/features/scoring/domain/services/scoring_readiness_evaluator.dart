import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_point_calculator.dart';

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
          case ScoringRequirement.fiber:
            _checkNutritionRequirement(
              requirement,
              _nutritionEvidence(input, requirement),
              blockers,
              warnings,
              missing,
              needsEvidence,
            );
          case ScoringRequirement.protein:
            // Branch-conditional: protein only blocks scoring when its
            // absence could change the selected deterministic score
            // branch (see NUTRITION_METHODOLOGY_2023.md and
            // _isProteinRequired). A present-but-invalid protein value is
            // still fully validated regardless — this relaxation is only
            // ever about missing-ness, never about tolerating bad data.
            _checkNutritionRequirement(
              requirement,
              _nutritionEvidence(input, requirement),
              blockers,
              warnings,
              missing,
              needsEvidence,
              requireIfMissing: _isProteinRequired(input, category),
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

    // Cross-field / cross-evidence checks that no single per-requirement
    // check above can see: two individually-present, individually-finite,
    // individually-non-negative values can still be jointly nonsensical
    // (e.g. saturated fat greater than total fat), or a numeric value that
    // is technically "present" can still fail a category-specific physical
    // constraint (e.g. zero total fat for a fats/oils/nuts/seeds product).
    // Without these, such source data reaches
    // ValidatedNutritionScoringInput.validate() unblocked and throws
    // NutritionScoringInputValidationException as an uncaught exception
    // instead of a diagnosable, fail-closed readiness blocker.
    _checkCrossFieldNutritionInvariants(input, category, blockers);

    return _result(
      category: category,
      blockers: blockers,
      warnings: warnings,
      missing: missing,
      needsEvidence: needsEvidence,
    );
  }

  void _checkCrossFieldNutritionInvariants(
    EtiketlyScoringInput input,
    ScoringCategory category,
    Set<ScoringReadinessBlocker> blockers,
  ) {
    final totalFat = input.nutrition.totalFat.value;
    final saturatedFat = input.nutrition.saturatedFat.value;
    final totalFatIsCleanNonNegative =
        totalFat != null && totalFat.isFinite && totalFat >= 0;
    final saturatedFatIsCleanNonNegative =
        saturatedFat != null && saturatedFat.isFinite && saturatedFat >= 0;

    if (totalFatIsCleanNonNegative &&
        saturatedFatIsCleanNonNegative &&
        saturatedFat > totalFat) {
      blockers.add(ScoringReadinessBlocker.saturatedFatExceedsTotalFat);
    }

    if (category == ScoringCategory.fatsOilsNutsSeeds &&
        totalFatIsCleanNonNegative &&
        totalFat <= 0) {
      blockers.add(ScoringReadinessBlocker.nonPositiveTotalFatForFatCategory);
    }

    if (input.classificationFacts.isPlainWater?.trustedValue == true &&
        category != ScoringCategory.beverage) {
      blockers.add(ScoringReadinessBlocker.plainWaterCategoryMismatch);
    }
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
    Set<ScoringRequirement> needsEvidence, {
    bool requireIfMissing = true,
  }) {
    final value = evidence.value;
    if (value == null) {
      if (requireIfMissing) {
        blockers.add(_missingBlocker(requirement));
        missing.add(requirement);
      }
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

  static const _pointCalculator = NutritionPointCalculator();

  /// Whether missing protein evidence can actually change this product's
  /// deterministic score branch — the dependency-graph correction required
  /// by NUTRITION_METHODOLOGY_2023.md. Cheese and beverage never suppress
  /// protein, so it is always required for them. General food and red meat
  /// suppress protein once `N >= 11`; fats/oils/nuts/seeds suppress it once
  /// `N >= 7`. `N` is computed here purely from the OTHER already-present,
  /// individually-clean negative-point inputs, reusing
  /// [NutritionPointCalculator]'s exact frozen point tables (never
  /// reimplemented) — never from protein itself, so there is no
  /// circularity. If any of those other inputs is missing/invalid, `N`
  /// cannot be determined, and protein remains conservatively required
  /// (unchanged, fail-closed behavior) rather than guessed.
  bool _isProteinRequired(EtiketlyScoringInput input, ScoringCategory category) {
    return isProteinRequiredForNutrition(category, input.nutrition);
  }

  /// Public, reusable form of the SAME branch-conditional protein
  /// determination [_isProteinRequired] uses internally — exposed so
  /// other callers (e.g. the historical basis revalidation service's
  /// nutrition-consistency gate) can ask "does this specific
  /// category/nutrition combination actually need protein" without
  /// re-deriving a second, hardcoded copy of this dependency logic. Pure,
  /// frozen, unchanged behavior from [_isProteinRequired] — only the
  /// parameter type changed (nutrition data directly, not a full scoring
  /// input), since that was always the only part of the input this logic
  /// ever read.
  bool isProteinRequiredForNutrition(
    ScoringCategory category,
    ScoringNutritionData nutrition,
  ) {
    switch (category) {
      case ScoringCategory.cheese:
      case ScoringCategory.beverage:
        return true;
      case ScoringCategory.generalFood:
      case ScoringCategory.redMeat:
        final n = _generalNegativeTotalIfDetermined(nutrition);
        return n == null || n < 11;
      case ScoringCategory.fatsOilsNutsSeeds:
        final n = _fatsNegativeTotalIfDetermined(nutrition);
        return n == null || n < 7;
      case ScoringCategory.unknown:
      case ScoringCategory.outOfScope:
        // Unreachable in practice: evaluate() already returns before this
        // point for both categories. Conservative default if ever reached.
        return true;
    }
  }

  /// Public: every [ScoringRequirement] that is actually nutrition-numeric
  /// AND score-relevant for [category] given [nutrition] (used only to
  /// resolve the branch-conditional protein threshold above — never to
  /// second-guess the other, always-required fields). Deliberately
  /// excludes [ScoringRequirement.fvlPercentage]/[ScoringRequirement.nnsPresence]
  /// and every non-numeric requirement — those are not nutrition-consistency
  /// concerns. Reuses [_categoryRequirements] and
  /// [isProteinRequiredForNutrition] directly; this is not a second,
  /// independently-maintained dependency table.
  Set<ScoringRequirement> requiredNutritionFields(
    ScoringCategory category,
    ScoringNutritionData nutrition,
  ) {
    const nutritionNumericRequirements = {
      ScoringRequirement.energyKj,
      ScoringRequirement.totalFat,
      ScoringRequirement.saturatedFat,
      ScoringRequirement.sugars,
      ScoringRequirement.salt,
      ScoringRequirement.protein,
      ScoringRequirement.fiber,
    };
    final categoryRequirements = _categoryRequirements[category] ?? const {};
    final result = <ScoringRequirement>{};
    for (final requirement in categoryRequirements) {
      if (!nutritionNumericRequirements.contains(requirement)) continue;
      if (requirement == ScoringRequirement.protein &&
          !isProteinRequiredForNutrition(category, nutrition)) {
        continue;
      }
      result.add(requirement);
    }
    return result;
  }

  int? _generalNegativeTotalIfDetermined(ScoringNutritionData nutrition) {
    final energyKj = _cleanValue(nutrition.energyKj);
    final sugars = _cleanValue(nutrition.sugars);
    final saturatedFat = _cleanValue(nutrition.saturatedFat);
    final salt = _cleanValue(nutrition.salt);
    if (energyKj == null ||
        sugars == null ||
        saturatedFat == null ||
        salt == null) {
      return null;
    }
    return _pointCalculator.generalEnergyPoints(energyKj) +
        _pointCalculator.saturatedFatPoints(saturatedFat) +
        _pointCalculator.generalSugarPoints(sugars) +
        _pointCalculator.saltPoints(salt);
  }

  int? _fatsNegativeTotalIfDetermined(ScoringNutritionData nutrition) {
    final sugars = _cleanValue(nutrition.sugars);
    final saturatedFat = _cleanValue(nutrition.saturatedFat);
    final salt = _cleanValue(nutrition.salt);
    final totalFat = _cleanValue(nutrition.totalFat);
    if (sugars == null ||
        saturatedFat == null ||
        salt == null ||
        totalFat == null ||
        totalFat <= 0) {
      return null;
    }
    if (saturatedFat > totalFat) {
      // Physically impossible ratio (>100%). This is a genuine data
      // contradiction handled independently by
      // _checkCrossFieldNutritionInvariants's saturatedFatExceedsTotalFat
      // blocker — N cannot be safely determined here, so fall back to
      // conservatively requiring protein rather than feeding an
      // out-of-range percentage into fatSaturatedRatioPoints.
      return null;
    }
    final saturatedEnergyKj = saturatedFat * 37;
    final ratioPercent = 100 * saturatedFat / totalFat;
    return _pointCalculator.generalSugarPoints(sugars) +
        _pointCalculator.saltPoints(salt) +
        _pointCalculator.fatSaturatedEnergyPoints(saturatedEnergyKj) +
        _pointCalculator.fatSaturatedRatioPoints(ratioPercent);
  }

  double? _cleanValue(EvidenceValue<double> evidence) {
    final value = evidence.value;
    if (value == null || !value.isFinite || value < 0 || evidence.isRejected) {
      return null;
    }
    return value;
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
