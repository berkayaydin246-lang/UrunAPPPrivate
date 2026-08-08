import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class EtiketlyScoringInput {
  final ScoringNutritionData nutrition;
  final NutritionBasis nutritionBasis;
  final NutritionProductState productState;
  final ScoringCategoryEvidence categoryEvidence;
  final ScoringClassificationFacts classificationFacts;
  final CompositionPercentageEvidence fvlEvidence;
  final PresenceEvidence nnsEvidence;
  final IngredientEvidenceCompleteness ingredientEvidenceCompleteness;

  const EtiketlyScoringInput({
    required this.nutrition,
    required this.nutritionBasis,
    required this.productState,
    required this.categoryEvidence,
    this.classificationFacts = const ScoringClassificationFacts(),
    this.fvlEvidence = const CompositionPercentageEvidence.unknown(),
    this.nnsEvidence = const PresenceEvidence.unknown(),
    this.ingredientEvidenceCompleteness =
        IngredientEvidenceCompleteness.unknown,
  });
}
