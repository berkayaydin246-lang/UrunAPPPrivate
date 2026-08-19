import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/additive_quality_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/validated_nutrition_scoring_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/nutrition_raw_score_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/additive_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/etiketly_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_quality_transformer.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nutrition_raw_score_calculator.dart';
import 'package:food_analyzer_app/features/scoring/presentation/etiketly_score_presentation.dart';

class ScoreV2CalibrationFixture {
  const ScoreV2CalibrationFixture({
    required this.name,
    required this.category,
    this.energyKj = 0,
    this.totalFat = 0,
    this.saturatedFat = 0,
    this.sugars = 0,
    this.salt = 0,
    this.protein = 0,
    this.fiber = 0,
    this.fvl = 0,
    this.nnsPresent = false,
    this.plainWater = false,
    this.additives = const [],
  });

  final String name;
  final ScoringCategory category;
  final double energyKj;
  final double totalFat;
  final double saturatedFat;
  final double sugars;
  final double salt;
  final double protein;
  final double fiber;
  final double fvl;
  final bool nnsPresent;
  final bool plainWater;
  final List<ScoreV2CalibrationAdditive> additives;
}

class ScoreV2CalibrationAdditive {
  const ScoreV2CalibrationAdditive(this.eCode, this.riskLevel);

  final String eCode;
  final String riskLevel;
}

class ScoreV2CalibrationResult {
  const ScoreV2CalibrationResult({
    required this.fixture,
    required this.input,
    required this.rawResult,
    required this.additiveResult,
    required this.rawNutritionScore,
    required this.nutritionQualityV1,
    required this.nutritionQualityV2,
    required this.additiveQuality,
    required this.finalV1,
    required this.finalV2,
    required this.publicBandV1,
    required this.publicBandV2,
  });

  final ScoreV2CalibrationFixture fixture;
  final EtiketlyScoringInput input;
  final NutritionRawScoreResult rawResult;
  final AdditiveQualityResult additiveResult;
  final int? rawNutritionScore;
  final double nutritionQualityV1;
  final double nutritionQualityV2;
  final double additiveQuality;
  final double finalV1;
  final double finalV2;
  final String publicBandV1;
  final String publicBandV2;
}

const scoreV2CalibrationFixtures = <ScoreV2CalibrationFixture>[
  ScoreV2CalibrationFixture(
    name: 'A strong balanced general food',
    category: ScoringCategory.generalFood,
    energyKj: 700,
    totalFat: 5,
    saturatedFat: 1,
    sugars: 3,
    salt: 0.2,
    protein: 10,
    fiber: 8,
    fvl: 60,
    additives: [
      ScoreV2CalibrationAdditive('E202', 'low'),
      ScoreV2CalibrationAdditive('E322', 'low'),
    ],
  ),
  ScoreV2CalibrationFixture(
    name: 'B tarhana-like one major salt negative',
    category: ScoringCategory.generalFood,
    energyKj: 1493,
    totalFat: 4,
    saturatedFat: 1.3,
    sugars: 1,
    salt: 3.6,
    protein: 10,
    fiber: 9.4,
    additives: [
      ScoreV2CalibrationAdditive('E202', 'low'),
      ScoreV2CalibrationAdditive('E322', 'low'),
    ],
  ),
  ScoreV2CalibrationFixture(
    name: 'C multi-negative low-fiber food',
    category: ScoringCategory.generalFood,
    energyKj: 2100,
    totalFat: 28,
    saturatedFat: 15,
    sugars: 35,
    salt: 3,
    protein: 4,
    fiber: 1,
    additives: [
      ScoreV2CalibrationAdditive('E202', 'low'),
      ScoreV2CalibrationAdditive('E322', 'low'),
    ],
  ),
  ScoreV2CalibrationFixture(
    name: 'D high sugar only',
    category: ScoringCategory.generalFood,
    sugars: 52,
    additives: [
      ScoreV2CalibrationAdditive('E202', 'low'),
      ScoreV2CalibrationAdditive('E322', 'low'),
    ],
  ),
  ScoreV2CalibrationFixture(
    name: 'E high saturated fat only',
    category: ScoringCategory.generalFood,
    energyKj: 1000,
    totalFat: 20,
    saturatedFat: 10.1,
    additives: [
      ScoreV2CalibrationAdditive('E202', 'low'),
      ScoreV2CalibrationAdditive('E322', 'low'),
    ],
  ),
  ScoreV2CalibrationFixture(
    name: 'F genuinely poor multi-negative snack',
    category: ScoringCategory.generalFood,
    energyKj: 2300,
    totalFat: 32,
    saturatedFat: 12,
    sugars: 40,
    salt: 2,
    protein: 3,
    fiber: 1,
    additives: [
      ScoreV2CalibrationAdditive('E102', 'high'),
      ScoreV2CalibrationAdditive('E110', 'high'),
    ],
  ),
  ScoreV2CalibrationFixture(
    name: 'G high-fiber useful-protein profile',
    category: ScoringCategory.generalFood,
    energyKj: 1200,
    totalFat: 8,
    saturatedFat: 2,
    sugars: 8,
    salt: 0.8,
    protein: 13,
    fiber: 9,
    fvl: 45,
  ),
  ScoreV2CalibrationFixture(
    name: 'G comparison without fiber and protein',
    category: ScoringCategory.generalFood,
    energyKj: 1200,
    totalFat: 8,
    saturatedFat: 2,
    sugars: 8,
    salt: 0.8,
    fvl: 45,
  ),
  ScoreV2CalibrationFixture(
    name: 'H plain water',
    category: ScoringCategory.beverage,
    plainWater: true,
  ),
  ScoreV2CalibrationFixture(
    name: 'H low-negative beverage',
    category: ScoringCategory.beverage,
    energyKj: 20,
    sugars: 0.3,
    salt: 0.05,
  ),
  ScoreV2CalibrationFixture(
    name: 'H medium beverage',
    category: ScoringCategory.beverage,
    energyKj: 190,
    sugars: 6,
    salt: 0.1,
  ),
  ScoreV2CalibrationFixture(
    name: 'H poor sugary beverage',
    category: ScoringCategory.beverage,
    energyKj: 210,
    sugars: 12,
  ),
  ScoreV2CalibrationFixture(
    name: 'I unsalted nuts and seeds',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 50,
    saturatedFat: 5,
    sugars: 4,
    salt: 0.05,
    protein: 20,
    fiber: 8,
  ),
  ScoreV2CalibrationFixture(
    name: 'I high-saturated fat',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 82,
    saturatedFat: 51,
    salt: 0.1,
  ),
  ScoreV2CalibrationFixture(
    name: 'K salty canned legumes',
    category: ScoringCategory.generalFood,
    energyKj: 500,
    totalFat: 0.5,
    saturatedFat: 0.2,
    sugars: 2,
    salt: 2.2,
    protein: 8,
    fiber: 6,
    fvl: 80,
    additives: [ScoreV2CalibrationAdditive('E202', 'low')],
  ),
  ScoreV2CalibrationFixture(
    name: 'K chips',
    category: ScoringCategory.generalFood,
    energyKj: 2200,
    totalFat: 35,
    saturatedFat: 10,
    sugars: 2,
    salt: 2,
    protein: 6,
    fiber: 3.5,
    additives: [ScoreV2CalibrationAdditive('E621', 'medium')],
  ),
  ScoreV2CalibrationFixture(
    name: 'K chocolate biscuit',
    category: ScoringCategory.generalFood,
    energyKj: 2100,
    totalFat: 25,
    saturatedFat: 15,
    sugars: 35,
    salt: 0.8,
    protein: 5,
    fiber: 2,
    additives: [
      ScoreV2CalibrationAdditive('E322', 'low'),
      ScoreV2CalibrationAdditive('E471', 'low'),
    ],
  ),
  ScoreV2CalibrationFixture(
    name: 'K processed salty red meat',
    category: ScoringCategory.redMeat,
    energyKj: 1100,
    totalFat: 15,
    saturatedFat: 7,
    salt: 2,
    protein: 20,
    additives: [ScoreV2CalibrationAdditive('E102', 'high')],
  ),
  ScoreV2CalibrationFixture(
    name: 'K hard cheese',
    category: ScoringCategory.cheese,
    energyKj: 1700,
    totalFat: 30,
    saturatedFat: 20,
    salt: 1.8,
    protein: 25,
  ),
  ScoreV2CalibrationFixture(
    name: 'K butter',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 82,
    saturatedFat: 51,
    salt: 0.1,
  ),
  ScoreV2CalibrationFixture(
    name: 'K coconut oil',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 100,
    saturatedFat: 87,
  ),
  ScoreV2CalibrationFixture(
    name: 'K plain nuts',
    category: ScoringCategory.fatsOilsNutsSeeds,
    totalFat: 50,
    saturatedFat: 5,
    sugars: 4,
    protein: 20,
    fiber: 8,
  ),
  ScoreV2CalibrationFixture(
    name: 'K regular cola',
    category: ScoringCategory.beverage,
    energyKj: 180,
    sugars: 10.6,
  ),
  ScoreV2CalibrationFixture(
    name: 'K sugary fruit drink',
    category: ScoringCategory.beverage,
    energyKj: 210,
    sugars: 12,
    fvl: 20,
  ),
  ScoreV2CalibrationFixture(
    name: 'K energy drink',
    category: ScoringCategory.beverage,
    energyKj: 190,
    sugars: 11,
    nnsPresent: true,
    additives: [ScoreV2CalibrationAdditive('E202', 'low')],
  ),
];

ScoreV2CalibrationResult evaluateScoreV2Calibration(
  ScoreV2CalibrationFixture fixture,
) {
  final input = _inputFor(fixture);
  final raw = const NutritionRawScoreCalculator().calculate(
    ValidatedNutritionScoringInput.validate(input),
  );
  final v1 = const NutritionQualityTransformer.v1().transform(raw).qualityScore;
  final v2 = const NutritionQualityTransformer.v2().transform(raw).qualityScore;
  final assessment = const CanonicalIngredientRiskService().assessIngredients(
    fixture.additives.map(_ingredientFor),
    scoringCategory: fixture.category,
  );
  final additiveQuality = const AdditiveQualityTransformer().transform(
    assessment,
  );
  final finalV1 =
      v1 * EtiketlyScoreCalculator.nutritionWeight +
      additiveQuality.qualityScore * EtiketlyScoreCalculator.additiveWeight;
  final finalV2 =
      v2 * EtiketlyScoreCalculator.nutritionWeight +
      additiveQuality.qualityScore * EtiketlyScoreCalculator.additiveWeight;
  const presentation = EtiketlyScorePresentationMapper();

  String v2Band(double score) {
    final value = presentation.bandForDisplayScore(score.round());
    return presentation.labelForBand(value);
  }

  String v1Band(double score) {
    final displayScore = score.round();
    if (displayScore >= 80) return 'Çok iyi';
    if (displayScore >= 60) return 'İyi';
    if (displayScore >= 40) return 'Orta';
    if (displayScore >= 20) return 'Zayıf';
    return 'Çok zayıf';
  }

  return ScoreV2CalibrationResult(
    fixture: fixture,
    input: input,
    rawResult: raw,
    additiveResult: additiveQuality,
    rawNutritionScore: raw.rawScore,
    nutritionQualityV1: v1,
    nutritionQualityV2: v2,
    additiveQuality: additiveQuality.qualityScore,
    finalV1: finalV1,
    finalV2: finalV2,
    publicBandV1: v1Band(finalV1),
    publicBandV2: v2Band(finalV2),
  );
}

String formatScoreV2CalibrationReport(
  Iterable<ScoreV2CalibrationResult> results,
) {
  final lines = <String>[
    'fixture\tcategory\traw nutrition score\tnutritionQuality v1\t'
        'nutritionQuality v2\tadditiveQuality\tfinal v1\tfinal v2\t'
        'public band v1\tpublic band v2',
  ];
  for (final result in results) {
    lines.add(
      [
        result.fixture.name,
        result.fixture.category.name,
        result.rawNutritionScore?.toString() ?? 'plain_water',
        result.nutritionQualityV1.toStringAsFixed(3),
        result.nutritionQualityV2.toStringAsFixed(3),
        result.additiveQuality.toStringAsFixed(3),
        result.finalV1.toStringAsFixed(3),
        result.finalV2.toStringAsFixed(3),
        result.publicBandV1,
        result.publicBandV2,
      ].join('\t'),
    );
  }
  return lines.join('\n');
}

EtiketlyScoringInput _inputFor(ScoreV2CalibrationFixture fixture) {
  EvidenceValue<double> verified(double value) => EvidenceValue<double>(
    value: value,
    provenance: EvidenceProvenance.adminVerified,
    verification: EvidenceVerification.verified,
  );

  return EtiketlyScoringInput(
    nutrition: ScoringNutritionData(
      energyKj: verified(fixture.energyKj),
      totalFat: verified(fixture.totalFat),
      saturatedFat: verified(fixture.saturatedFat),
      sugars: verified(fixture.sugars),
      salt: verified(fixture.salt),
      protein: verified(fixture.protein),
      fiber: verified(fixture.fiber),
    ),
    nutritionBasis: fixture.category == ScoringCategory.beverage
        ? NutritionBasis.per100ml
        : NutritionBasis.per100g,
    productState: NutritionProductState.asSold,
    categoryEvidence: ScoringCategoryEvidence(
      resolvedCategory: fixture.category,
      source: CategoryEvidenceSource.explicitScoringMetadata,
      evidenceValues: [fixture.category.name],
      reasons: const [CategoryResolutionReason.resolvedFromExplicitMetadata],
    ),
    fvlEvidence: CompositionPercentageEvidence.known(
      fixture.fvl,
      provenance: EvidenceProvenance.adminVerified,
      verification: EvidenceVerification.verified,
    ),
    nnsEvidence: fixture.nnsPresent
        ? const PresenceEvidence.present(
            provenance: EvidenceProvenance.adminVerified,
            verification: EvidenceVerification.verified,
          )
        : const PresenceEvidence.absent(
            provenance: EvidenceProvenance.adminVerified,
            verification: EvidenceVerification.verified,
          ),
    ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.complete,
    classificationFacts: ScoringClassificationFacts(
      isPlainWater: fixture.plainWater
          ? const EvidenceValue<bool>(
              value: true,
              provenance: EvidenceProvenance.adminVerified,
              verification: EvidenceVerification.verified,
            )
          : null,
    ),
  );
}

Ingredient _ingredientFor(ScoreV2CalibrationAdditive additive) {
  return Ingredient(
    id: 'score-v2-${additive.eCode.toLowerCase()}',
    name: 'Score v2 ${additive.eCode}',
    normalizedName: 'score v2 ${additive.eCode.toLowerCase()}',
    eCode: additive.eCode,
    additiveGroup: 'calibration_fixture',
    riskLevel: additive.riskLevel,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}
