import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';

/// Cleans unmatched ingredient fragments so the UI only shows meaningful items.
class UnknownIngredientSanitizer {
  static List<String> sanitizeUnknownIngredients({
    required List<String> rawUnknowns,
    required Iterable<IngredientMatch> matches,
  }) {
    final knownForms = <String>{};
    for (final match in matches) {
      if (!match.isMatched) continue;
      final tokens = <String>{
        match.originalToken,
        match.normalizedText,
        match.matchedToken ?? '',
        match.matchedIngredient?.name ?? '',
        match.matchedIngredient?.normalizedName ?? '',
        ...?match.matchedIngredient?.aliases,
        ...?match.matchedIngredient?.commonNames,
        ...?match.matchedIngredient?.alternativeNames,
        ...?match.matchedIngredient?.englishNames,
      };
      for (final token in tokens) {
        final normalized = _normalizeKnown(token);
        if (normalized.isNotEmpty) {
          knownForms.add(normalized);
        }
      }
    }

    final result = <String>[];
    final seen = <String>{};

    for (final raw in rawUnknowns) {
      // Hide overly long parenthetical unknowns from user-facing list (keep for telemetry only).
      if ((raw.contains('(') || raw.contains(')')) &&
          raw.split(RegExp(r'\s+')).length > 5) {
        continue;
      }

      final cleaned = _cleanUnknownFragment(raw);
      if (cleaned.isEmpty) continue;
      final normalized = _normalizeUnknown(cleaned);
      if (normalized.isEmpty) continue;
      if (_shouldDiscard(normalized)) continue;
      if (knownForms.contains(normalized)) continue;
      if (_isSubstringOfKnown(normalized, knownForms)) continue;
      if (seen.add(normalized)) {
        result.add(normalized);
      }
    }

    return result;
  }

  static String _cleanUnknownFragment(String value) {
    var text = value.trim();
    if (text.isEmpty) return '';

    text = text.replaceAll(RegExp(r'[\[\]{}]'), ' ');
    text = text.replaceAll(RegExp(r'["“”‘’]'), ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    text = text.replaceAll(RegExp(r'^[\s,;:/\-–—]+|[\s,;:/\-–—]+$'), '');
    text = text.replaceAll(RegExp(r'\(\s*\)'), '');
    return text.trim();
  }

  static String _normalizeKnown(String value) {
    final cleaned = IngredientCanonicalizer.normalizeToken(value);
    final canonical = IngredientCanonicalizer.mapToCanonical(cleaned);
    return canonical.trim();
  }

  static String _normalizeUnknown(String value) {
    var cleaned = IngredientCanonicalizer.normalizeToken(value);
    cleaned = IngredientCanonicalizer.mapToCanonical(cleaned);
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b(?:mg/l|mg|g/l|g|kg|ml/l|ml|l|mcg|μg|ug)\b',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\b\d+(?:[.,]\d+)?\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned;
  }

  static bool _shouldDiscard(String value) {
    if (value.isEmpty) return true;
    if (value.length <= 1) return true;
    if (RegExp(r'^[\d\s.,/%+-]+$').hasMatch(value)) return true;
    if (RegExp(r'^[\W_]+$').hasMatch(value)) {
      return true;
    }
    if (RegExp(r'^\d+\s+\D+').hasMatch(value) && !value.startsWith('e')) {
      return true;
    }
    if (value == '()' || value == '[]' || value == '{}') {
      return true;
    }
    if (value.startsWith('(') && value.endsWith(')')) {
      return true;
    }
    return false;
  }

  static bool _isSubstringOfKnown(String candidate, Set<String> knownForms) {
    for (final known in knownForms) {
      if (known.isEmpty) {
        continue;
      }
      if (candidate == known) {
        return true;
      }
      if (candidate.length >= 4 && known.contains(candidate)) {
        return true;
      }
      if (candidate.length < known.length &&
          candidate.length >= 4 &&
          candidate.startsWith(known)) {
        return true;
      }
      if (candidate.length < known.length &&
          known.startsWith(candidate) &&
          candidate.length >= 4) {
        return true;
      }
    }
    return false;
  }
}
