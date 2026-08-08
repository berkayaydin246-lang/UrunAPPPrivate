import 'package:food_analyzer_app/features/product/models/ingredient.dart';

/// Type of match for an ingredient
enum MatchType {
  exactMatch,
  eCodeMatch,
  aliasMatch,
  highConfidenceFuzzy,
  lowConfidencePossible,
  unmatched, // no match found
}

/// Result of matching a single ingredient from OCR text
class IngredientMatch {
  final String originalToken; // raw OCR token before matching
  final String normalizedText; // normalized version used for comparisons
  final Ingredient? matchedIngredient; // matched database ingredient if found
  final String? matchedToken; // token or alias that produced the match
  final double confidenceScore; // 0.0 to 1.0
  final MatchType matchType;
  final bool shouldAffectAnalysis;
  final bool needsUserConfirmation;
  final bool? userApproved;

  IngredientMatch({
    required this.originalToken,
    required this.normalizedText,
    this.matchedIngredient,
    this.matchedToken,
    required this.confidenceScore,
    required this.matchType,
    this.shouldAffectAnalysis = false,
    this.needsUserConfirmation = false,
    this.userApproved,
  });

  bool get isMatched => matchedIngredient != null;
  bool get isConfirmed => shouldAffectAnalysis;
  bool get isLowConfidence => matchType == MatchType.lowConfidencePossible;
  bool get isRejected => userApproved == false;

  IngredientMatch copyWith({
    String? originalToken,
    String? normalizedText,
    Ingredient? matchedIngredient,
    String? matchedToken,
    double? confidenceScore,
    MatchType? matchType,
    bool? shouldAffectAnalysis,
    bool? needsUserConfirmation,
    bool? userApproved,
  }) {
    return IngredientMatch(
      originalToken: originalToken ?? this.originalToken,
      normalizedText: normalizedText ?? this.normalizedText,
      matchedIngredient: matchedIngredient ?? this.matchedIngredient,
      matchedToken: matchedToken ?? this.matchedToken,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      matchType: matchType ?? this.matchType,
      shouldAffectAnalysis: shouldAffectAnalysis ?? this.shouldAffectAnalysis,
      needsUserConfirmation:
          needsUserConfirmation ?? this.needsUserConfirmation,
      userApproved: userApproved ?? this.userApproved,
    );
  }

  IngredientMatch approveLowConfidence() => copyWith(
    shouldAffectAnalysis: true,
    needsUserConfirmation: false,
    userApproved: true,
  );

  IngredientMatch rejectLowConfidence() => copyWith(
    shouldAffectAnalysis: false,
    needsUserConfirmation: false,
    userApproved: false,
  );

  /// Get ingredient type explanation (e.g., "Koruyucu katkı maddesi")
  String? getIngredientType() {
    return matchedIngredient?.ingredientType;
  }

  /// Get short purpose explanation (why it's used)
  String? getShortPurpose() {
    return matchedIngredient?.shortPurpose;
  }

  /// Get short risk summary (why it may be concerning)
  String? getShortRiskSummary() {
    return matchedIngredient?.shortRiskSummary;
  }

  /// Get caution groups (e.g., ["çocuklar", "alerji hastaları"])
  List<String>? getCautionGroups() {
    return matchedIngredient?.cautionGroups;
  }

  /// Get processing role (e.g., "Ultra işlenmiş ürünlerde yaygın")
  String? getProcessingRole() {
    return matchedIngredient?.processingRole;
  }

  /// Check if this ingredient has rich explanation metadata
  bool hasExplanationMetadata() {
    return matchedIngredient != null &&
        (matchedIngredient!.ingredientType != null ||
            matchedIngredient!.shortPurpose != null ||
            matchedIngredient!.shortRiskSummary != null ||
            (matchedIngredient!.cautionGroups?.isNotEmpty ?? false) ||
            matchedIngredient!.processingRole != null);
  }

  @override
  String toString() =>
      'IngredientMatch(originalToken=$originalToken, matched=${matchedIngredient?.name}, confidence=$confidenceScore, type=$matchType, shouldAffectAnalysis=$shouldAffectAnalysis)';
}

/// Container for ingredient matching results
class IngredientMatchingResult {
  final List<IngredientMatch> matches;
  final int totalIngredients;
  final int matchedCount;
  final int reviewRequiredCount;
  final int unmatchedCount;
  final double averageConfidence; // average of all match confidences

  IngredientMatchingResult({required this.matches})
    : totalIngredients = matches.length,
      matchedCount = matches.where((m) => m.shouldAffectAnalysis).length,
      reviewRequiredCount = matches
          .where((m) => m.needsUserConfirmation)
          .length,
      unmatchedCount = matches
          .where((m) => m.matchType == MatchType.unmatched)
          .length,
      averageConfidence = matches.isEmpty
          ? 0.0
          : matches.fold<double>(0, (sum, m) => sum + m.confidenceScore) /
                matches.length;

  /// Get confirmed matches only.
  List<IngredientMatch> getConfirmedMatches() =>
      matches.where((m) => m.shouldAffectAnalysis).toList();

  /// Get low-confidence matches that need the user's decision.
  List<IngredientMatch> getLowConfidenceMatches() =>
      matches.where((m) => m.needsUserConfirmation).toList();

  /// Get unmatched ingredients only
  List<IngredientMatch> getUnmatched() =>
      matches.where((m) => m.matchType == MatchType.unmatched).toList();

  /// Returns a new result with one low-confidence match updated.
  IngredientMatchingResult updateDecision(String originalToken, bool approved) {
    final updatedMatches = matches
        .map((match) {
          if (match.originalToken != originalToken) return match;
          if (!match.isLowConfidence) return match;
          return approved
              ? match.approveLowConfidence()
              : match.rejectLowConfidence();
        })
        .toList(growable: false);

    return IngredientMatchingResult(matches: updatedMatches);
  }

  /// Get match rate as percentage (0-100)
  int getMatchPercentage() {
    if (totalIngredients == 0) return 0;
    return ((matchedCount / totalIngredients) * 100).toInt();
  }

  @override
  String toString() =>
      'IngredientMatchingResult(total=$totalIngredients, matched=$matchedCount, unmatched=$unmatchedCount, avgConfidence=${averageConfidence.toStringAsFixed(2)})';
}
