import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';

enum CanonicalRiskLevel { low, medium, high, unknown }

extension CanonicalRiskLevelName on CanonicalRiskLevel {
  String get name => switch (this) {
    CanonicalRiskLevel.low => 'low',
    CanonicalRiskLevel.medium => 'medium',
    CanonicalRiskLevel.high => 'high',
    CanonicalRiskLevel.unknown => 'unknown',
  };
}

enum CanonicalRiskSource {
  ingredientCatalogue,
  reviewedExplanationCatalogue,
  consistentCatalogues,
  unresolvedConflict,
  unknown,
}

enum CanonicalMatchAuthority { authoritative, reviewRequired, unresolved }

enum NutritionMethodologyOverlap { none, beverageNnsAlreadyRepresented }

enum CanonicalRiskConflictType {
  catalogueRiskMismatch,
  duplicateIdentityRiskMismatch,
}

class CanonicalMatchEvidence {
  const CanonicalMatchEvidence({
    required this.sourceToken,
    required this.normalizedToken,
    required this.matchType,
    required this.confidence,
    required this.affectsCurrentAnalysis,
    required this.needsReview,
  });

  final String sourceToken;
  final String normalizedToken;
  final MatchType matchType;
  final double confidence;
  final bool affectsCurrentAnalysis;
  final bool needsReview;
}

class CanonicalRiskConflict {
  const CanonicalRiskConflict({
    required this.canonicalKey,
    required this.type,
    required this.message,
    this.ingredientCatalogueRisk,
    this.reviewedCatalogueRisk,
  });

  final String canonicalKey;
  final CanonicalRiskConflictType type;
  final String message;
  final CanonicalRiskLevel? ingredientCatalogueRisk;
  final CanonicalRiskLevel? reviewedCatalogueRisk;
}

class CanonicalIngredientAssessment {
  CanonicalIngredientAssessment({
    required this.ingredient,
    required this.ingredientId,
    required this.canonicalKey,
    required this.canonicalName,
    required this.eCode,
    required this.additiveGroup,
    required this.isAdditive,
    required this.riskLevel,
    required this.riskSource,
    required this.matchType,
    required this.matchConfidence,
    required this.matchAuthority,
    required Iterable<CanonicalMatchEvidence> matchEvidence,
    required this.affectsCurrentAnalysis,
    required this.eligibleForFutureAdditiveScore,
    required this.nutritionMethodologyOverlap,
    required Iterable<String> warnings,
    required Iterable<CanonicalRiskConflict> conflicts,
    required this.firstOccurrenceIndex,
  }) : matchEvidence = List.unmodifiable(matchEvidence),
       warnings = List.unmodifiable(warnings),
       conflicts = List.unmodifiable(conflicts);

  final Ingredient ingredient;
  final String? ingredientId;
  final String canonicalKey;
  final String canonicalName;
  final String? eCode;
  final String? additiveGroup;
  final bool isAdditive;
  final CanonicalRiskLevel riskLevel;
  final CanonicalRiskSource riskSource;
  final MatchType matchType;
  final double matchConfidence;
  final CanonicalMatchAuthority matchAuthority;
  final List<CanonicalMatchEvidence> matchEvidence;
  final bool affectsCurrentAnalysis;
  final bool eligibleForFutureAdditiveScore;
  final NutritionMethodologyOverlap nutritionMethodologyOverlap;
  final List<String> warnings;
  final List<CanonicalRiskConflict> conflicts;
  final int firstOccurrenceIndex;

  int get occurrenceCount => matchEvidence.length;
  List<String> get sourceTokens =>
      List.unmodifiable(matchEvidence.map((evidence) => evidence.sourceToken));
  String get riskLevelName => riskLevel.name;
}

class CanonicalUnresolvedIngredient {
  CanonicalUnresolvedIngredient({
    required this.normalizedToken,
    required Iterable<String> sourceTokens,
    required this.matchType,
    required this.matchConfidence,
    this.candidateIngredientId,
    this.candidateCanonicalName,
  }) : sourceTokens = List.unmodifiable(sourceTokens);

  final String normalizedToken;
  final List<String> sourceTokens;
  final MatchType matchType;
  final double matchConfidence;
  final String? candidateIngredientId;
  final String? candidateCanonicalName;

  int get occurrenceCount => sourceTokens.length;
}

class CanonicalAdditiveAssessment {
  CanonicalAdditiveAssessment({
    required Iterable<CanonicalIngredientAssessment> recognizedIngredients,
    required Iterable<CanonicalUnresolvedIngredient> unresolvedIngredients,
    required Iterable<CanonicalRiskConflict> conflicts,
  }) : recognizedIngredients = List.unmodifiable(recognizedIngredients),
       unresolvedIngredients = List.unmodifiable(unresolvedIngredients),
       conflicts = List.unmodifiable(conflicts);

  final List<CanonicalIngredientAssessment> recognizedIngredients;
  final List<CanonicalUnresolvedIngredient> unresolvedIngredients;
  final List<CanonicalRiskConflict> conflicts;

  List<CanonicalIngredientAssessment> get canonicalAdditives =>
      List.unmodifiable(recognizedIngredients.where((item) => item.isAdditive));

  List<CanonicalIngredientAssessment> get ordinaryIngredients =>
      List.unmodifiable(
        recognizedIngredients.where((item) => !item.isAdditive),
      );

  List<CanonicalIngredientAssessment> get reviewRequired => List.unmodifiable(
    recognizedIngredients.where(
      (item) => item.matchAuthority == CanonicalMatchAuthority.reviewRequired,
    ),
  );

  int get lowRiskCount => _additiveRiskCount(CanonicalRiskLevel.low);
  int get mediumRiskCount => _additiveRiskCount(CanonicalRiskLevel.medium);
  int get highRiskCount => _additiveRiskCount(CanonicalRiskLevel.high);
  int get unknownRiskCount => _additiveRiskCount(CanonicalRiskLevel.unknown);

  int _additiveRiskCount(CanonicalRiskLevel level) =>
      canonicalAdditives.where((item) => item.riskLevel == level).length;
}
