import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class ScoringReadinessResult {
  final bool isScorable;
  final ScoringCategory resolvedCategory;
  final Set<ScoringRequirement> missingRequirements;
  final Set<ScoringRequirement> requirementsNeedingEvidence;
  final Set<ScoringReadinessBlocker> blockingReasons;
  final Set<ScoringReadinessWarning> warningReasons;
  final ScoringEvidenceQuality evidenceQuality;

  ScoringReadinessResult({
    required this.isScorable,
    required this.resolvedCategory,
    Iterable<ScoringRequirement> missingRequirements = const [],
    Iterable<ScoringRequirement> requirementsNeedingEvidence = const [],
    Iterable<ScoringReadinessBlocker> blockingReasons = const [],
    Iterable<ScoringReadinessWarning> warningReasons = const [],
    required this.evidenceQuality,
  }) : missingRequirements = Set.unmodifiable(missingRequirements),
       requirementsNeedingEvidence = Set.unmodifiable(
         requirementsNeedingEvidence,
       ),
       blockingReasons = Set.unmodifiable(blockingReasons),
       warningReasons = Set.unmodifiable(warningReasons);

  bool get isEligible => isScorable;
}
