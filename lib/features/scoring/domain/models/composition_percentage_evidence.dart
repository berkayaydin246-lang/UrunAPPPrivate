import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class CompositionPercentageEvidence {
  final CompositionPercentageState state;
  final double? percentage;
  final EvidenceProvenance provenance;
  final EvidenceVerification verification;
  final EvidenceDependency dependency;

  const CompositionPercentageEvidence.known(
    double this.percentage, {
    required this.provenance,
    this.verification = EvidenceVerification.unknown,
    this.dependency = EvidenceDependency.none,
  }) : assert(percentage >= 0 && percentage <= 100),
       state = CompositionPercentageState.known;

  const CompositionPercentageEvidence.provenAbsent({
    required this.provenance,
    this.verification = EvidenceVerification.unknown,
    this.dependency = EvidenceDependency.completeIngredientList,
  }) : state = CompositionPercentageState.provenAbsent,
       percentage = 0;

  const CompositionPercentageEvidence.unknown()
    : state = CompositionPercentageState.unknown,
      percentage = null,
      provenance = EvidenceProvenance.unknown,
      verification = EvidenceVerification.unknown,
      dependency = EvidenceDependency.none;

  bool get hasDeterministicValue =>
      state == CompositionPercentageState.known ||
      state == CompositionPercentageState.provenAbsent;

  bool get isRejected => verification == EvidenceVerification.rejected;
}
