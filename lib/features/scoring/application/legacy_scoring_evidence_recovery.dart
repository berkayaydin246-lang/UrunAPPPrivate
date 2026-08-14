import 'dart:convert';

import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/legacy_fvl_evidence_resolver.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nns_evidence_detector.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';

class LegacyStagingScoringEvidence {
  LegacyStagingScoringEvidence({
    required this.id,
    required this.sourceUrl,
    required this.nutritionBasis,
    Iterable<String> nutritionWarnings = const [],
    this.nutritionProductState,
    this.source,
    this.ingredientsSource,
    this.ingredientsRaw,
    this.ingredientsText,
    this.ingredientsQuality,
    this.nutritionSource,
    this.nutritionStrategy,
    Map<String, dynamic>? nutritionJson,
  }) : nutritionWarnings = List.unmodifiable(
         nutritionWarnings
             .map((value) => value.trim())
             .where((value) => value.isNotEmpty),
       ),
       nutritionJson = nutritionJson == null
           ? null
           : Map.unmodifiable(nutritionJson);

  final String id;
  final String sourceUrl;
  final String? nutritionBasis;
  final List<String> nutritionWarnings;
  final String? nutritionProductState;
  final String? source;
  final String? ingredientsSource;
  final String? ingredientsRaw;
  final String? ingredientsText;
  final String? ingredientsQuality;
  final String? nutritionSource;
  final String? nutritionStrategy;
  final Map<String, dynamic>? nutritionJson;

  String get evidenceSignature {
    final warnings = nutritionWarnings.toSet().toList()..sort();
    return [
      _normalized(nutritionBasis),
      _normalized(nutritionProductState),
      _normalized(source),
      _normalized(ingredientsSource),
      _normalizedText(ingredientsRaw),
      _normalizedText(ingredientsText),
      _normalized(ingredientsQuality),
      _normalized(nutritionSource),
      _normalized(nutritionStrategy),
      jsonEncode(nutritionJson ?? const <String, dynamic>{}),
      warnings.join(','),
    ].join('|');
  }

  bool hasSourceCompleteIngredients(String? productIngredientsText) {
    return _normalized(ingredientsQuality) == 'ingredients_ok' &&
        _isWebScraperSource(ingredientsSource ?? source) &&
        _normalizedText(ingredientsRaw).isNotEmpty &&
        _normalizedText(ingredientsText).isNotEmpty &&
        _normalizedText(ingredientsText) ==
            _normalizedText(productIngredientsText);
  }

  bool hasSourceVerifiedNutrition(NutritionData productNutrition) {
    final strategy = _normalized(nutritionStrategy);
    final sourceNutrition = nutritionJson == null
        ? null
        : NutritionData.fromMap(nutritionJson!);
    return _isWebScraperSource(nutritionSource ?? source) &&
        const {'dom', 'json', 'text'}.contains(strategy) &&
        sourceNutrition != null &&
        sourceNutrition.hasAnyData &&
        _sameNutrition(sourceNutrition, productNutrition);
  }

  static String _normalized(String? value) => value?.trim().toLowerCase() ?? '';

  static String _normalizedText(String? value) =>
      _normalized(value).replaceAll(RegExp(r'\s+'), ' ');

  static bool _isWebScraperSource(String? value) =>
      _normalized(value).startsWith('web_scraper:');

  static bool _sameNutrition(NutritionData left, NutritionData right) {
    return left.energyKj == right.energyKj &&
        left.energyKcal == right.energyKcal &&
        left.fat == right.fat &&
        left.saturatedFat == right.saturatedFat &&
        left.carbohydrates == right.carbohydrates &&
        left.sugars == right.sugars &&
        left.fiber == right.fiber &&
        left.proteins == right.proteins &&
        left.salt == right.salt &&
        left.sodium == right.sodium;
  }
}

class LegacyScoringEvidenceRecoveryResult {
  const LegacyScoringEvidenceRecoveryResult({
    required this.stagingMatch,
    required this.explicitPer100,
    required this.basisReady,
    required this.nutritionComplete,
    required this.classificationReady,
    required this.fvlReady,
    required this.nnsReady,
    required this.additiveReady,
    required this.finalScoreReady,
    required this.blockerReasons,
    this.evidence,
    this.selectedStagingId,
  });

  final bool stagingMatch;
  final bool explicitPer100;
  final bool basisReady;
  final bool nutritionComplete;
  final bool classificationReady;
  final bool fvlReady;
  final bool nnsReady;
  final bool additiveReady;
  final bool finalScoreReady;
  final List<String> blockerReasons;
  final ScoringEvidenceSnapshot? evidence;
  final String? selectedStagingId;

  bool get canWrite => evidence != null;
}

/// Conservatively reconstructs only source-backed legacy scoring evidence.
class LegacyScoringEvidenceRecoveryService {
  const LegacyScoringEvidenceRecoveryService({
    this.categoryResolver = const ScoringCategoryResolver(),
    this.nnsDetector = const NnsEvidenceDetector(),
    this.fvlResolver = const LegacyFvlEvidenceResolver(),
    this.matcher = const IngredientMatcherService(),
    this.riskService = const CanonicalIngredientRiskService(),
    this.orchestrator = const ProductEtiketlyScoreOrchestrator(),
  });

  static const _assumedPer100Warning =
      'nutrition_basis_unknown_assumed_per_100';

  final ScoringCategoryResolver categoryResolver;
  final NnsEvidenceDetector nnsDetector;
  final LegacyFvlEvidenceResolver fvlResolver;
  final IngredientMatcherService matcher;
  final CanonicalIngredientRiskService riskService;
  final ProductEtiketlyScoreOrchestrator orchestrator;

  Future<LegacyScoringEvidenceRecoveryResult> recover({
    required Product product,
    required List<LegacyStagingScoringEvidence> stagingMatches,
    required List<Ingredient> ingredientCatalogue,
  }) async {
    if (stagingMatches.isEmpty) {
      return _blocked('missing_staging_match');
    }
    final signatures = stagingMatches
        .map((match) => match.evidenceSignature)
        .toSet();
    if (signatures.length != 1) {
      return _blocked('ambiguous_staging_match', stagingMatch: true);
    }
    final matches = [...stagingMatches]
      ..sort((left, right) => left.id.compareTo(right.id));
    final staging = matches.first;
    final basis = staging.nutritionBasis?.trim().toLowerCase();
    final warnings = staging.nutritionWarnings
        .map((value) => value.trim().toLowerCase())
        .toSet();
    if (warnings.contains(_assumedPer100Warning)) {
      return _blocked(
        'basis_unknown_assumed_per100',
        stagingMatch: true,
        selectedStagingId: staging.id,
      );
    }
    if (basis == null || basis.isEmpty || basis == 'unknown') {
      return _blocked(
        'basis_unknown',
        stagingMatch: true,
        selectedStagingId: staging.id,
      );
    }
    if (basis == 'per_serving') {
      return _blocked(
        'basis_per_serving',
        stagingMatch: true,
        selectedStagingId: staging.id,
      );
    }
    if (basis != 'per_100') {
      return _blocked(
        'basis_unsupported',
        stagingMatch: true,
        selectedStagingId: staging.id,
      );
    }

    final nutrition = product.nutrition;
    if (nutrition == null || !nutrition.hasAnyData) {
      return _blocked(
        'missing_nutrition',
        stagingMatch: true,
        explicitPer100: true,
        selectedStagingId: staging.id,
      );
    }

    const facts = ScoringClassificationFacts();
    final categoryEvidence = categoryResolver.resolve(
      ScoringCategoryResolverInput(
        categoryTags: product.categoryTags ?? const [],
        canonicalCategory: product.canonicalCategory,
        canonicalSubcategory: product.canonicalSubcategory,
        taxonomyProvenance: EvidenceProvenance.databaseImport,
        taxonomyVerification: EvidenceVerification.unverified,
        facts: facts,
        allowLegacyCompatibility: true,
      ),
    );
    final resolvedCategory = categoryEvidence.resolvedCategory;
    final classificationReady =
        resolvedCategory != ScoringCategory.unknown &&
        resolvedCategory != ScoringCategory.outOfScope &&
        categoryEvidence.isSufficient;
    final recoveredBasis = _basisForCategory(resolvedCategory);
    final retainedProductState = _productState(staging.nutritionProductState);
    final productState = retainedProductState != NutritionProductState.unknown
        ? retainedProductState
        : classificationReady
        ? NutritionProductState.asSold
        : NutritionProductState.unknown;
    final sourceVerifiedNutrition = staging.hasSourceVerifiedNutrition(
      nutrition,
    );
    final scoringNutrition = _nutrition(
      nutrition,
      sourceVerified: sourceVerifiedNutrition,
    );
    final ingredientsComplete = staging.hasSourceCompleteIngredients(
      product.ingredientsText,
    );
    final fvl = fvlResolver.resolve(
      ingredientsText: product.ingredientsText,
      sourceComplete: ingredientsComplete,
      category: resolvedCategory,
    );
    final nns = nnsDetector.detect(product.ingredientsText);
    final nnsEvidence = nns.hasQualifyingMatch
        ? PresenceEvidence.present(
            provenance: EvidenceProvenance.databaseImport,
            verification: ingredientsComplete
                ? EvidenceVerification.verified
                : EvidenceVerification.unverified,
          )
        : ingredientsComplete
        ? const PresenceEvidence.absent(
            provenance: EvidenceProvenance.databaseImport,
            verification: EvidenceVerification.verified,
          )
        : const PresenceEvidence.unknown();

    final evidence = ScoringEvidenceSnapshot(
      nutritionBasis: recoveredBasis,
      nutritionProductState: productState,
      nutritionBasisEvidence: recoveredBasis == NutritionBasis.unknown
          ? null
          : EvidenceValue<NutritionBasis>(
              value: recoveredBasis,
              provenance: EvidenceProvenance.databaseImport,
              verification: EvidenceVerification.verified,
            ),
      nutritionProductStateEvidence:
          productState == NutritionProductState.unknown
          ? null
          : EvidenceValue<NutritionProductState>(
              value: productState,
              provenance: EvidenceProvenance.databaseImport,
              verification: EvidenceVerification.verified,
            ),
      nutrition: scoringNutrition,
      fvlEvidence: fvl.evidence,
      nnsEvidence: nnsEvidence,
      ingredientEvidenceCompleteness: ingredientsComplete
          ? IngredientEvidenceCompleteness.complete
          : IngredientEvidenceCompleteness.unknown,
      categoryEvidence: categoryEvidence,
      classificationFacts: facts,
    );

    final blockers = <String>{};
    if (!classificationReady) blockers.add('missing_classification');
    if (recoveredBasis == NutritionBasis.unknown) {
      blockers.add('basis_unit_ambiguous');
    }
    if (productState == NutritionProductState.unknown) {
      blockers.add('product_state_unknown');
    }
    _addMissingNutritionBlockers(nutrition, blockers);
    if (!sourceVerifiedNutrition) {
      blockers.add('nutrition_source_unverified');
    }
    if (!fvl.isReady) blockers.add('fvl_unknown');
    if (resolvedCategory == ScoringCategory.beverage && !nnsEvidence.isKnown) {
      blockers.add('nns_unknown');
    }
    if (!ingredientsComplete) blockers.add('ingredients_incomplete');

    final temporaryProduct = _withEvidence(product, evidence);
    final tokens = matcher.parseIngredients(product.ingredientsText ?? '');
    if (tokens.isEmpty) blockers.add('missing_ingredients');
    final matching = await matcher.matchIngredientTokens(
      tokens,
      ingredientCatalogue,
    );
    final assessment = riskService.assessForScoring(
      matching,
      scoringCategory: resolvedCategory,
    );
    final evaluation = orchestrator.calculate(
      product: temporaryProduct,
      canonicalAssessment: assessment,
    );
    if (evaluation == null) {
      blockers.add('canonical_additive_unavailable');
    } else {
      _addReadinessBlockers(
        evaluation.finalReadiness.blockingReasons,
        blockers,
      );
    }
    final additiveReady =
        evaluation != null &&
        evaluation.finalReadiness.blockingReasons
            .where(
              (reason) =>
                  reason != EtiketlyScoreReadinessBlocker.nutritionNotReady,
            )
            .isEmpty;

    return LegacyScoringEvidenceRecoveryResult(
      stagingMatch: true,
      explicitPer100: true,
      basisReady: recoveredBasis != NutritionBasis.unknown,
      nutritionComplete: _nutritionComplete(nutrition),
      classificationReady: classificationReady,
      fvlReady: fvl.isReady,
      nnsReady:
          resolvedCategory != ScoringCategory.beverage || nnsEvidence.isKnown,
      additiveReady: additiveReady,
      finalScoreReady: evaluation?.isCalculated ?? false,
      blockerReasons: (blockers.toList()..sort()),
      evidence: evidence,
      selectedStagingId: staging.id,
    );
  }

  LegacyScoringEvidenceRecoveryResult _blocked(
    String reason, {
    bool stagingMatch = false,
    bool explicitPer100 = false,
    String? selectedStagingId,
  }) {
    return LegacyScoringEvidenceRecoveryResult(
      stagingMatch: stagingMatch,
      explicitPer100: explicitPer100,
      basisReady: false,
      nutritionComplete: false,
      classificationReady: false,
      fvlReady: false,
      nnsReady: false,
      additiveReady: false,
      finalScoreReady: false,
      blockerReasons: [reason],
      selectedStagingId: selectedStagingId,
    );
  }

  NutritionBasis _basisForCategory(ScoringCategory category) {
    return switch (category) {
      ScoringCategory.beverage => NutritionBasis.per100ml,
      ScoringCategory.generalFood ||
      ScoringCategory.cheese ||
      ScoringCategory.redMeat ||
      ScoringCategory.fatsOilsNutsSeeds => NutritionBasis.per100g,
      ScoringCategory.unknown ||
      ScoringCategory.outOfScope => NutritionBasis.unknown,
    };
  }

  NutritionProductState _productState(String? value) {
    return switch (value?.trim().toLowerCase()) {
      'assold' || 'as_sold' => NutritionProductState.asSold,
      'asprepared' || 'as_prepared' => NutritionProductState.asPrepared,
      _ => NutritionProductState.unknown,
    };
  }

  ScoringNutritionData _nutrition(
    NutritionData value, {
    required bool sourceVerified,
  }) {
    EvidenceValue<double> imported(double? raw) => raw == null
        ? const EvidenceValue<double>.unknown()
        : EvidenceValue<double>(
            value: raw,
            provenance: sourceVerified
                ? EvidenceProvenance.declaredLabel
                : EvidenceProvenance.databaseImport,
            verification: sourceVerified
                ? EvidenceVerification.verified
                : EvidenceVerification.unverified,
          );
    return ScoringNutritionData(
      energyKj: imported(value.energyKj),
      energyKcal: imported(value.energyKcal),
      totalFat: imported(value.fat),
      saturatedFat: imported(value.saturatedFat),
      sugars: imported(value.sugars),
      protein: imported(value.proteins),
      fiber: imported(value.fiber),
      salt: imported(value.salt),
      sodium: imported(value.sodium),
    );
  }

  void _addMissingNutritionBlockers(
    NutritionData nutrition,
    Set<String> blockers,
  ) {
    if (nutrition.energyKj == null) blockers.add('missing_energy_kj');
    if (nutrition.fat == null) blockers.add('missing_total_fat');
    if (nutrition.saturatedFat == null) blockers.add('missing_saturated_fat');
    if (nutrition.sugars == null) blockers.add('missing_sugars');
    if (nutrition.fiber == null) blockers.add('missing_fiber');
    if (nutrition.proteins == null) blockers.add('missing_protein');
    if (nutrition.salt == null) blockers.add('missing_salt');
  }

  bool _nutritionComplete(NutritionData nutrition) {
    return nutrition.energyKj != null &&
        nutrition.fat != null &&
        nutrition.saturatedFat != null &&
        nutrition.sugars != null &&
        nutrition.fiber != null &&
        nutrition.proteins != null &&
        nutrition.salt != null;
  }

  void _addReadinessBlockers(
    Set<EtiketlyScoreReadinessBlocker> reasons,
    Set<String> blockers,
  ) {
    for (final reason in reasons) {
      switch (reason) {
        case EtiketlyScoreReadinessBlocker.nutritionNotReady:
          break;
        case EtiketlyScoreReadinessBlocker.ingredientEvidenceIncomplete:
          blockers.add('ingredients_incomplete');
        case EtiketlyScoreReadinessBlocker.unresolvedIngredientEvidence:
          blockers.add('canonical_additive_unresolved');
        case EtiketlyScoreReadinessBlocker.reviewRequiredAdditiveEvidence:
          blockers.add('canonical_additive_review_required');
        case EtiketlyScoreReadinessBlocker.additiveRiskConflict:
          blockers.add('canonical_additive_risk_conflict');
        case EtiketlyScoreReadinessBlocker.unknownAdditiveRisk:
          blockers.add('canonical_additive_unknown_risk');
        case EtiketlyScoreReadinessBlocker.additiveAssessmentIncomplete:
          blockers.add('canonical_additive_incomplete');
      }
    }
  }

  Product _withEvidence(Product product, ScoringEvidenceSnapshot evidence) {
    return Product(
      id: product.id,
      barcode: product.barcode,
      name: product.name,
      normalizedName: product.normalizedName,
      brand: product.brand,
      categoryId: product.categoryId,
      imageUrl: product.imageUrl,
      ingredientsText: product.ingredientsText,
      nutritionText: product.nutritionText,
      source: product.source,
      sourceUrl: product.sourceUrl,
      verificationStatus: product.verificationStatus,
      searchKeywords: product.searchKeywords,
      categoryTags: product.categoryTags,
      canonicalCategory: product.canonicalCategory,
      canonicalSubcategory: product.canonicalSubcategory,
      scoringEvidence: evidence,
      createdAt: product.createdAt,
      updatedAt: product.updatedAt,
    );
  }
}
