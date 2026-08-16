import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

enum NutritionScoringInputIssue {
  invalidNumericValue,
  nonPositiveTotalFat,
  saturatedFatExceedsTotalFat,
  plainWaterCategoryMismatch,
}

class NutritionScoringInputValidationException implements Exception {
  final ScoringReadinessResult readiness;
  final Set<NutritionScoringInputIssue> issues;

  NutritionScoringInputValidationException({
    required this.readiness,
    Iterable<NutritionScoringInputIssue> issues = const [],
  }) : issues = Set.unmodifiable(issues);

  @override
  String toString() {
    final details = <String>[
      if (readiness.blockingReasons.isNotEmpty)
        'readiness=${readiness.blockingReasons.map((value) => value.name).join(',')}',
      if (issues.isNotEmpty)
        'issues=${issues.map((value) => value.name).join(',')}',
    ];
    return 'NutritionScoringInputValidationException(${details.join('; ')})';
  }
}

class ValidatedNutritionScoringInput {
  final ScoringCategory category;
  final NutritionBasis nutritionBasis;
  final NutritionProductState productState;
  final double? energyKj;
  final double? totalFat;
  final double saturatedFat;
  final double sugars;
  final double salt;
  // Null exactly when ScoringReadinessEvaluator independently proved N
  // already places this category/branch on the protein-excluded side of
  // its documented threshold (see NUTRITION_METHODOLOGY_2023.md) — never
  // null for cheese or beverage, which always require it. When null,
  // NutritionRawScoreCalculator applies zero protein points, which is
  // mathematically identical to applying any real value in that branch.
  final double? protein;
  final double fiber;
  final double fvlPercentage;
  final bool? nnsPresent;
  final bool isPlainWater;
  final ScoringEvidenceQuality evidenceQuality;
  final Set<ScoringReadinessWarning> readinessWarnings;

  ValidatedNutritionScoringInput._({
    required this.category,
    required this.nutritionBasis,
    required this.productState,
    required this.energyKj,
    required this.totalFat,
    required this.saturatedFat,
    required this.sugars,
    required this.salt,
    required this.protein,
    required this.fiber,
    required this.fvlPercentage,
    required this.nnsPresent,
    required this.isPlainWater,
    required this.evidenceQuality,
    required Iterable<ScoringReadinessWarning> readinessWarnings,
  }) : readinessWarnings = Set.unmodifiable(readinessWarnings);

  factory ValidatedNutritionScoringInput.validate(EtiketlyScoringInput input) {
    final readiness = const ScoringReadinessEvaluator().evaluate(input);
    if (!readiness.isScorable) {
      throw NutritionScoringInputValidationException(readiness: readiness);
    }

    final nutrition = input.nutrition;
    final category = readiness.resolvedCategory;
    final energyKj = nutrition.energyKj.value;
    final totalFat = nutrition.totalFat.value;
    final saturatedFat = nutrition.saturatedFat.value!;
    final sugars = nutrition.sugars.value!;
    final salt = nutrition.salt.value!;
    // Nullable: readiness only guarantees this is present when the
    // category/branch actually requires it (cheese, beverage, or N below
    // the documented per-category threshold). Cannot use `!` here.
    final protein = nutrition.protein.value;
    final fiber = nutrition.fiber.value!;
    final fvlPercentage = input.fvlEvidence.percentage!;
    final isPlainWater =
        input.classificationFacts.isPlainWater?.trustedValue == true;
    final issues = <NutritionScoringInputIssue>{};

    final requiredValues = <double>[
      saturatedFat,
      sugars,
      salt,
      ?protein,
      fiber,
      fvlPercentage,
      if (category != ScoringCategory.fatsOilsNutsSeeds) energyKj!,
      if (category == ScoringCategory.fatsOilsNutsSeeds) totalFat!,
    ];
    if (requiredValues.any((value) => !value.isFinite || value < 0) ||
        fvlPercentage > 100) {
      issues.add(NutritionScoringInputIssue.invalidNumericValue);
    }

    if (totalFat != null) {
      if (!totalFat.isFinite || totalFat < 0) {
        issues.add(NutritionScoringInputIssue.invalidNumericValue);
      } else if (saturatedFat > totalFat) {
        issues.add(NutritionScoringInputIssue.saturatedFatExceedsTotalFat);
      }
    }
    if (category == ScoringCategory.fatsOilsNutsSeeds && totalFat! <= 0) {
      issues.add(NutritionScoringInputIssue.nonPositiveTotalFat);
    }
    if (isPlainWater && category != ScoringCategory.beverage) {
      issues.add(NutritionScoringInputIssue.plainWaterCategoryMismatch);
    }

    if (issues.isNotEmpty) {
      throw NutritionScoringInputValidationException(
        readiness: readiness,
        issues: issues,
      );
    }

    final nnsPresent = category == ScoringCategory.beverage
        ? input.nnsEvidence.state == PresenceEvidenceState.present
        : null;

    return ValidatedNutritionScoringInput._(
      category: category,
      nutritionBasis: input.nutritionBasis,
      productState: input.productState,
      energyKj: energyKj,
      totalFat: totalFat,
      saturatedFat: saturatedFat,
      sugars: sugars,
      salt: salt,
      protein: protein,
      fiber: fiber,
      fvlPercentage: fvlPercentage,
      nnsPresent: nnsPresent,
      isPlainWater: isPlainWater,
      evidenceQuality: readiness.evidenceQuality,
      readinessWarnings: readiness.warningReasons,
    );
  }
}
