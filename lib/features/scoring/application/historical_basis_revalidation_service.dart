import 'package:food_analyzer_app/features/product/models/nutrition_data.dart';
import 'package:food_analyzer_app/features/product/models/product.dart';
import 'package:food_analyzer_app/features/scoring/adapters/product_scoring_input_adapter.dart';
import 'package:food_analyzer_app/features/scoring/application/basis_source_fetcher.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/basis_revalidation_result.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_nutrition_data.dart';
import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';
import 'package:food_analyzer_app/features/scoring/domain/services/scoring_readiness_evaluator.dart';

/// Section F of the basis remediation pass: a source-neutral, deterministic
/// service that attempts to independently prove a product's exact
/// nutrition-declaration unit (g vs mL) from its live retailer source, for
/// products whose only historical basis evidence is generically ambiguous.
///
/// Never invents, never infers from category/name/package size — see
/// [_verifyIdentity] (Section G) and [_nutritionMismatches] (Section H),
/// both of which fail closed rather than guess. A live fetch is treated
/// throughout as NEW current evidence about the page as it exists right
/// now, never as proof of what the page said when the product was
/// originally scraped — the two are only ever linked once identity AND
/// nutrition consistency are both independently confirmed.
///
/// This service never writes anything itself — see
/// tool/final_legacy_basis_revalidation.dart for the dry-run/apply CLI that
/// wraps it and the only write path (through the ordinary
/// ProductScoringLifecycleService, unchanged).
class HistoricalBasisRevalidationService {
  const HistoricalBasisRevalidationService({
    required this.fetcher,
    this.extractCanonicalIdentifier,
    this.scoringInputAdapter = const ProductScoringInputAdapter(),
    this.readinessEvaluator = const ScoringReadinessEvaluator(),
  });

  final BasisSourceFetcher fetcher;

  /// Retailer-specific canonical-product-identifier extraction from a
  /// stored `sourceUrl`, injected by the caller so this service itself
  /// never hardcodes a single retailer's URL shape (Section M:
  /// source-neutral). When null, only the barcode identity tier is used.
  final String? Function(String sourceUrl)? extractCanonicalIdentifier;

  /// The SAME sanctioned raw-nutrition-to-scoring-evidence conversion used
  /// everywhere else in the pipeline (energy kcal→kj via *4.184, salt from
  /// sodium via *2.5) — never reimplemented here, so this service can never
  /// silently invent a different conversion than the rest of the app.
  final ProductScoringInputAdapter scoringInputAdapter;

  /// The SAME branch-dependency logic the readiness/blocker pipeline uses
  /// (Section 2 of this fix) — reused, not duplicated, to determine which
  /// nutrition fields the STORED product's scoring branch actually depends
  /// on before deciding whether a missing fresh-source field is safe to
  /// ignore.
  final ScoringReadinessEvaluator readinessEvaluator;

  /// Maps each nutrition-numeric [ScoringRequirement] to its reporting
  /// name and its accessor on [ScoringNutritionData] — the single place
  /// this service knows how a scoring requirement corresponds to a
  /// concrete nutrition value, reused for both the missing-field and the
  /// mismatch checks so the two can never drift apart.
  static const _requirementFieldNames = {
    ScoringRequirement.energyKj: 'energy_kj',
    ScoringRequirement.totalFat: 'total_fat',
    ScoringRequirement.saturatedFat: 'saturated_fat',
    ScoringRequirement.sugars: 'sugars',
    ScoringRequirement.salt: 'salt',
    ScoringRequirement.protein: 'protein',
    ScoringRequirement.fiber: 'fiber',
  };

  double? _fieldValue(ScoringNutritionData nutrition, ScoringRequirement requirement) {
    return switch (requirement) {
      ScoringRequirement.energyKj => nutrition.energyKj.value,
      ScoringRequirement.totalFat => nutrition.totalFat.value,
      ScoringRequirement.saturatedFat => nutrition.saturatedFat.value,
      ScoringRequirement.sugars => nutrition.sugars.value,
      ScoringRequirement.salt => nutrition.salt.value,
      ScoringRequirement.protein => nutrition.protein.value,
      ScoringRequirement.fiber => nutrition.fiber.value,
      _ => null,
    };
  }

  Future<BasisRevalidationResult> revalidate(Product product) async {
    final source = _clean(product.source);
    final sourceUrl = _clean(product.sourceUrl);
    if (source == null || sourceUrl == null) {
      return BasisRevalidationResult(
        productId: product.id,
        outcome: BasisRevalidationOutcome.sourceUnavailable,
      );
    }

    BasisSourceFetchResult? fetched;
    try {
      fetched = await fetcher.fetch(source: source, sourceUrl: sourceUrl);
    } catch (error) {
      return BasisRevalidationResult(
        productId: product.id,
        outcome: BasisRevalidationOutcome.unexpectedError,
        source: source,
        sourceUrl: sourceUrl,
        errorType: error.runtimeType.toString(),
      );
    }
    if (fetched == null) {
      return BasisRevalidationResult(
        productId: product.id,
        outcome: BasisRevalidationOutcome.sourceUnavailable,
        source: source,
        sourceUrl: sourceUrl,
      );
    }

    final identityMethod = _verifyIdentity(product, fetched);
    if (identityMethod == null) {
      return BasisRevalidationResult(
        productId: product.id,
        outcome: BasisRevalidationOutcome.identityUnverified,
        source: source,
        sourceUrl: sourceUrl,
        fetchedAt: fetched.fetchedAt,
        adapterVersion: fetched.adapterVersion,
        rawBasisText: fetched.rawBasisText,
        normalizedBasis: fetched.normalizedBasis,
      );
    }

    final normalized = fetched.normalizedBasis;
    if (normalized == 'unknown' || normalized == 'per_serving') {
      return BasisRevalidationResult(
        productId: product.id,
        outcome: BasisRevalidationOutcome.basisNotPresent,
        source: source,
        sourceUrl: sourceUrl,
        fetchedAt: fetched.fetchedAt,
        adapterVersion: fetched.adapterVersion,
        rawBasisText: fetched.rawBasisText,
        normalizedBasis: normalized,
        identityVerificationMethod: identityMethod,
      );
    }

    // Section H (dependency-aware, per this fix): never attach a
    // freshly-fetched basis to stale historical nutrition numbers without
    // proving that every nutrition value the STORED product's own resolved
    // scoring branch actually depends on is still the same declaration.
    // Reuses readinessEvaluator.requiredNutritionFields — the SAME
    // branch-dependency logic the readiness/blocker pipeline uses — rather
    // than a second, independently-maintained dependency table. A field
    // the selected branch never uses is ignored entirely here, both for
    // the missing-field check and the mismatch check. Checked BEFORE
    // deciding exact-vs-generic, so a changed or unverifiable source is
    // reported as such regardless of what its new basis text says.
    final consistency = _nutritionConsistency(product, fetched.nutrition);
    if (consistency.mismatches.isNotEmpty) {
      return BasisRevalidationResult(
        productId: product.id,
        outcome: BasisRevalidationOutcome.sourceChangedRequiresReingest,
        source: source,
        sourceUrl: sourceUrl,
        fetchedAt: fetched.fetchedAt,
        adapterVersion: fetched.adapterVersion,
        rawBasisText: fetched.rawBasisText,
        normalizedBasis: normalized,
        identityVerificationMethod: identityMethod,
        nutritionConsistencyChecked: consistency.checked,
        nutritionMismatchFields: consistency.mismatches,
      );
    }
    if (consistency.missingFromFreshSource.isNotEmpty) {
      // Fresh source agrees on everything it DOES declare, but is silent
      // on at least one field this branch needs. Absence is never proof
      // of agreement — fail closed rather than attach this basis to
      // possibly-superseded stored nutrition.
      return BasisRevalidationResult(
        productId: product.id,
        outcome: BasisRevalidationOutcome.nutritionConsistencyUnverified,
        source: source,
        sourceUrl: sourceUrl,
        fetchedAt: fetched.fetchedAt,
        adapterVersion: fetched.adapterVersion,
        rawBasisText: fetched.rawBasisText,
        normalizedBasis: normalized,
        identityVerificationMethod: identityMethod,
        nutritionConsistencyChecked: consistency.checked,
        nutritionMissingRequiredFields: consistency.missingFromFreshSource,
      );
    }

    final exactBasis = switch (normalized) {
      'per_100g' => NutritionBasis.per100g,
      'per_100ml' => NutritionBasis.per100ml,
      _ => null,
    };
    if (exactBasis != null) {
      return BasisRevalidationResult(
        productId: product.id,
        outcome: BasisRevalidationOutcome.exactBasisRevalidated,
        source: source,
        sourceUrl: sourceUrl,
        fetchedAt: fetched.fetchedAt,
        adapterVersion: fetched.adapterVersion,
        rawBasisText: fetched.rawBasisText,
        normalizedBasis: normalized,
        revalidatedBasis: exactBasis,
        identityVerificationMethod: identityMethod,
        nutritionConsistencyChecked: consistency.checked,
      );
    }

    // Only 'per_100' (historical) / 'per_100_generic' (corrected contract)
    // reach here — a genuine, still-ambiguous per-100 declaration.
    return BasisRevalidationResult(
      productId: product.id,
      outcome: BasisRevalidationOutcome.genericBasisStillAmbiguous,
      source: source,
      sourceUrl: sourceUrl,
      fetchedAt: fetched.fetchedAt,
      adapterVersion: fetched.adapterVersion,
      rawBasisText: fetched.rawBasisText,
      normalizedBasis: normalized,
      identityVerificationMethod: identityMethod,
      nutritionConsistencyChecked: consistency.checked,
    );
  }

  /// Section G strict identity gate. Barcode is always the strongest tier
  /// when present on both sides. The canonical-URL-identifier tier only
  /// ever runs when the caller supplied [extractCanonicalIdentifier] AND
  /// the fetcher itself reports one — never a name/brand similarity
  /// fallback. Returns null (fail closed) when neither tier can confirm a
  /// match, including when one side has data the other lacks.
  String? _verifyIdentity(Product product, BasisSourceFetchResult fetched) {
    final storedBarcode = _clean(product.barcode);
    final fetchedBarcode = _clean(fetched.barcode);
    if (storedBarcode != null && fetchedBarcode != null) {
      return storedBarcode == fetchedBarcode ? 'barcode' : null;
    }

    final extract = extractCanonicalIdentifier;
    final storedUrl = product.sourceUrl;
    if (extract != null && storedUrl != null && fetched.canonicalUrlIdentifier != null) {
      final storedIdentifier = extract(storedUrl);
      if (storedIdentifier != null) {
        return storedIdentifier == fetched.canonicalUrlIdentifier
            ? 'canonical_url_identifier'
            : null;
      }
    }
    return null;
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Section H strict, dependency-aware nutrition consistency gate.
  /// Determines exactly which nutrition fields the STORED product's own
  /// resolved scoring branch depends on (via [readinessEvaluator] — never
  /// a second hardcoded table), converts both stored and freshly-fetched
  /// raw nutrition through the SAME sanctioned normalization
  /// ([scoringInputAdapter], never a bespoke conversion here), and then,
  /// for each required field the stored data actually used:
  ///  - fresh source silent on it → [_NutritionConsistency.missingFromFreshSource]
  ///    (never treated as agreement — fails closed).
  ///  - fresh source disagrees beyond machine tolerance →
  ///    [_NutritionConsistency.mismatches].
  ///  - fresh source agrees → contributes to [_NutritionConsistency.checked]
  ///    only.
  /// A field the selected branch does not depend on is ignored entirely,
  /// in both directions — its absence or disagreement can never block or
  /// falsely clear this gate.
  _NutritionConsistency _nutritionConsistency(
    Product product,
    NutritionData? fetchedRaw,
  ) {
    final storedInput = scoringInputAdapter.fromProduct(product);
    final storedNutrition = storedInput.nutrition;
    final fetchedNutrition = scoringInputAdapter.fromLegacyNutrition(fetchedRaw);
    final category = storedInput.categoryEvidence.resolvedCategory;
    final required = readinessEvaluator.requiredNutritionFields(
      category,
      storedNutrition,
    );

    final checked = <String>[];
    final mismatches = <String>[];
    final missingFromFreshSource = <String>[];
    for (final entry in _requirementFieldNames.entries) {
      if (!required.contains(entry.key)) continue;
      final storedValue = _fieldValue(storedNutrition, entry.key);
      // The stored score never depended on a value it didn't have — no
      // basis to compare, so this field contributes nothing either way.
      if (storedValue == null) continue;
      checked.add(entry.value);
      final fetchedValue = _fieldValue(fetchedNutrition, entry.key);
      if (fetchedValue == null) {
        missingFromFreshSource.add(entry.value);
      } else if (!_closeEnough(storedValue, fetchedValue)) {
        mismatches.add(entry.value);
      }
    }
    return _NutritionConsistency(
      checked: checked,
      mismatches: mismatches,
      missingFromFreshSource: missingFromFreshSource,
    );
  }

  // Machine-level floating serialization tolerance ONLY — never a broad
  // fuzzy tolerance for genuinely different values.
  static const _epsilon = 1e-9;
  bool _closeEnough(double a, double b) => (a - b).abs() <= _epsilon;
}

/// Result of [HistoricalBasisRevalidationService._nutritionConsistency] —
/// kept as a small private holder rather than reusing
/// [BasisRevalidationResult] directly so the branch-dependency computation
/// stays decoupled from the outcome-selection logic in [HistoricalBasisRevalidationService.revalidate].
class _NutritionConsistency {
  const _NutritionConsistency({
    required this.checked,
    required this.mismatches,
    required this.missingFromFreshSource,
  });

  final List<String> checked;
  final List<String> mismatches;
  final List<String> missingFromFreshSource;
}
