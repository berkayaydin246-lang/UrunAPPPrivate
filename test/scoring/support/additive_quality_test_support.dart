import 'package:food_analyzer_app/features/analysis/models/canonical_additive_assessment.dart';
import 'package:food_analyzer_app/features/analysis/models/ingredient_match.dart';
import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

const canonicalRiskService = CanonicalIngredientRiskService();

Ingredient reviewedIngredientForCode(
  String eCode, {
  String? id,
  String? name,
  String riskLevel = 'unknown',
  String? additiveGroup,
}) {
  return Ingredient(
    id: id ?? 'fixture-${_identifier(eCode)}',
    name: name ?? 'Fixture $eCode',
    normalizedName: (name ?? 'Fixture $eCode').toLowerCase(),
    eCode: eCode,
    additiveGroup: additiveGroup,
    riskLevel: riskLevel,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

CanonicalAdditiveAssessment assessmentForCodes(
  Iterable<String> eCodes, {
  ScoringCategory category = ScoringCategory.generalFood,
}) {
  return canonicalRiskService.assessIngredients(
    eCodes.map(reviewedIngredientForCode),
    scoringCategory: category,
  );
}

CanonicalAdditiveAssessment duplicateAssessment(String eCode) {
  final ingredient = reviewedIngredientForCode(eCode);
  return canonicalRiskService.assess(
    IngredientMatchingResult(
      matches: [
        _match(eCode, ingredient, MatchType.eCodeMatch),
        _match('canonical $eCode', ingredient, MatchType.exactMatch),
        _match('alias $eCode', ingredient, MatchType.aliasMatch),
      ],
    ),
  );
}

CanonicalAdditiveAssessment fuzzyAssessment(String eCode) {
  final ingredient = reviewedIngredientForCode(eCode);
  return canonicalRiskService.assess(
    IngredientMatchingResult(
      matches: [
        _match(
          'fuzzy $eCode',
          ingredient,
          MatchType.highConfidenceFuzzy,
          confidence: 0.9,
        ),
      ],
    ),
  );
}

CanonicalAdditiveAssessment conflictingAssessment() {
  final ingredient = reviewedIngredientForCode(
    'E321',
    name: 'BHT',
    riskLevel: 'high',
  );
  return canonicalRiskService.assessIngredients([ingredient]);
}

CanonicalAdditiveAssessment ordinaryAssessment() {
  final water = Ingredient(
    id: 'ordinary-water',
    name: 'Su',
    normalizedName: 'su',
    riskLevel: 'low',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
  return canonicalRiskService.assessIngredients([water]);
}

CanonicalAdditiveAssessment unresolvedAssessment() {
  return canonicalRiskService.assess(
    IngredientMatchingResult(
      matches: [
        IngredientMatch(
          originalToken: 'tanımsız içerik',
          normalizedText: 'tanımsız içerik',
          matchedIngredient: null,
          matchedToken: null,
          confidenceScore: 0,
          matchType: MatchType.unmatched,
          shouldAffectAnalysis: false,
          needsUserConfirmation: false,
        ),
      ],
    ),
  );
}

IngredientMatch _match(
  String token,
  Ingredient ingredient,
  MatchType matchType, {
  double confidence = 1,
}) {
  return IngredientMatch(
    originalToken: token,
    normalizedText: token.toLowerCase(),
    matchedIngredient: ingredient,
    matchedToken: ingredient.normalizedName,
    confidenceScore: confidence,
    matchType: matchType,
    shouldAffectAnalysis: true,
    needsUserConfirmation: matchType == MatchType.highConfidenceFuzzy,
  );
}

String _identifier(String value) =>
    value.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
