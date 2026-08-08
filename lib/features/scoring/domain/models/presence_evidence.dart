import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class PresenceEvidence {
  final PresenceEvidenceState state;
  final EvidenceProvenance provenance;
  final EvidenceVerification verification;
  final EvidenceDependency dependency;

  const PresenceEvidence.present({
    required this.provenance,
    this.verification = EvidenceVerification.unknown,
    this.dependency = EvidenceDependency.none,
  }) : state = PresenceEvidenceState.present;

  const PresenceEvidence.absent({
    required this.provenance,
    this.verification = EvidenceVerification.unknown,
    this.dependency = EvidenceDependency.completeIngredientList,
  }) : state = PresenceEvidenceState.absent;

  const PresenceEvidence.unknown()
    : state = PresenceEvidenceState.unknown,
      provenance = EvidenceProvenance.unknown,
      verification = EvidenceVerification.unknown,
      dependency = EvidenceDependency.none;

  bool get isKnown => state != PresenceEvidenceState.unknown;

  bool get isRejected => verification == EvidenceVerification.rejected;
}
