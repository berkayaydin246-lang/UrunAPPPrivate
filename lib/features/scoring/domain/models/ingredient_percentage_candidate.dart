import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// A literal percentage printed next to an ingredient on the label.
///
/// This is only a review candidate. It does not imply that the ingredient
/// qualifies for FVL or that percentages should be summed automatically.
class IngredientPercentageCandidate {
  final String ingredientText;
  final double percentage;
  final String evidenceText;
  final EvidenceProvenance provenance;
  final EvidenceVerification verification;

  const IngredientPercentageCandidate({
    required this.ingredientText,
    required this.percentage,
    required this.evidenceText,
    required this.provenance,
    this.verification = EvidenceVerification.unverified,
  });

  bool get isValid =>
      ingredientText.trim().isNotEmpty &&
      evidenceText.trim().isNotEmpty &&
      percentage.isFinite &&
      percentage >= 0 &&
      percentage <= 100;
}
