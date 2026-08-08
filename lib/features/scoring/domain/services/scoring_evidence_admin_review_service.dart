import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nns_evidence_detector.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

class ScoringEvidenceAdminDraft {
  final Map<String, dynamic>? reviewedNutrition;
  final String? ingredientText;
  final NutritionBasis nutritionBasis;
  final NutritionProductState productState;
  final IngredientEvidenceCompleteness ingredientCompleteness;
  final CompositionPercentageState fvlState;
  final double? fvlPercentage;
  final PresenceEvidenceState nnsState;
  final ScoringCategory category;
  final bool? isPlainWater;
  final double? redMeatPercentage;
  final bool? redMeatIsPrimaryIngredient;
  final double? nutSeedPercentage;
  final bool? isPlantBasedCheeseAlternative;
  final bool? isCompoundProduct;
  final ScoringEvidenceSnapshot? existingCandidate;
  final String? verifiedBy;
  final DateTime? verifiedAt;

  const ScoringEvidenceAdminDraft({
    this.reviewedNutrition,
    this.ingredientText,
    this.nutritionBasis = NutritionBasis.unknown,
    this.productState = NutritionProductState.unknown,
    this.ingredientCompleteness = IngredientEvidenceCompleteness.unknown,
    this.fvlState = CompositionPercentageState.unknown,
    this.fvlPercentage,
    this.nnsState = PresenceEvidenceState.unknown,
    this.category = ScoringCategory.unknown,
    this.isPlainWater,
    this.redMeatPercentage,
    this.redMeatIsPrimaryIngredient,
    this.nutSeedPercentage,
    this.isPlantBasedCheeseAlternative,
    this.isCompoundProduct,
    this.existingCandidate,
    this.verifiedBy,
    this.verifiedAt,
  });
}

class ScoringEvidenceAdminReviewResult {
  final ScoringEvidenceSnapshot evidence;
  final ScoringReadinessResult readiness;
  final List<String> validationIssues;

  const ScoringEvidenceAdminReviewResult({
    required this.evidence,
    required this.readiness,
    required this.validationIssues,
  });

  bool get isValid => validationIssues.isEmpty;
}

/// Produces one internally consistent admin-verified evidence snapshot.
class ScoringEvidenceAdminReviewService {
  const ScoringEvidenceAdminReviewService({
    this.nnsDetector = const NnsEvidenceDetector(),
    this.categoryResolver = const ScoringCategoryResolver(),
    this.readinessEvaluator = const ScoringReadinessEvaluator(),
  });

  final NnsEvidenceDetector nnsDetector;
  final ScoringCategoryResolver categoryResolver;
  final ScoringReadinessEvaluator readinessEvaluator;

  ScoringEvidenceAdminReviewResult build(ScoringEvidenceAdminDraft draft) {
    final issues = <String>[];
    final nutrition = _nutrition(draft.reviewedNutrition);
    final fvl = _fvl(draft, issues);
    final nns = _nns(draft, issues);
    final facts = _facts(draft, issues);
    final explicitCategory = draft.category == ScoringCategory.unknown
        ? null
        : EvidenceValue<ScoringCategory>(
            value: draft.category,
            provenance: EvidenceProvenance.adminVerified,
            verification: EvidenceVerification.verified,
          );
    final categoryEvidence = categoryResolver.resolve(
      ScoringCategoryResolverInput(
        explicitCategory: explicitCategory,
        facts: facts,
      ),
    );

    final evidence = ScoringEvidenceSnapshot(
      nutritionBasis: draft.nutritionBasis,
      nutritionProductState: draft.productState,
      nutritionBasisEvidence: draft.nutritionBasis == NutritionBasis.unknown
          ? null
          : EvidenceValue<NutritionBasis>(
              value: draft.nutritionBasis,
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            ),
      nutritionProductStateEvidence:
          draft.productState == NutritionProductState.unknown
          ? null
          : EvidenceValue<NutritionProductState>(
              value: draft.productState,
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            ),
      nutrition: nutrition,
      fvlEvidence: fvl,
      nnsEvidence: nns,
      ingredientEvidenceCompleteness: draft.ingredientCompleteness,
      categoryEvidence: categoryEvidence,
      classificationFacts: facts,
      ingredientPercentageCandidates:
          draft.existingCandidate?.ingredientPercentageCandidates ?? const [],
      adminVerification: ScoringEvidenceAdminMetadata(
        verifiedBy: draft.verifiedBy,
        verifiedAt: (draft.verifiedAt ?? DateTime.now()).toUtc(),
      ),
    );

    return ScoringEvidenceAdminReviewResult(
      evidence: evidence,
      readiness: readinessEvaluator.evaluate(evidence.toScoringInput()),
      validationIssues: List.unmodifiable(issues),
    );
  }

  ScoringNutritionData _nutrition(Map<String, dynamic>? value) {
    final normalized = normalizeNutritionMap(value);
    EvidenceValue<double> verified(String key) {
      final raw = normalized?[key];
      return raw is num
          ? EvidenceValue<double>(
              value: raw.toDouble(),
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            )
          : const EvidenceValue<double>.unknown();
    }

    final sodium = verified('sodium');
    final declaredSalt = verified('salt');
    final salt = declaredSalt.hasValue
        ? declaredSalt
        : sodium.hasValue
        ? EvidenceValue<double>(
            value: sodium.value! * 2.5,
            provenance: EvidenceProvenance.derivedFromSodium,
            verification: EvidenceVerification.verified,
          )
        : const EvidenceValue<double>.unknown();
    return ScoringNutritionData(
      energyKj: verified('energy_kj'),
      energyKcal: verified('energy_kcal'),
      totalFat: verified('fat'),
      saturatedFat: verified('saturated_fat'),
      sugars: verified('sugars'),
      protein: verified('proteins'),
      fiber: verified('fiber'),
      salt: salt,
      sodium: sodium,
    );
  }

  CompositionPercentageEvidence _fvl(
    ScoringEvidenceAdminDraft draft,
    List<String> issues,
  ) {
    switch (draft.fvlState) {
      case CompositionPercentageState.unknown:
        return const CompositionPercentageEvidence.unknown();
      case CompositionPercentageState.known:
        final percentage = draft.fvlPercentage;
        if (percentage == null ||
            !percentage.isFinite ||
            percentage < 0 ||
            percentage > 100) {
          issues.add('FVL oranı 0 ile 100 arasında olmalıdır.');
          return const CompositionPercentageEvidence.unknown();
        }
        return CompositionPercentageEvidence.known(
          percentage,
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
        );
      case CompositionPercentageState.provenAbsent:
        if (draft.ingredientCompleteness !=
                IngredientEvidenceCompleteness.complete ||
            draft.ingredientText?.trim().isNotEmpty != true) {
          issues.add(
            'FVL yokluğu için içerik listesi tam ve okunabilir olmalıdır.',
          );
          return const CompositionPercentageEvidence.unknown();
        }
        return const CompositionPercentageEvidence.provenAbsent(
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
          dependency: EvidenceDependency.completeIngredientList,
        );
    }
  }

  PresenceEvidence _nns(ScoringEvidenceAdminDraft draft, List<String> issues) {
    final detection = nnsDetector.detect(draft.ingredientText);
    switch (draft.nnsState) {
      case PresenceEvidenceState.present:
        return const PresenceEvidence.present(
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
        );
      case PresenceEvidenceState.absent:
        if (draft.ingredientCompleteness !=
                IngredientEvidenceCompleteness.complete ||
            draft.ingredientText?.trim().isNotEmpty != true) {
          issues.add(
            'Tatlandırıcı yokluğu için içerik listesi tam ve okunabilir olmalıdır.',
          );
          return const PresenceEvidence.unknown();
        }
        if (detection.hasQualifyingMatch) {
          issues.add(
            'İçerik listesinde puanlama kapsamındaki bir tatlandırıcı bulundu.',
          );
          return const PresenceEvidence.unknown();
        }
        return const PresenceEvidence.absent(
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
          dependency: EvidenceDependency.completeIngredientList,
        );
      case PresenceEvidenceState.unknown:
        return nnsDetector.ocrCandidate(draft.ingredientText);
    }
  }

  ScoringClassificationFacts _facts(
    ScoringEvidenceAdminDraft draft,
    List<String> issues,
  ) {
    final redMeatPercentage = _percentage(
      draft.redMeatPercentage,
      'Kırmızı et oranı',
      issues,
    );
    final nutSeedPercentage = _percentage(
      draft.nutSeedPercentage,
      'Kuruyemiş/tohum oranı',
      issues,
    );
    return ScoringClassificationFacts(
      isPlainWater: _verifiedBool(draft.isPlainWater),
      redMeatPercentage: _verifiedDouble(redMeatPercentage),
      redMeatIsPrimaryIngredient: _verifiedBool(
        draft.redMeatIsPrimaryIngredient,
      ),
      nutSeedPercentage: _verifiedDouble(nutSeedPercentage),
      isPlantBasedCheeseAlternative: _verifiedBool(
        draft.isPlantBasedCheeseAlternative,
      ),
      isCompoundProduct: _verifiedBool(draft.isCompoundProduct),
    );
  }

  double? _percentage(double? value, String label, List<String> issues) {
    if (value == null) return null;
    if (!value.isFinite || value < 0 || value > 100) {
      issues.add('$label 0 ile 100 arasında olmalıdır.');
      return null;
    }
    return value;
  }

  EvidenceValue<bool>? _verifiedBool(bool? value) => value == null
      ? null
      : EvidenceValue<bool>(
          value: value,
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
        );

  EvidenceValue<double>? _verifiedDouble(double? value) => value == null
      ? null
      : EvidenceValue<double>(
          value: value,
          provenance: EvidenceProvenance.adminVerified,
          verification: EvidenceVerification.verified,
        );
}
