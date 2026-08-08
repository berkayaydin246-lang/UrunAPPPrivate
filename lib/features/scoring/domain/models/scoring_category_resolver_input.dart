import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class ScoringCategoryResolverInput {
  final List<String> categoryTags;
  final String? canonicalCategory;
  final String? canonicalSubcategory;
  final EvidenceProvenance taxonomyProvenance;
  final EvidenceVerification taxonomyVerification;
  final EvidenceValue<ScoringCategory>? explicitCategory;
  final ScoringClassificationFacts facts;

  ScoringCategoryResolverInput({
    Iterable<String> categoryTags = const [],
    this.canonicalCategory,
    this.canonicalSubcategory,
    this.taxonomyProvenance = EvidenceProvenance.unknown,
    this.taxonomyVerification = EvidenceVerification.unknown,
    this.explicitCategory,
    this.facts = const ScoringClassificationFacts(),
  }) : categoryTags = List.unmodifiable(categoryTags);
}
