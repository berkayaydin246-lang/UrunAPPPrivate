import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class EvidenceValue<T> {
  final T? value;
  final EvidenceProvenance provenance;
  final EvidenceVerification verification;

  const EvidenceValue({
    required this.value,
    required this.provenance,
    this.verification = EvidenceVerification.unknown,
  });

  const EvidenceValue.unknown()
    : value = null,
      provenance = EvidenceProvenance.unknown,
      verification = EvidenceVerification.unknown;

  bool get hasValue => value != null;

  bool get hasKnownProvenance => provenance != EvidenceProvenance.unknown;

  bool get isRejected => verification == EvidenceVerification.rejected;

  bool get isTrusted => hasValue && hasKnownProvenance && !isRejected;

  T? get trustedValue => isTrusted ? value : null;
}
