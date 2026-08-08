import 'dart:developer' as developer;

import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';

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

    // Try matching in priority order
    Ingredient? bestMatch;
    MatchType bestMatchType = MatchType.unmatched;
    double bestConfidence = 0.0;
    String? bestMatchedToken;
    bool bestAffectsAnalysis = false;
    bool bestNeedsConfirmation = false;

    for (final ingredient in allIngredients) {
      final ingredientNormalized = ingredient.normalizedName.toLowerCase();
      final eCode = ingredient.eCode == null
          ? null
          : IngredientCanonicalizer.normalizeECode(ingredient.eCode!);
      final aliases = <String>[
        ...?ingredient.aliases,
        ...?ingredient.alternativeNames,
        ...?ingredient.commonNames,
        ...?ingredient.englishNames,
      ];

      // 1. Exact match on normalized_name
      if (ingredientNormalized == normalized) {
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

      // 2. E-code match
      if (eCode != null && normalized == eCode) {
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

      // 3. Exact alias/common/English name match
      for (final alias in aliases) {
        final normalizedAlias = normalizeIngredient(alias);
        if (normalizedAlias.isNotEmpty && normalizedAlias == normalized) {
          if (0.95 > bestConfidence) {
            bestMatch = ingredient;
            bestMatchType = MatchType.aliasMatch;
            bestMatchedToken = normalizedAlias;
            bestConfidence = 0.95;
            bestAffectsAnalysis = true;
            bestNeedsConfirmation = false;
          }
        }
      }

      // 3b. Canonical mapping match: map token to canonical form and try exact match
      final canonical = IngredientCanonicalizer.mapToCanonical(normalized);
      if (canonical != normalized) {
        if (ingredientNormalized == canonical) {
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
        // also check aliases against canonical
        for (final alias in aliases) {
          final na = normalizeIngredient(alias);
          if (na == canonical) {
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

      // 4. Strong fuzzy match for non-high-impact ingredients only.
      final similarity = _calculateSimilarity(normalized, ingredientNormalized);
      final strongFuzzyAllowed =
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
