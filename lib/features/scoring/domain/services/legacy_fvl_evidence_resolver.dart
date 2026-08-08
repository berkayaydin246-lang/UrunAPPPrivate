import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

class LegacyFvlEvidenceResolution {
  const LegacyFvlEvidenceResolution({
    required this.evidence,
    required this.hasQualifyingIngredient,
  });

  final CompositionPercentageEvidence evidence;
  final bool hasQualifyingIngredient;

  bool get isReady => evidence.hasDeterministicValue;
}

/// Recovers only literal, source-complete legacy FVL evidence.
class LegacyFvlEvidenceResolver {
  const LegacyFvlEvidenceResolver();

  static final _qualifyingSignal = RegExp(
    r'\b(?:meyve|sebze|baklagil|elma|armut|muz|portakal|mandalina|limon|greyfurt|uzum|cilek|ahududu|bogurtlen|frambuaz|visne|kiraz|seftali|kayisi|erik|ananas|mango|kivi|nar|kavun|karpuz|hurma|incir|ayva|avokado|zeytin|domates|biber|sogan|sarimsak|havuc|patates|brokoli|karnabahar|ispanak|pirasa|kabak|patlican|salatalik|lahana|kereviz|enginar|pancar|marul|roka|mantar|mercimek|nohut|fasulye|bezelye|bakla|borulce|soya)\b',
    caseSensitive: false,
  );

  static final _nonQualifyingForm = RegExp(
    r'\b(?:toz|unu|un|nisasta|aroma|aromali|ekstrakt|pektin|lesitin|sirke)\b|limon tuzu|dondurularak kurutul',
    caseSensitive: false,
  );

  static final _factorOrStateAmbiguous = RegExp(
    r'\b(?:kuru|kurutulmus|konsantre|konsantresi|konsantreden)\b',
    caseSensitive: false,
  );

  static final _oilForm = RegExp(
    r'\b(?:yag|yagi|yaglari|oil)\b',
    caseSensitive: false,
  );

  static final _percentage = RegExp(
    r'(?:%\s*(\d+(?:[.,]\d+)?)|(\d+(?:[.,]\d+)?)\s*%)',
  );

  LegacyFvlEvidenceResolution resolve({
    required String? ingredientsText,
    required bool sourceComplete,
    required ScoringCategory category,
  }) {
    if (!sourceComplete || ingredientsText == null) {
      return const LegacyFvlEvidenceResolution(
        evidence: CompositionPercentageEvidence.unknown(),
        hasQualifyingIngredient: false,
      );
    }

    var foundQualifying = false;
    var percentageTotal = 0.0;
    for (final segment in _segments(ingredientsText)) {
      final normalized = _foldTurkish(
        IngredientCanonicalizer.normalizeToken(segment),
      );
      if (!_qualifyingSignal.hasMatch(normalized)) continue;
      if (_nonQualifyingForm.hasMatch(normalized)) continue;
      if (_oilForm.hasMatch(normalized) &&
          category != ScoringCategory.fatsOilsNutsSeeds) {
        continue;
      }

      foundQualifying = true;
      if (_factorOrStateAmbiguous.hasMatch(normalized)) {
        return const LegacyFvlEvidenceResolution(
          evidence: CompositionPercentageEvidence.unknown(),
          hasQualifyingIngredient: true,
        );
      }

      final percentages = _percentage
          .allMatches(segment)
          .map((match) => _number(match.group(1) ?? match.group(2)))
          .whereType<double>()
          .toList(growable: false);
      if (percentages.length != 1) {
        return const LegacyFvlEvidenceResolution(
          evidence: CompositionPercentageEvidence.unknown(),
          hasQualifyingIngredient: true,
        );
      }
      percentageTotal += percentages.single;
      if (percentageTotal > 100) {
        return const LegacyFvlEvidenceResolution(
          evidence: CompositionPercentageEvidence.unknown(),
          hasQualifyingIngredient: true,
        );
      }
    }

    if (!foundQualifying) {
      return const LegacyFvlEvidenceResolution(
        evidence: CompositionPercentageEvidence.provenAbsent(
          provenance: EvidenceProvenance.databaseImport,
          verification: EvidenceVerification.verified,
        ),
        hasQualifyingIngredient: false,
      );
    }
    return LegacyFvlEvidenceResolution(
      evidence: CompositionPercentageEvidence.known(
        percentageTotal,
        provenance: EvidenceProvenance.declaredLabel,
        verification: EvidenceVerification.verified,
        dependency: EvidenceDependency.completeIngredientList,
      ),
      hasQualifyingIngredient: true,
    );
  }

  List<String> _segments(String value) {
    final segments = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    void flush() {
      final segment = buffer.toString().trim();
      buffer.clear();
      if (segment.isNotEmpty) segments.add(segment);
    }

    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      if (character == '(') depth++;
      if (character == ')' && depth > 0) depth--;
      if (depth == 0 && (character == ',' || character == ';')) {
        flush();
      } else {
        buffer.write(character);
      }
    }
    flush();
    return segments;
  }

  double? _number(String? value) {
    if (value == null) return null;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    return parsed != null && parsed.isFinite && parsed >= 0 && parsed <= 100
        ? parsed
        : null;
  }

  String _foldTurkish(String value) => value
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u');
}
