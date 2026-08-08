import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/ingredient_percentage_candidate.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nns_evidence_detector.dart';

/// Converts structured OCR output into draft evidence without upgrading trust.
class ScoringEvidenceOcrCandidateBuilder {
  const ScoringEvidenceOcrCandidateBuilder({
    this.nnsDetector = const NnsEvidenceDetector(),
  });

  final NnsEvidenceDetector nnsDetector;

  ScoringEvidenceSnapshot? build({
    Map<String, dynamic>? nutrition,
    Map<String, dynamic>? evidenceCandidates,
    String? ingredientsText,
  }) {
    final basis = _basis(evidenceCandidates?['nutrition_basis']);
    final state = _state(evidenceCandidates?['nutrition_product_state']);
    final percentages = _percentages(
      evidenceCandidates?['ingredient_percentages'],
    );
    final scoringNutrition = _nutrition(nutrition);
    final nns = nnsDetector.ocrCandidate(ingredientsText);

    final hasEvidence =
        _hasNutrition(scoringNutrition) ||
        basis != NutritionBasis.unknown ||
        state != NutritionProductState.unknown ||
        percentages.isNotEmpty ||
        nns.isKnown;
    if (!hasEvidence) return null;

    return ScoringEvidenceSnapshot(
      nutritionBasis: basis,
      nutritionProductState: state,
      nutritionBasisEvidence: basis == NutritionBasis.unknown
          ? null
          : EvidenceValue<NutritionBasis>(
              value: basis,
              provenance: EvidenceProvenance.ocrDeclaredLabel,
              verification: EvidenceVerification.unverified,
            ),
      nutritionProductStateEvidence: state == NutritionProductState.unknown
          ? null
          : EvidenceValue<NutritionProductState>(
              value: state,
              provenance: EvidenceProvenance.ocrDeclaredLabel,
              verification: EvidenceVerification.unverified,
            ),
      nutrition: scoringNutrition,
      nnsEvidence: nns,
      ingredientPercentageCandidates: percentages,
    );
  }

  ScoringNutritionData _nutrition(Map<String, dynamic>? value) {
    EvidenceValue<double> declared(String key) {
      final parsed = _number(value?[key]);
      return parsed == null
          ? const EvidenceValue<double>.unknown()
          : EvidenceValue<double>(
              value: parsed,
              provenance: EvidenceProvenance.ocrDeclaredLabel,
              verification: EvidenceVerification.unverified,
            );
    }

    final sodium = declared('sodium');
    final declaredSalt = declared('salt');
    final salt = declaredSalt.hasValue
        ? declaredSalt
        : sodium.hasValue
        ? EvidenceValue<double>(
            value: sodium.value! * 2.5,
            provenance: EvidenceProvenance.derivedFromSodium,
            verification: EvidenceVerification.unverified,
          )
        : const EvidenceValue<double>.unknown();

    return ScoringNutritionData(
      energyKj: declared('energy_kj'),
      energyKcal: declared('energy_kcal'),
      totalFat: declared('fat'),
      saturatedFat: declared('saturated_fat'),
      sugars: declared('sugars'),
      protein: declared('proteins'),
      fiber: declared('fiber'),
      salt: salt,
      sodium: sodium,
    );
  }

  List<IngredientPercentageCandidate> _percentages(dynamic value) {
    if (value is! List) return const [];
    final result = <IngredientPercentageCandidate>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final ingredient = _text(map['ingredient_text']);
      final percentage = _number(map['percentage'], maximum: 100);
      final evidenceText = _text(map['evidence_text']);
      if (ingredient == null || percentage == null || evidenceText == null) {
        continue;
      }
      result.add(
        IngredientPercentageCandidate(
          ingredientText: ingredient,
          percentage: percentage,
          evidenceText: evidenceText,
          provenance: EvidenceProvenance.ocrDeclaredLabel,
          verification: EvidenceVerification.unverified,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  NutritionBasis _basis(dynamic value) => switch (value) {
    'per100g' || 'per_100_g' => NutritionBasis.per100g,
    'per100ml' || 'per_100_ml' => NutritionBasis.per100ml,
    'perServing' || 'per_serving' => NutritionBasis.perServing,
    _ => NutritionBasis.unknown,
  };

  NutritionProductState _state(dynamic value) => switch (value) {
    'asSold' || 'as_sold' => NutritionProductState.asSold,
    'asPrepared' || 'as_prepared' => NutritionProductState.asPrepared,
    _ => NutritionProductState.unknown,
  };

  bool _hasNutrition(ScoringNutritionData value) => [
    value.energyKj,
    value.energyKcal,
    value.totalFat,
    value.saturatedFat,
    value.sugars,
    value.protein,
    value.fiber,
    value.salt,
    value.sodium,
  ].any((field) => field.hasValue);

  double? _number(dynamic value, {double? maximum}) {
    if (value is! num) return null;
    final parsed = value.toDouble();
    if (!parsed.isFinite ||
        parsed < 0 ||
        (maximum != null && parsed > maximum)) {
      return null;
    }
    return parsed;
  }

  String? _text(dynamic value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}
