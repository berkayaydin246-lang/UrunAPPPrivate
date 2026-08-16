import 'dart:developer' as developer;

import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_canonicalizer.dart';
import 'package:food_analyzer_app/features/product/data/ingredient_explanation_catalog.dart';

class _AliasCandidate {
  const _AliasCandidate({
    required this.ingredient,
    required this.matchedAlias,
    required this.fieldPriority,
  });

  final Ingredient ingredient;
  final String matchedAlias;
  final int fieldPriority;
}

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
    // "arttırıcı" (double t) is a very common misspelling of "artırıcı" on
    // real product labels — same functional class, not a different label.
    'kıvam arttırıcı',
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

  // Field priority used only to break ties between multiple canonical rows
  // that independently claim the same alias text (a genuine, observed
  // production condition — e.g. three separate "palm oil" rows). Direct
  // `aliases` are curated most deliberately; `englishNames` are the most
  // auxiliary, so they rank lowest.
  Iterable<({List<String> values, int priority})> _aliasFieldsFor(
    Ingredient ingredient,
  ) sync* {
    yield (values: ingredient.aliases ?? const [], priority: 0);
    yield (values: ingredient.alternativeNames ?? const [], priority: 1);
    yield (values: ingredient.commonNames ?? const [], priority: 2);
    yield (values: ingredient.englishNames ?? const [], priority: 3);
  }

  bool _hasValidECode(Ingredient ingredient) =>
      ingredient.eCode?.trim().isNotEmpty == true;

  /// Deterministic, source-order-independent tie-break for the exact and
  /// e-code tiers: a candidate with its own explicit, verified e-code
  /// identity is preferred over an alias-only duplicate; a final id-based
  /// ordering guarantees the same token always resolves to the same row
  /// regardless of how allIngredients happened to be ordered.
  Ingredient _pickPreferredCandidate(List<Ingredient> candidates) {
    final sorted = [...candidates]
      ..sort((a, b) {
        final aRank = _hasValidECode(a) ? 0 : 1;
        final bRank = _hasValidECode(b) ? 0 : 1;
        if (aRank != bRank) return aRank - bRank;
        return a.id.compareTo(b.id);
      });
    return sorted.first;
  }

  /// Same determinism guarantee as [_pickPreferredCandidate], additionally
  /// preferring a match found via a higher-priority alias field.
  _AliasCandidate _pickPreferredAliasCandidate(
    List<_AliasCandidate> candidates,
  ) {
    final sorted = [...candidates]
      ..sort((a, b) {
        final aRank = _hasValidECode(a.ingredient) ? 0 : 1;
        final bRank = _hasValidECode(b.ingredient) ? 0 : 1;
        if (aRank != bRank) return aRank - bRank;
        if (a.fieldPriority != b.fieldPriority) {
          return a.fieldPriority - b.fieldPriority;
        }
        return a.ingredient.id.compareTo(b.ingredient.id);
      });
    return sorted.first;
  }

  // Generic Turkish food head-nouns shared by dozens of otherwise-unrelated
  // ingredients (many distinct oils all end in "yağı", many distinct powders
  // all end in "tozu", etc.). A last-word match against one of these carries
  // no discriminating evidence by itself — see _hasCompatibleFuzzyWords.
  static const Set<String> _genericHeadNouns = {
    'yağı',
    'yagi',
    'tozu',
    'şurubu',
    'surubu',
    'proteini',
    'ekstraktı',
    'ekstrakti',
    'aroması',
    'aromasi',
    'unu',
  };

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
    if (tokenLast == candidateLast) {
      // A shared last word is only meaningful compatibility evidence when it
      // is NOT a generic head noun (e.g. "pamuk yağı" and "palm yağı" both
      // end in "yağı" despite being unrelated oils). For a generic head
      // noun, the distinguishing (non-final) word(s) must also be similar.
      if (!_genericHeadNouns.contains(tokenLast)) return true;
      final tokenLead = tokenWords.sublist(0, tokenWords.length - 1).join(' ');
      final candidateLead = candidateWords
          .sublist(0, candidateWords.length - 1)
          .join(' ');
      if (tokenLead == candidateLead) return true;
      return _normalizedEditSimilarity(tokenLead, candidateLead) >= 0.72;
    }

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
    // normalized name, E-code, or alias. Within each authoritative tier,
    // candidates are collected first rather than returning on the first
    // iteration hit — production data contains genuine duplicate canonical
    // rows (e.g. three separate "palm oil" rows, two separate E471 rows)
    // whose relative order in allIngredients is an incidental artifact of
    // ProductRepository.getAllIngredients() (ORDER BY name), not a
    // deliberate precedence signal. _pickPreferredCandidate /
    // _pickPreferredAliasCandidate apply an explicit, source-order-
    // independent tie-break so the same token always resolves to the same
    // canonical id.
    final exactCandidates = <Ingredient>[
      for (final ingredient in allIngredients)
        if (normalizeIngredient(ingredient.normalizedName) == normalized)
          ingredient,
    ];
    if (exactCandidates.isNotEmpty) {
      final winner = _pickPreferredCandidate(exactCandidates);
      return IngredientMatch(
        originalToken: rawIngredientText,
        normalizedText: normalized,
        matchedIngredient: winner,
        matchedToken: winner.normalizedName,
        matchType: MatchType.exactMatch,
        confidenceScore: 1.0,
        shouldAffectAnalysis: true,
        needsUserConfirmation: false,
      );
    }

    final eCodeCandidates = <Ingredient>[
      for (final ingredient in allIngredients)
        if (ingredient.eCode != null &&
            IngredientCanonicalizer.normalizeECode(ingredient.eCode!) ==
                normalized)
          ingredient,
    ];
    if (eCodeCandidates.isNotEmpty) {
      final winner = _pickPreferredCandidate(eCodeCandidates);
      final eCode = IngredientCanonicalizer.normalizeECode(winner.eCode!);
      return IngredientMatch(
        originalToken: rawIngredientText,
        normalizedText: normalized,
        matchedIngredient: winner,
        matchedToken: eCode,
        matchType: MatchType.eCodeMatch,
        confidenceScore: 0.98,
        shouldAffectAnalysis: true,
        needsUserConfirmation: false,
      );
    }

    final aliasCandidates = <_AliasCandidate>[];
    for (final ingredient in allIngredients) {
      for (final field in _aliasFieldsFor(ingredient)) {
        for (final alias in field.values) {
          final normalizedAlias = normalizeIngredient(alias);
          if (normalizedAlias.isNotEmpty && normalizedAlias == normalized) {
            aliasCandidates.add(
              _AliasCandidate(
                ingredient: ingredient,
                matchedAlias: normalizedAlias,
                fieldPriority: field.priority,
              ),
            );
          }
        }
      }
    }
    if (aliasCandidates.isNotEmpty) {
      final winner = _pickPreferredAliasCandidate(aliasCandidates);
      return IngredientMatch(
        originalToken: rawIngredientText,
        normalizedText: normalized,
        matchedIngredient: winner.ingredient,
        matchedToken: winner.matchedAlias,
        matchType: MatchType.aliasMatch,
        confidenceScore: 0.95,
        shouldAffectAnalysis: true,
        needsUserConfirmation: false,
      );
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
