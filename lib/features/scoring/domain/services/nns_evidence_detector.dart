import 'package:food_analyzer_app/features/scoring/domain/data/nns_canonical_identifiers.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class NnsDetectionResult {
  final bool hasQualifyingMatch;
  final List<String> matchedIdentifiers;
  final String identifierVersion;

  const NnsDetectionResult({
    required this.hasQualifyingMatch,
    required this.matchedIdentifiers,
    required this.identifierVersion,
  });
}

/// Conservative exact detector. Non-detection never proves absence by itself.
class NnsEvidenceDetector {
  const NnsEvidenceDetector();

  NnsDetectionResult detect(String? ingredientText) {
    final normalized = _normalize(ingredientText ?? '');
    final matches = <String>{};

    for (final number in NnsCanonicalIdentifiers.qualifyingENumbers) {
      if (RegExp(
        '(^|[^a-zçğıöşü0-9])e[ -]?$number([^a-zçğıöşü0-9]|\$)',
        unicode: true,
      ).hasMatch(normalized)) {
        matches.add('E$number');
      }
    }
    for (final alias in NnsCanonicalIdentifiers.qualifyingAliases) {
      final escaped = RegExp.escape(alias);
      if (RegExp(
        '(^|[^a-zçğıöşü0-9])$escaped([^a-zçğıöşü0-9]|\$)',
        unicode: true,
      ).hasMatch(normalized)) {
        matches.add(alias);
      }
    }

    return NnsDetectionResult(
      hasQualifyingMatch: matches.isNotEmpty,
      matchedIdentifiers: List.unmodifiable(matches),
      identifierVersion: NnsCanonicalIdentifiers.version,
    );
  }

  PresenceEvidence ocrCandidate(String? ingredientText) {
    return detect(ingredientText).hasQualifyingMatch
        ? const PresenceEvidence.present(
            provenance: EvidenceProvenance.ocrDeclaredLabel,
            verification: EvidenceVerification.unverified,
          )
        : const PresenceEvidence.unknown();
  }

  PresenceEvidence adminVerified({
    required String? ingredientText,
    required IngredientEvidenceCompleteness completeness,
  }) {
    if (detect(ingredientText).hasQualifyingMatch) {
      return const PresenceEvidence.present(
        provenance: EvidenceProvenance.adminVerified,
        verification: EvidenceVerification.verified,
      );
    }
    if (completeness == IngredientEvidenceCompleteness.complete &&
        ingredientText?.trim().isNotEmpty == true) {
      return const PresenceEvidence.absent(
        provenance: EvidenceProvenance.adminVerified,
        verification: EvidenceVerification.verified,
        dependency: EvidenceDependency.completeIngredientList,
      );
    }
    return const PresenceEvidence.unknown();
  }

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[_–—-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
