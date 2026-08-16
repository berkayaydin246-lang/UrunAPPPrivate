import 'dart:convert';

import 'package:food_analyzer_app/features/analysis/services/canonical_ingredient_risk_service.dart';
import 'package:food_analyzer_app/features/analysis/services/ingredient_matcher_service.dart';
import 'package:food_analyzer_app/features/product/models/ingredient.dart';
import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/application/product_etiketly_score_orchestrator.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/etiketly_score_readiness_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/evidence_value.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/composition_percentage_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/presence_evidence.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_category_resolver_input.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_classification_facts.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_evidence_snapshot.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/legacy_fvl_evidence_resolver.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/nns_evidence_detector.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_category_resolver.dart';

/// Reserved sentinel returned by [resolveEffectiveIngredientsQuality] when
/// the two known trusted locations for the scraper's ingredient-quality
/// classification are both present but disagree. Never a value the scraper
/// itself produces (see [_scraperQualityStates]), so it always fails
/// [LegacyStagingScoringEvidence.hasSourceCompleteIngredients]'s
/// `== 'ingredients_ok'` check closed without any change to that method —
/// while still being distinguishable in `blockerReasons` (see
/// `_recover`'s `ingredients_quality_provenance_conflict` blocker).
const ingredientsQualityProvenanceConflict =
    'ingredients_quality_provenance_conflict';

/// Every quality state the scraper contract has ever been observed to
/// produce (scripts/product_import/web_scraper/ingredient_parser.py's
/// INGREDIENT_QUALITY_* constants). Only these exact strings are ever
/// trusted as a real quality judgment — anything else is treated as absent,
/// never guessed or aliased.
const _scraperQualityStates = {
  'ingredients_ok',
  'ingredients_suspicious',
  'ingredients_rejected_as_junk',
  'ingredients_missing',
};

/// Version tag for [recomputeIngredientsQualityFromRetainedSource]. Bump
/// this only if the ported heuristic itself changes — it exists so a
/// recomputed "OK" is always distinguishable in provenance/diagnostics from
/// a value the scraper declared directly at ingestion time, even though
/// both are treated identically by
/// [LegacyStagingScoringEvidence.hasSourceCompleteIngredients].
const recomputedIngredientsQualityOkV1 =
    'ingredients_ok_recomputed_from_raw_source_v1';

/// Resolves the effective ingredient-quality classification for a staging
/// row, in two tiers:
///
/// TIER 1 — direct, trusted scraper-declared value. Checks every
/// historically-confirmed location the scraper contract has actually
/// written it to:
///   1. `payload['ingredients_quality']` — the current top-level location
///      (scripts/product_import/web_scraper/runner.py's candidate
///      `raw_source_payload` dict).
///   2. `payload['debug']['ingredient_quality']` — a nested legacy
///      location, confirmed present in real historical rows (verified
///      against saved production probe output) that have NO top-level key
///      at all — that scraper contract wrote the classification only here,
///      it was never merely "not captured".
/// A missing top-level field is therefore not, by itself, proof the
/// judgment was never made. If both locations are present and agree, that
/// value is used. If both are present and disagree, this is a genuine
/// provenance conflict — never resolved to either value — see
/// [ingredientsQualityProvenanceConflict]. Only the exact, known
/// scraper-produced states in [_scraperQualityStates] are ever trusted; any
/// other string is treated as absent, never aliased.
///
/// TIER 2 — only when tier 1 finds nothing at all (neither location has any
/// trusted value — NOT the conflict case, which is already a definite,
/// distinct result): deterministic recomputation from retained source, see
/// [recomputeIngredientsQualityFromRetainedSource].
String? resolveEffectiveIngredientsQuality(
  Map<String, dynamic>? payload, {
  String? ingredientsRaw,
  String? ingredientsText,
}) {
  final direct = _resolveDirectIngredientsQuality(payload);
  if (direct != null) return direct;
  return recomputeIngredientsQualityFromRetainedSource(
    ingredientsRaw: ingredientsRaw,
    ingredientsText: ingredientsText,
  );
}

String? _resolveDirectIngredientsQuality(Map<String, dynamic>? payload) {
  if (payload == null) return null;
  final topLevel = _trustedQualityState(payload['ingredients_quality']);
  final debugValue = payload['debug'];
  final nested = debugValue is Map
      ? _trustedQualityState(debugValue['ingredient_quality'])
      : null;
  if (topLevel != null && nested != null) {
    return topLevel == nested ? topLevel : ingredientsQualityProvenanceConflict;
  }
  return topLevel ?? nested;
}

String? _trustedQualityState(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return _scraperQualityStates.contains(trimmed) ? trimmed : null;
}

/// Deterministic last-resort recomputation, used ONLY when no trusted
/// scraper-declared quality value exists anywhere. This is NOT a guess and
/// NOT a re-derivation of ingredient-section boundaries from raw HTML —
/// that extraction already happened once, deterministically, at scrape
/// time (`clean_ingredients()` in ingredient_parser.py), and its result is
/// retained verbatim as [ingredientsText]. This function is a direct,
/// line-for-line Dart port of that SAME file's `is_junk()`/`is_suspicious()`
/// classifiers (see [_looksJunk]/[_looksSuspicious]), applied to the
/// already-extracted text — the identical judgment the scraper itself would
/// have made, just never persisted for these specific historical rows.
///
/// Requires BOTH [ingredientsRaw] (proof the original source text was
/// actually retained, not merely a downstream derived value) AND
/// [ingredientsText] (the extracted result) to be non-empty — a missing
/// raw source cannot be recomputed from, it can only stay unknown.
///
/// Source-neutral: operates purely on retained text fields present on
/// every [LegacyStagingScoringEvidence] regardless of which retailer
/// adapter produced them — never Migros-specific.
String? recomputeIngredientsQualityFromRetainedSource({
  required String? ingredientsRaw,
  required String? ingredientsText,
}) {
  final raw = ingredientsRaw?.trim() ?? '';
  final text = ingredientsText?.trim() ?? '';
  if (raw.isEmpty || text.isEmpty) return null;
  if (_looksJunk(text)) return 'ingredients_rejected_as_junk';
  if (_looksSuspicious(text)) return 'ingredients_suspicious';
  return recomputedIngredientsQualityOkV1;
}

// Direct port of ingredient_parser.py's _JUNK_PHRASES — phrases that
// unambiguously indicate non-ingredient UI/policy content. Keep in sync
// with that file; do not add or remove entries independently.
const _junkPhrases = [
  'iade koşulları',
  'iade kosullari',
  'iade sürecini',
  'iade surecini',
  'iade/değişim',
  'iade/degisim',
  'değişim kapsamı',
  'degisim kapsami',
  'nasıl başlatabilirim',
  'nasil baslatabilirim',
  'ücretsiz iade',
  'ucretsiz iade',
  'sepete ekle',
  'sipariş ver',
  'siparis ver',
  'teslimat süresi',
  'teslimat ucreti',
  'teslimat ücreti',
  'kargo bedeli',
  'kargo ücreti',
  'sarf malzeme',
  'kapsamında değerlendiri',
  'kapsami degerlendiri',
  'javascript',
  'cookie',
  'çerez politik',
  'cerez politik',
];

// Port of ingredient_parser.py's _junk_fold(): Python's str.lower() maps
// İ (U+0130) to i+combining-dot, breaking plain-'i' substring matches.
// Dart's toLowerCase() does not have this specific issue, but the same
// explicit replacement is applied first for exact parity with the source
// classifier's matching behavior.
String _foldTurkish(String value) =>
    value.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

bool _looksJunk(String text) {
  if (text.isEmpty) return false;
  final folded = _foldTurkish(text);
  return _junkPhrases.any(folded.contains);
}

// Direct port of ingredient_parser.py's is_suspicious().
bool _looksSuspicious(String text) {
  if (text.length < 20) return true;
  final folded = text.toLowerCase();
  if (folded.startsWith('net miktar')) return true;
  if (folded.contains('besin değer') || folded.contains('besin deger')) {
    return true;
  }
  if (['javascript', 'cookie', 'çerez politik'].any(folded.contains)) {
    return true;
  }
  final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  if (!text.contains(',') && !text.contains(';') && tokens.length < 5) {
    return true;
  }
  return false;
}

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
    final quality = _normalized(ingredientsQuality);
    return (quality == 'ingredients_ok' ||
            quality == recomputedIngredientsQualityOkV1) &&
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
    this.notScoreEligible = false,
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
  // True only when the category resolver independently determined
  // ScoringCategory.outOfScope from a trusted classification fact (food
  // supplement / infant food / medical food / sports nutrition / meal
  // replacement — see ScoringClassificationFacts.hasTrustedOutOfScopeFact).
  // This is NOT a scoring failure and must never be mixed into
  // blockerReasons/finalScoreReady's ordinary blocked semantics — a
  // not-score-eligible product has no numeric score by design, not because
  // evidence is missing. See LegacyScoringRecoveryOutcome.notScoreEligible.
  final bool notScoreEligible;
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

  // Every staging nutrition_basis string this recovery path proceeds past
  // the initial basis gate for. `per_100` is the historical, pre-fix
  // Migros value — retained for backward compatibility with rows the
  // scraper already wrote before the Section B contract fix, understood as
  // GENERIC per-100 evidence (never malformed, never discarded), but it
  // still cannot satisfy exact basis readiness. `per_100_generic` is the
  // same concept from the corrected scraper contract, produced when the
  // source genuinely names both units without identifying which values
  // belong to which (e.g. "100 g / ml") — see nutrition_parser.py's
  // detect_basis(). `per_100g`/`per_100ml` are the only two values that
  // can ever satisfy exact basis readiness.
  static const _supportedBasisStrings = {
    'per_100',
    'per_100_generic',
    'per_100g',
    'per_100ml',
  };

  // Basis strings that prove a 100-unit declaration exists but NOT which
  // unit — genuinely ambiguous, as opposed to no basis signal at all
  // (basis_unknown, checked earlier). Tracked as its own set (rather than
  // folded into a single `_supportedBasisStrings` membership test) so the
  // historical revalidation planner (Section J) can distinguish "this
  // product is blocked ONLY on the exact unit, everything else is ready"
  // from every other kind of blocker.
  static const _genericAmbiguousBasisStrings = {'per_100', 'per_100_generic'};

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
  }) {
    return _recover(
      product: product,
      stagingMatches: stagingMatches,
      ingredientCatalogue: ingredientCatalogue,
      evaluateScoreReadiness: true,
    );
  }

  /// Recovers trusted evidence without running the score calculation.
  ///
  /// Production ingestion uses this method and delegates the only readiness,
  /// canonical additive, score, and fingerprint calculation to the lifecycle's
  /// [ProductScoreAuditEvaluator]. Backfill diagnostics retain [recover].
  Future<LegacyScoringEvidenceRecoveryResult> recoverEvidence({
    required Product product,
    required List<LegacyStagingScoringEvidence> stagingMatches,
    required List<Ingredient> ingredientCatalogue,
  }) {
    return _recover(
      product: product,
      stagingMatches: stagingMatches,
      ingredientCatalogue: ingredientCatalogue,
      evaluateScoreReadiness: false,
    );
  }

  Future<LegacyScoringEvidenceRecoveryResult> _recover({
    required Product product,
    required List<LegacyStagingScoringEvidence> stagingMatches,
    required List<Ingredient> ingredientCatalogue,
    required bool evaluateScoreReadiness,
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
    if (!_supportedBasisStrings.contains(basis)) {
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
    // notScoreEligible is its own outcome, never a blocker: it means the
    // product was determined out of the scoring perimeter entirely (via a
    // trusted classification fact), not that evidence is missing/invalid.
    final notScoreEligible = resolvedCategory == ScoringCategory.outOfScope;
    if (notScoreEligible) {
      // Short-circuit before any nutrition/FVL/ingredient evaluation: none
      // of those checks are meaningful for a product that is out of the
      // scoring perimeter entirely, and running them would populate
      // blockerReasons with noise that misrepresents a non-failure as a
      // list of blockers.
      return LegacyScoringEvidenceRecoveryResult(
        stagingMatch: true,
        explicitPer100: true,
        basisReady: false,
        nutritionComplete: false,
        classificationReady: false,
        fvlReady: false,
        nnsReady: false,
        additiveReady: false,
        finalScoreReady: false,
        notScoreEligible: true,
        blockerReasons: const [],
        evidence: ScoringEvidenceSnapshot(
          nutritionBasis: NutritionBasis.unknown,
          nutritionProductState: NutritionProductState.unknown,
          nutrition: const ScoringNutritionData(),
          fvlEvidence: const CompositionPercentageEvidence.unknown(),
          nnsEvidence: const PresenceEvidence.unknown(),
          ingredientEvidenceCompleteness: IngredientEvidenceCompleteness.unknown,
          categoryEvidence: categoryEvidence,
          classificationFacts: facts,
        ),
        selectedStagingId: staging.id,
      );
    }
    final classificationReady =
        resolvedCategory != ScoringCategory.unknown &&
        resolvedCategory != ScoringCategory.outOfScope &&
        categoryEvidence.isSufficient;
    final recoveredBasis = _recoveredBasisFromEvidence(basis);
    // Whether a product is sold ready-to-consume ("as sold") versus needing
    // preparation is a fact about the product itself — it does not depend on
    // which of the five scoring categories the product resolves into. Gating
    // this default on classificationReady made product_state_unknown fire as
    // a pure downstream artifact of missing_classification even when staging
    // said nothing about product state either way, double-counting one root
    // cause as two separate-looking blockers.
    final retainedProductState = _productState(staging.nutritionProductState);
    final productState = retainedProductState != NutritionProductState.unknown
        ? retainedProductState
        : NutritionProductState.asSold;
    final sourceVerifiedNutrition = staging.hasSourceVerifiedNutrition(
      nutrition,
    );
    // hasSourceVerifiedNutrition requires an exact match on every field, so
    // a product missing just one field (e.g. fiber) never benefits from an
    // otherwise-identical, genuinely present staging value for that field —
    // it stays blocked even though the trusted source data is right there.
    // Only ever fills fields the product itself is missing; never overrides
    // a field the product already has, and never borrows anything if any
    // field present on both sides disagrees (a real conflict, not a gap).
    final stagingNutrition = staging.nutritionJson == null
        ? null
        : NutritionData.fromMap(staging.nutritionJson!);
    final stagingFallback =
        stagingNutrition != null &&
            stagingNutrition.hasAnyData &&
            LegacyStagingScoringEvidence._isWebScraperSource(
              staging.nutritionSource ?? staging.source,
            ) &&
            _fieldsAgreeWhereBothPresent(nutrition, stagingNutrition)
        ? stagingNutrition
        : null;
    final scoringNutrition = _nutrition(
      nutrition,
      sourceVerified: sourceVerifiedNutrition,
      stagingFallback: stagingFallback,
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
      // Section E of the basis remediation pass: `declaredLabel`, never
      // `databaseImport`, is deliberate and load-bearing. This branch is
      // now ONLY ever reached when `recoveredBasis` came from an exact,
      // genuinely-proven `per_100g`/`per_100ml` staging string (see
      // _recoveredBasisFromEvidence — every generic/ambiguous case already
      // resolves to `unknown` above and never reaches here). Tagging it
      // `declaredLabel` — "the source declared this exact unit" — makes it
      // retroactively distinguishable from every historical evidence
      // object written by the OLD, pre-fix `_basisForCategory` bug, which
      // always used `databaseImport` for this same field regardless of
      // whether the unit was actually proven. See
      // EtiketlyPublicScoreAuditGate / historical basis trust check: a
      // current snapshot's basis provenance must be `declaredLabel` or
      // `adminVerified` — `databaseImport` basis provenance is exactly the
      // legacy-invented signature and is never trusted as current again.
      nutritionBasisEvidence: recoveredBasis == NutritionBasis.unknown
          ? null
          : EvidenceValue<NutritionBasis>(
              value: recoveredBasis,
              provenance: EvidenceProvenance.declaredLabel,
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
    // notScoreEligible is reported as its own field/outcome, never folded
    // into 'missing_classification' — that string means the category is
    // genuinely unresolved/insufficient, a different situation from a
    // product that was determined out of scope entirely.
    if (!notScoreEligible && !classificationReady) {
      blockers.add('missing_classification');
    }
    if (recoveredBasis == NutritionBasis.unknown) {
      blockers.add('basis_unit_ambiguous');
      // Distinct signal for the historical revalidation planner (Section
      // J): a product blocked ONLY because the exact g/ml unit was never
      // proven, as opposed to no per-100 signal existing at all. Both
      // still block identically today — this is purely diagnostic, never
      // relaxes readiness.
      if (_genericAmbiguousBasisStrings.contains(basis)) {
        blockers.add('basis_generic_ambiguous_exact_unit_unproven');
      }
    }
    if (productState == NutritionProductState.unknown) {
      blockers.add('product_state_unknown');
    }
    _addMissingNutritionBlockers(scoringNutrition, blockers);
    if (!sourceVerifiedNutrition) {
      blockers.add('nutrition_source_unverified');
    }
    if (!fvl.isReady) blockers.add('fvl_unknown');
    if (resolvedCategory == ScoringCategory.beverage && !nnsEvidence.isKnown) {
      blockers.add('nns_unknown');
    }
    if (!ingredientsComplete) blockers.add('ingredients_incomplete');
    // Distinct, deterministic signal for the genuine provenance-conflict
    // case (see resolveEffectiveIngredientsQuality) — never silently
    // absorbed into the generic ingredients_incomplete reason, so it can be
    // operationally triaged differently: this needs a human to look at why
    // the two trusted quality locations disagree, not just "no evidence".
    if (staging.ingredientsQuality == ingredientsQualityProvenanceConflict) {
      blockers.add('ingredients_quality_provenance_conflict');
    }

    if (!evaluateScoreReadiness) {
      return LegacyScoringEvidenceRecoveryResult(
        stagingMatch: true,
        explicitPer100: true,
        basisReady: recoveredBasis != NutritionBasis.unknown,
        nutritionComplete: _nutritionComplete(scoringNutrition),
        classificationReady: classificationReady,
        fvlReady: fvl.isReady,
        nnsReady:
            resolvedCategory != ScoringCategory.beverage || nnsEvidence.isKnown,
        additiveReady: false,
        finalScoreReady: false,
        blockerReasons: (blockers.toList()..sort()),
        evidence: evidence,
        selectedStagingId: staging.id,
      );
    }

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
      // EtiketlyScoreReadinessBlocker.nutritionNotReady collapses every
      // nutrition-level reason into one generic case in
      // _addReadinessBlockers (see below), so the specific cross-field
      // invariant that actually blocked the product would otherwise be
      // silently dropped from this diagnostic's reported blockers.
      _addCrossFieldNutritionBlockers(
        evaluation.nutritionReadiness.blockingReasons,
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
      nutritionComplete: _nutritionComplete(scoringNutrition),
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

  /// Resolves the nutrition basis from the staging row's OWN evidence only
  /// — scoring category must never manufacture this. [normalizedBasis] is
  /// already guaranteed non-null/non-empty at every call site (the caller's
  /// earlier gate blocks `basis_unknown`/`basis_per_serving`/
  /// `basis_unsupported` before this ever runs).
  ///
  /// Pre-remediation (Section B) historical Migros rows only ever have the
  /// generic `per_100` — the OLD `nutrition_parser.py.detect_basis()`
  /// collapsed "100 g" and "100 ml" hints into that SAME string, and the
  /// disambiguating raw text was never retained anywhere, confirmed by
  /// exhaustive code search. The CORRECTED scraper contract still produces
  /// a comparable, deliberately generic value — `per_100_generic` — for
  /// sources that genuinely name both units without saying which values
  /// belong to which (e.g. "100 g / ml"). Both `per_100` and
  /// `per_100_generic` prove only "a 100-unit basis was declared", never
  /// which unit — they must resolve to [NutritionBasis.unknown] (fail
  /// closed), never paired with whatever unit the category happens to
  /// expect. `per_100` is kept recognized (not "unsupported") purely for
  /// backward compatibility with rows already written before this fix —
  /// it is understood as generic evidence, never treated as malformed.
  ///
  /// Forward-compatible, source-neutral: any adapter (see
  /// LegacyScoringRecoveryLifecycleRunner's source-neutral tests) that DOES
  /// retain the distinct unit reports it as `per_100g`/`per_100ml`
  /// directly — those exact strings are trusted immediately, no category
  /// involved. Never guessed, never aliased from any other string.
  NutritionBasis _recoveredBasisFromEvidence(String? normalizedBasis) {
    return switch (normalizedBasis) {
      'per_100g' => NutritionBasis.per100g,
      'per_100ml' => NutritionBasis.per100ml,
      _ => NutritionBasis.unknown,
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
    NutritionData? stagingFallback,
  }) {
    EvidenceValue<double> imported(double? Function(NutritionData) select) {
      final raw = select(value);
      if (raw != null) {
        return EvidenceValue<double>(
          value: raw,
          provenance: sourceVerified
              ? EvidenceProvenance.declaredLabel
              : EvidenceProvenance.databaseImport,
          verification: sourceVerified
              ? EvidenceVerification.verified
              : EvidenceVerification.unverified,
        );
      }
      final recovered = stagingFallback == null
          ? null
          : select(stagingFallback);
      if (recovered == null) return const EvidenceValue<double>.unknown();
      // Recovered only because the product's own field was missing, not
      // because it was cross-checked against a fully matching declared
      // label — always the lower trust tier, regardless of sourceVerified.
      return EvidenceValue<double>(
        value: recovered,
        provenance: EvidenceProvenance.databaseImport,
        verification: EvidenceVerification.unverified,
      );
    }

    return ScoringNutritionData(
      energyKj: imported((n) => n.energyKj),
      energyKcal: imported((n) => n.energyKcal),
      totalFat: imported((n) => n.fat),
      saturatedFat: imported((n) => n.saturatedFat),
      sugars: imported((n) => n.sugars),
      protein: imported((n) => n.proteins),
      fiber: imported((n) => n.fiber),
      salt: imported((n) => n.salt),
      sodium: imported((n) => n.sodium),
    );
  }

  static bool _fieldsAgreeWhereBothPresent(
    NutritionData left,
    NutritionData right,
  ) {
    bool agrees(double? a, double? b) => a == null || b == null || a == b;
    return agrees(left.energyKj, right.energyKj) &&
        agrees(left.energyKcal, right.energyKcal) &&
        agrees(left.fat, right.fat) &&
        agrees(left.saturatedFat, right.saturatedFat) &&
        agrees(left.carbohydrates, right.carbohydrates) &&
        agrees(left.sugars, right.sugars) &&
        agrees(left.fiber, right.fiber) &&
        agrees(left.proteins, right.proteins) &&
        agrees(left.salt, right.salt) &&
        agrees(left.sodium, right.sodium);
  }

  void _addMissingNutritionBlockers(
    ScoringNutritionData nutrition,
    Set<String> blockers,
  ) {
    if (nutrition.energyKj.value == null) blockers.add('missing_energy_kj');
    if (nutrition.totalFat.value == null) blockers.add('missing_total_fat');
    if (nutrition.saturatedFat.value == null) {
      blockers.add('missing_saturated_fat');
    }
    if (nutrition.sugars.value == null) blockers.add('missing_sugars');
    if (nutrition.fiber.value == null) blockers.add('missing_fiber');
    if (nutrition.protein.value == null) blockers.add('missing_protein');
    if (nutrition.salt.value == null) blockers.add('missing_salt');
  }

  bool _nutritionComplete(ScoringNutritionData nutrition) {
    return nutrition.energyKj.value != null &&
        nutrition.totalFat.value != null &&
        nutrition.saturatedFat.value != null &&
        nutrition.sugars.value != null &&
        nutrition.fiber.value != null &&
        nutrition.protein.value != null &&
        nutrition.salt.value != null;
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

  void _addCrossFieldNutritionBlockers(
    Set<ScoringReadinessBlocker> reasons,
    Set<String> blockers,
  ) {
    for (final reason in reasons) {
      switch (reason) {
        case ScoringReadinessBlocker.saturatedFatExceedsTotalFat:
          blockers.add('saturated_fat_exceeds_total_fat');
        case ScoringReadinessBlocker.nonPositiveTotalFatForFatCategory:
          blockers.add('non_positive_total_fat_for_fat_category');
        case ScoringReadinessBlocker.plainWaterCategoryMismatch:
          blockers.add('plain_water_category_mismatch');
        case ScoringReadinessBlocker.nutritionBasisDoesNotMatchCategory:
          // A basis that IS proven (per100g/per100ml) but does not match
          // what the resolved category expects (e.g. an explicit per100g
          // declaration for a beverage) — never silently reinterpreted as
          // the expected unit. Distinct from basis_unit_ambiguous, which
          // means basis could not be proven at all.
          blockers.add('nutrition_basis_does_not_match_category');
        default:
          break;
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
