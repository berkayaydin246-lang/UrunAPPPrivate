import 'package:food_analyzer_app/features/scoring/domain/models/scoring_types.dart';

/// Section I of the basis remediation pass — every possible outcome of
/// attempting to independently revalidate a product's exact nutrition
/// basis unit against its live retailer source. Deliberately no generic
/// "success" state for ambiguous source evidence: [genericBasisStillAmbiguous]
/// is its own distinct, still-blocking outcome, never folded into
/// [exactBasisRevalidated].
enum BasisRevalidationOutcome {
  /// The source was fetched, product identity was verified, the fetched
  /// nutrition matches the stored nutrition field-for-field, and the
  /// source declares an exact, unambiguous g or mL basis. The only outcome
  /// that ever produces a revalidated [NutritionBasis.per100g] /
  /// [NutritionBasis.per100ml] value.
  exactBasisRevalidated,

  /// The source was fetched and identity/nutrition checks passed, but the
  /// source itself only ever declares a generic per-100 basis (e.g. "100 g
  /// / ml", or the historical pre-remediation contract) — the exact unit
  /// genuinely cannot be proven from this source. Still blocked; never
  /// treated as a success.
  genericBasisStillAmbiguous,

  /// The source could not be fetched at all (network failure, 404, page
  /// removed) — distinct from a fetch that succeeds but proves nothing.
  sourceUnavailable,

  /// The source was fetched, but the strongest available deterministic
  /// identifier (barcode, retailer SKU, canonical URL product identifier)
  /// could not confirm the fetched page is the SAME product as the stored
  /// row. Never inferred from name/brand similarity alone. Fails closed.
  identityUnverified,

  /// Identity was confirmed, but the freshly-fetched nutrition values
  /// disagree with the stored scoring-relevant nutrition on at least one
  /// field the selected scoring branch actually depends on. A live fetch
  /// today is NEW evidence, not proof of what the historical page said —
  /// this basis must never be attached to the old, possibly-superseded
  /// nutrition numbers. The normal ingestion pipeline may later ingest the
  /// new source as a new evidence version; this service never does that
  /// itself.
  sourceChangedRequiresReingest,

  /// Identity was confirmed and every scoring-relevant field the fresh
  /// source DID provide agrees with the stored value, but at least one
  /// nutrition field that the STORED product's scoring branch actually
  /// depends on (per ScoringReadinessEvaluator.requiredNutritionFields)
  /// is simply absent from the freshly-fetched source. Absence is never
  /// treated as agreement — a live source that doesn't mention a
  /// score-relevant field proves nothing about whether the old stored
  /// value is still correct, so this basis must never be attached to the
  /// old nutrition either. Distinct from [sourceChangedRequiresReingest]:
  /// there the fresh source affirmatively disagrees; here it simply never
  /// said.
  nutritionConsistencyUnverified,

  /// The source was fetched and identity confirmed, but no per-100 basis
  /// signal of any kind was found on the (current) page at all.
  basisNotPresent,

  /// An unexpected failure isolated to this one product/candidate.
  unexpectedError,
}

/// Immutable record of one revalidation attempt. Section F requires every
/// field here be retained precisely because a live fetch is NEW evidence
/// about the CURRENT page state, not a time machine into what the page
/// said when originally scraped — every field is needed to audit that
/// distinction later.
class BasisRevalidationResult {
  const BasisRevalidationResult({
    required this.productId,
    required this.outcome,
    this.source,
    this.sourceUrl,
    this.fetchedAt,
    this.adapterVersion,
    this.rawBasisText,
    this.normalizedBasis,
    this.revalidatedBasis,
    this.identityVerificationMethod,
    this.nutritionConsistencyChecked = const [],
    this.nutritionMismatchFields = const [],
    this.nutritionMissingRequiredFields = const [],
    this.errorType,
  });

  final String productId;
  final BasisRevalidationOutcome outcome;

  // Section F provenance fields — always recorded when a fetch happened at
  // all, regardless of outcome, so a human can audit exactly what was
  // fetched, when, and with which adapter version.
  final String? source;
  final String? sourceUrl;
  final DateTime? fetchedAt;
  final String? adapterVersion;
  final String? rawBasisText;
  final String? normalizedBasis;

  /// Only non-null when [outcome] is [BasisRevalidationOutcome.exactBasisRevalidated].
  final NutritionBasis? revalidatedBasis;

  /// Which deterministic identifier tier confirmed identity (Section G) —
  /// e.g. 'barcode', 'canonical_url_identifier'. Null when identity was
  /// never reached or could not be confirmed.
  final String? identityVerificationMethod;

  /// Which scoring-relevant nutrition fields were compared (Section H).
  final List<String> nutritionConsistencyChecked;

  /// Non-empty only for [BasisRevalidationOutcome.sourceChangedRequiresReingest]
  /// — exactly which fields disagreed.
  final List<String> nutritionMismatchFields;

  /// Non-empty only for [BasisRevalidationOutcome.nutritionConsistencyUnverified]
  /// — exactly which fields the stored product's scoring branch requires
  /// that the freshly-fetched source simply never provided.
  final List<String> nutritionMissingRequiredFields;

  final String? errorType;
}
