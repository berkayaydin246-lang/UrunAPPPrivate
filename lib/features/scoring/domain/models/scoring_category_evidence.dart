import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class ScoringCategoryEvidence {
  final ScoringCategory resolvedCategory;
  final CategoryEvidenceSource source;
  final List<String> evidenceValues;
  final Set<CategoryResolutionReason> reasons;

  ScoringCategoryEvidence({
    required this.resolvedCategory,
    required this.source,
    Iterable<String> evidenceValues = const [],
    Iterable<CategoryResolutionReason> reasons = const [],
  }) : evidenceValues = List.unmodifiable(evidenceValues),
       reasons = Set.unmodifiable(reasons);

  ScoringCategoryEvidence.unknown({
    Iterable<String> evidenceValues = const [],
    Iterable<CategoryResolutionReason> reasons = const [
      CategoryResolutionReason.insufficientEvidence,
    ],
  }) : resolvedCategory = ScoringCategory.unknown,
       source = CategoryEvidenceSource.unknown,
       evidenceValues = List.unmodifiable(evidenceValues),
       reasons = Set.unmodifiable(reasons);

  bool get isSufficient =>
      resolvedCategory != ScoringCategory.unknown &&
      source != CategoryEvidenceSource.unknown;
}
