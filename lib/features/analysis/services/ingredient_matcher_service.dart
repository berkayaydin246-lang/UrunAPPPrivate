import 'dart:developer' as developer;

import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';

/// Service for normalizing and matching ingredients
class IngredientMatcherService {
  const IngredientMatcherService();

  static const Set<String> _highImpactIngredients = {
    'tartrazin',
    'sodyum nitrit',
    'sodyum benzoat',
    'aspartam',
    'monosodyum glutamat',
    'msg',
    'glikoz şurubu',
    'glikoz surubu',
    'fruktoz şurubu',
    'fruktoz surubu',
  };

  static const Set<String> _unspecifiedFunctionalLabels = {
    'antioksidan',
    'aroma verici',
    'asitlik düzenleyici',
    'emülgatör',
    'jelleştirici',
    'kabartıcı',
    'kıvam artırıcı',
    'koruyucu',
    'renklendirici',
    'stabilizör',
    'tatlandırıcı',
    'topaklanma önleyici',
  };

  /// Normalize a single ingredient text for matching.
  String normalizeIngredient(String text) {
    final normalized = IngredientCanonicalizer.normalizeToken(text);
    if (RegExp(r'^e\d{2,3}$', caseSensitive: false).hasMatch(normalized)) {
      return IngredientCanonicalizer.normalizeECode(normalized);
    }
    return normalized;
  }

  /// Parse ingredient text into individual ingredient tokens
  /// Handles comma or semicolon separated lists
  List<String> parseIngredients(String text) {
    if (text.trim().isEmpty) {
      return [];
    }

    return IngredientCanonicalizer.parseIngredientsAdvanced(text);
  }

  double _calculateSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    if (a.length < 5 || b.length < 5) return 0.0;

    final lengthDiff = (a.length - b.length).abs();
    if (lengthDiff > 3 && (a.length < 8 || b.length < 8)) {
      return 0.0;
    }

    final damerau = _normalizedEditSimilarity(a, b);
    final bPrefixLen = b.length < 4 ? b.length : 4;
    final aPrefixLen = a.length < 4 ? a.length : 4;
    final prefixBonus =
        (a.startsWith(b.substring(0, bPrefixLen)) ||
            b.startsWith(a.substring(0, aPrefixLen)))
        ? 0.04
        : 0.0;

    return (damerau + prefixBonus).clamp(0.0, 1.0);
  }

  double _normalizedEditSimilarity(String a, String b) {
    final distance = _levenshteinDistance(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    return 1.0 - (distance / maxLen);
  }

  int _levenshteinDistance(String a, String b) {
    final rows = List.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
    );
    for (var i = 0; i <= a.length; i++) {
      rows[i][0] = i;
    }
    for (var j = 0; j <= b.length; j++) {
      rows[0][j] = j;
    }
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        rows[i][j] = [
          rows[i - 1][j] + 1,
          rows[i][j - 1] + 1,
          rows[i - 1][j - 1] + cost,
        ].reduce((value, element) => value < element ? value : element);
      }
    }
    return rows[a.length][b.length];
  }

  bool _isHighImpact(Ingredient ingredient) {
    final names = <String>{
      ingredient.normalizedName.toLowerCase(),
      ingredient.name.toLowerCase(),
      if (ingredient.eCode != null)
        IngredientCanonicalizer.normalizeECode(ingredient.eCode!),
      ...?ingredient.aliases?.map((e) => e.toLowerCase()),
      ...?ingredient.commonNames?.map((e) => e.toLowerCase()),
      ...?ingredient.englishNames?.map((e) => e.toLowerCase()),
    };
    return names.any(_highImpactIngredients.contains);
  }

  Iterable<String> _aliasesFor(Ingredient ingredient) sync* {
    yield* ingredient.aliases ?? const [];
    yield* ingredient.alternativeNames ?? const [];
    yield* ingredient.commonNames ?? const [];
    yield* ingredient.englishNames ?? const [];
  }

  bool _hasCompatibleFuzzyWords(String token, String candidate) {
    final tokenWords = token
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    final candidateWords = candidate
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toList();
    if (tokenWords.length < 2 || candidateWords.length < 2) return true;

    final tokenLast = tokenWords.last;
    final candidateLast = candidateWords.last;
    if (tokenLast == candidateLast) return true;

    // Shared salt prefixes (for example "kalsiyum") are not enough to fuzzy
    // match different chemical substances such as propiyonat and format.
    return _normalizedEditSimilarity(tokenLast, candidateLast) >= 0.72;
  }

  void _debugDecision({
    required String token,
    required String candidate,
    required double confidence,
    required String reason,
    required bool selected,
  }) {
    if (const bool.fromEnvironment('dart.vm.product')) return;
    developer.log(
      '[OCR-MATCH] token="$token" candidate="$candidate" confidence=${confidence.toStringAsFixed(2)} reason=$reason selected=$selected',
      name: 'IngredientMatcherService',
    );
  }

  /// Match a single ingredient against the database
  /// Returns IngredientMatch with details
  Future<IngredientMatch> matchSingleIngredient(
    String rawIngredientText,
    List<Ingredient> allIngredients,
  ) async {
    final normalized = normalizeIngredient(rawIngredientText);

    // If empty, return unmatched
    if (normalized.isEmpty) {
      return IngredientMatch(
        originalToken: rawIngredientText,
        normalizedText: normalized,
        matchType: MatchType.unmatched,
        confidenceScore: 0.0,
        shouldAffectAnalysis: false,
        needsUserConfirmation: false,
      );
    }

    // A function name without a declared child substance is not a canonical
    // ingredient identity, even if the educational catalogue contains a row
    // with a similar display name.
    if (_unspecifiedFunctionalLabels.contains(normalized)) {
      return IngredientMatch(
        originalToken: rawIngredientText,
        normalizedText: normalized,
        matchType: MatchType.unmatched,
        confidenceScore: 0.0,
        shouldAffectAnalysis: false,
        needsUserConfirmation: false,
      );
    }

    // Complete every authoritative pass before considering fuzzy candidates.
    // Catalogue row order must never let a fuzzy chemical name beat an exact
    // normalized name, E-code, or alias.
    for (final ingredient in allIngredients) {
      if (normalizeIngredient(ingredient.normalizedName) == normalized) {
        return IngredientMatch(
          originalToken: rawIngredientText,
          normalizedText: normalized,
          matchedIngredient: ingredient,
          matchedToken: ingredient.normalizedName,
          matchType: MatchType.exactMatch,
          confidenceScore: 1.0,
          shouldAffectAnalysis: true,
          needsUserConfirmation: false,
        );
      }
    }

    for (final ingredient in allIngredients) {
      final eCode = ingredient.eCode == null
          ? null
          : IngredientCanonicalizer.normalizeECode(ingredient.eCode!);
      if (eCode == normalized) {
        return IngredientMatch(
          originalToken: rawIngredientText,
          normalizedText: normalized,
          matchedIngredient: ingredient,
          matchedToken: eCode,
          matchType: MatchType.eCodeMatch,
          confidenceScore: 0.98,
          shouldAffectAnalysis: true,
          needsUserConfirmation: false,
        );
      }
    }

    for (final ingredient in allIngredients) {
      for (final alias in _aliasesFor(ingredient)) {
        final normalizedAlias = normalizeIngredient(alias);
        if (normalizedAlias.isNotEmpty && normalizedAlias == normalized) {
          return IngredientMatch(
            originalToken: rawIngredientText,
            normalizedText: normalized,
            matchedIngredient: ingredient,
            matchedToken: normalizedAlias,
            matchType: MatchType.aliasMatch,
            confidenceScore: 0.95,
            shouldAffectAnalysis: true,
            needsUserConfirmation: false,
          );
        }
      }
    }

    final canonical = IngredientCanonicalizer.mapToCanonical(normalized);
    if (canonical != normalized) {
      for (final ingredient in allIngredients) {
        if (normalizeIngredient(ingredient.normalizedName) == canonical) {
          return IngredientMatch(
            originalToken: rawIngredientText,
            normalizedText: normalized,
            matchedIngredient: ingredient,
            matchedToken: canonical,
            matchType: MatchType.aliasMatch,
            confidenceScore: 0.97,
            shouldAffectAnalysis: true,
            needsUserConfirmation: false,
          );
        }
        for (final alias in _aliasesFor(ingredient)) {
          if (normalizeIngredient(alias) == canonical) {
            return IngredientMatch(
              originalToken: rawIngredientText,
              normalizedText: normalized,
              matchedIngredient: ingredient,
              matchedToken: alias,
              matchType: MatchType.aliasMatch,
              confidenceScore: 0.96,
              shouldAffectAnalysis: true,
              needsUserConfirmation: false,
            );
          }
        }
      }
    }

    final reviewedStaticIdentity = reviewedCanonicalIngredientIdentityForToken(
      normalized,
    );
    if (reviewedStaticIdentity != null) {
      final normalizedECode = reviewedStaticIdentity.eCode == null
          ? null
          : IngredientCanonicalizer.normalizeECode(
              reviewedStaticIdentity.eCode!,
            );
      final matchType = normalized == normalizedECode
          ? MatchType.eCodeMatch
          : normalizeIngredient(reviewedStaticIdentity.normalizedName) ==
                normalized
          ? MatchType.exactMatch
          : MatchType.aliasMatch;
      return IngredientMatch(
        originalToken: rawIngredientText,
        normalizedText: normalized,
        matchedIngredient: reviewedStaticIdentity,
        matchedToken: matchType == MatchType.eCodeMatch
            ? normalizedECode
            : reviewedStaticIdentity.normalizedName,
        matchType: matchType,
        confidenceScore: matchType == MatchType.exactMatch ? 1 : 0.95,
        shouldAffectAnalysis: true,
        needsUserConfirmation: false,
      );
    }

    Ingredient? bestMatch;
    MatchType bestMatchType = MatchType.unmatched;
    double bestConfidence = 0.0;
    String? bestMatchedToken;
    bool bestAffectsAnalysis = false;
    bool bestNeedsConfirmation = false;

    for (final ingredient in allIngredients) {
      final ingredientNormalized = normalizeIngredient(
        ingredient.normalizedName,
      );
      final compatibleWords = _hasCompatibleFuzzyWords(
        normalized,
        ingredientNormalized,
      );

      // 4. Strong fuzzy match for non-high-impact ingredients only.
      final similarity = _calculateSimilarity(normalized, ingredientNormalized);
      final strongFuzzyAllowed =
          compatibleWords &&
          normalized.length >= 5 &&
          ingredientNormalized.length >= 5 &&
          (normalized.length - ingredientNormalized.length).abs() <= 3;

      if (strongFuzzyAllowed && similarity >= 0.88) {
        final highImpact = _isHighImpact(ingredient);
        final threshold = highImpact ? 0.92 : 0.88;
        if (similarity >= threshold && similarity > bestConfidence) {
          bestMatch = ingredient;
          bestMatchType = MatchType.highConfidenceFuzzy;
          bestMatchedToken = ingredient.name;
          bestConfidence = similarity;
          bestAffectsAnalysis = true;
          bestNeedsConfirmation = false;
        }
      }

      // 5. Low-confidence possible match: conservative and never affects analysis until approved.
      final possibleAllowed =
          compatibleWords &&
          normalized.length >= 5 &&
          ingredientNormalized.length >= 5 &&
          (normalized.length - ingredientNormalized.length).abs() <= 3;

      if (possibleAllowed && similarity >= 0.70 && similarity < 0.88) {
        final highImpact = _isHighImpact(ingredient);
        if (highImpact && similarity < 0.92) {
          _debugDecision(
            token: normalized,
            candidate: ingredient.name,
            confidence: similarity,
            reason: 'rejected_high_impact_below_threshold',
            selected: false,
          );
          continue;
        }
        if (similarity > bestConfidence) {
          bestMatch = ingredient;
          bestMatchType = MatchType.lowConfidencePossible;
          bestMatchedToken = ingredient.name;
          bestConfidence = similarity;
          bestAffectsAnalysis = false;
          bestNeedsConfirmation = true;
        }
      }
    }

    if (bestMatch != null) {
      final selected = bestAffectsAnalysis || bestNeedsConfirmation;
      _debugDecision(
        token: normalized,
        candidate: bestMatch.name,
        confidence: bestConfidence,
        reason: bestMatchType.name,
        selected: selected,
      );
      return IngredientMatch(
        originalToken: rawIngredientText,
        normalizedText: normalized,
        matchedIngredient: bestMatch,
        matchedToken: bestMatchedToken,
        matchType: bestMatchType,
        confidenceScore: bestConfidence,
        shouldAffectAnalysis: bestAffectsAnalysis,
        needsUserConfirmation: bestNeedsConfirmation,
      );
    }

    return IngredientMatch(
      originalToken: rawIngredientText,
      normalizedText: normalized,
      matchType: MatchType.unmatched,
      confidenceScore: 0.0,
      shouldAffectAnalysis: false,
      needsUserConfirmation: false,
    );
  }

  /// Match all ingredients from OCR text against database
  /// Returns IngredientMatchingResult with all matches
  Future<IngredientMatchingResult> matchIngredients(
    String ocrText,
    List<Ingredient> allIngredients,
  ) async {
    // 1. Parse ingredients from text
    final ingredientTokens = parseIngredients(ocrText);

    return matchIngredientTokens(ingredientTokens, allIngredients);
  }

  /// Match already-structured ingredient tokens without reparsing raw text.
  Future<IngredientMatchingResult> matchIngredientTokens(
    List<String> ingredientTokens,
    List<Ingredient> allIngredients,
  ) async {
    // 1. Match each ingredient
    final List<IngredientMatch> matches = [];
    for (final token in ingredientTokens) {
      final match = await matchSingleIngredient(token, allIngredients);
      matches.add(match);
    }

    // 2. Return results
    return IngredientMatchingResult(matches: matches);
  }
}
