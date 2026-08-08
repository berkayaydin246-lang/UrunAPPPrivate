import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Removes incoming nutrient evidence that does not describe the canonical row.
class ScoringEvidenceNutritionConsistency {
  const ScoringEvidenceNutritionConsistency();

  ScoringEvidenceSnapshot align(
    ScoringEvidenceSnapshot evidence,
    NutritionData? canonical,
  ) {
    final nutrition = evidence.nutrition;
    final sodium = _matching(nutrition.sodium, canonical?.sodium);
    final salt =
        nutrition.salt.provenance == EvidenceProvenance.derivedFromSodium &&
            canonical?.salt == null &&
            sodium.hasValue &&
            nutrition.salt.value != null &&
            (nutrition.salt.value! - sodium.value! * 2.5).abs() <= 0.000001
        ? nutrition.salt
        : _matching(nutrition.salt, canonical?.salt);
    return evidence.copyWith(
      nutrition: ScoringNutritionData(
        energyKj: _matching(nutrition.energyKj, canonical?.energyKj),
        energyKcal: _matching(nutrition.energyKcal, canonical?.energyKcal),
        totalFat: _matching(nutrition.totalFat, canonical?.fat),
        saturatedFat: _matching(
          nutrition.saturatedFat,
          canonical?.saturatedFat,
        ),
        sugars: _matching(nutrition.sugars, canonical?.sugars),
        protein: _matching(nutrition.protein, canonical?.proteins),
        fiber: _matching(nutrition.fiber, canonical?.fiber),
        salt: salt,
        sodium: sodium,
      ),
    );
  }

  EvidenceValue<double> _matching(
    EvidenceValue<double> evidence,
    double? canonical,
  ) {
    final value = evidence.value;
    if (value == null || canonical == null) {
      return const EvidenceValue<double>.unknown();
    }
    return (value - canonical).abs() <= 0.000001
        ? evidence
        : const EvidenceValue<double>.unknown();
  }
}
