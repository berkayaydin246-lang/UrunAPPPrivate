# Etiketly Scoring Evidence and Readiness

## Current scope

Phases 2B-1 through 2B-3 determine whether the available product evidence is
sufficient for deterministic nutrition calculation, persist that source
evidence, and let an admin verify submission evidence. Phase 2B-4 adds the pure
updated-methodology raw nutrition calculator behind that strict readiness
boundary. Phase 2B-5 transforms that raw result into an internal, category-aware
`nutritionQuality` component in `0..100`. Phase 2B-6 adds one canonical,
deterministic additive/ingredient identity and risk assessment authority with
deduplication, match authority, strict future eligibility, and non-numeric NNS
overlap metadata. Phase 2B-7 transforms eligible canonical additives into the
internal, versioned `additiveQuality` component in `0..100`. Phase 2B-8 adds the
strictly eligible, internal Etiketly Score v1 as an `80% nutritionQuality` and
`20% additiveQuality` weighted arithmetic result. Phase 2B-9 adds the guarded
Product Detail score card, presentation-only public labels, deterministic
explanations, and strict non-numeric unavailable/error states.

The domain module is pure Dart. It does not access UI state, Riverpod,
repositories, Supabase, the network, or AI services.

## Evidence rules

- Product names are never classification evidence.
- The discovery-oriented `CanonicalCategoryMapper` is not a scoring authority.
- Special categories require explicit metadata or conservative taxonomy facts.
- Unknown values are not silently converted to zero.
- FVL `provenAbsent` is different from FVL `unknown`.
- NNS `absent` is different from NNS `unknown`.
- Absence that depends on an ingredient list requires evidence that the list is
  complete.
- kcal-derived energy remains marked `derivedFromKcal`; it is not accepted as
  declared kJ for strict public readiness.
- Salt derived from sodium retains `derivedFromSodium` provenance.
- Legacy products do not gain fabricated basis, state, FVL, NNS, or category
  facts.
- OCR output is always a candidate with `ocrDeclaredLabel` / `unverified`
  provenance. Only an admin review upgrades a value to `adminVerified` /
  `verified`.

Public v1 readiness is binary: a product is either scorable or not scorable.
Evidence quality and warnings are diagnostic only and never bypass a blocker.

## Persisted evidence schema

`ScoringEvidenceSnapshot` is the typed representation of the nullable
`scoring_evidence` JSON object. Schema version 1 persists:

- nutrition basis (`per100g`, `per100ml`, `perServing`, or `unknown`)
- product state (`asSold`, `asPrepared`, or `unknown`)
- values, provenance, and verification for energy kJ, energy kcal, total fat,
  saturated fat, sugars, protein, fiber, salt, and sodium
- FVL state, percentage, provenance, verification, and dependency
- NNS tri-state evidence, provenance, verification, and dependency
- ingredient-list completeness (`complete`, `incomplete`, or `unknown`)
- resolved scoring-category evidence and the Phase 2B-1 classification facts
- optional admin verification metadata
- optional source-bearing basis/state metadata and explicit ingredient
  percentage candidates

The JSON object contains `schema_version: 1`. This evidence schema version is
only the serialization contract. It is independent from the raw nutrition
methodology version and is not a future combined Etiketly algorithm version.

Unsupported future schema versions are ignored conservatively. Unknown future
enum strings degrade to their domain `unknown` state where possible. Malformed,
negative, non-finite, or out-of-range numeric evidence is never trusted. A
missing `scoring_evidence` column value remains valid for every legacy model.

## Composition and ingredient evidence

FVL preserves three different states: a known percentage, proven absence, and
unknown. A known `0` remains known zero; it does not become unknown. Percentages
outside 0 through 100 are rejected as unknown.

NNS also remains tri-state: `present`, `absent`, and `unknown`. Absence is not
fabricated from a failed or incomplete ingredient scan. Ingredient completeness
is persisted separately so `unknown` never silently becomes `false` or
`complete`.

OCR ingredient percentages retain the exact ingredient, percentage, and label
evidence text. They are review hints only. Ingredient order does not create a
percentage, percentages are not made to sum to 100, and candidates never become
a trusted FVL value automatically. Admins may keep FVL unknown, enter a verified
0 through 100 percentage, or verify absence only when the ingredient list is
complete.

## OCR candidates and admin review

`/ocr/product-label` response schema 2 adds optional, backward-compatible
`extraction_schema_version` and `evidence_candidates` fields. Declared
`energy_kj` is preserved independently from `energy_kcal`; kcal-only labels do
not receive a converted declared kJ value.

Nutrition basis is proposed only for explicit wording equivalent to 100 g,
100 ml, or per serving. Product name, category, package, barcode, appearance,
and serving size alone are never basis evidence. Product state is proposed only
from explicit sold/prepared wording. Ambiguous text remains unknown.

The admin submission detail page has a separate **Puanlama Verisi** section for
basis, product state, ingredient completeness, FVL, NNS, scoring category, and
compact category-specific facts. Saving writes reviewed nutrition and matching
evidence in one submission-row update. Every reviewed critical nutrient becomes
`adminVerified`; sodium-derived salt remains `derivedFromSodium` unless printed
salt is reviewed. The readiness preview uses `ScoringReadinessEvaluator` and
shows only ready/missing-data diagnostics, never a result value.

## NNS evidence

The scoring-only identifier resource is versioned as
`nutri-score-2023.1`. Detection uses bounded exact canonical aliases and E
numbers E950, E951, E952, E954, E955, E957, E959, E960, E961, E962, and E969.
Polyols E420, E421, E953, E964, E965, E966, E967, and E968 are explicitly
outside this NNS set. This resource does not classify additive safety or add a
penalty.

An exact positive OCR match creates an unverified `present` candidate. No match
stays `unknown`; it never means absent. An admin may verify absence only after
the ingredient list is marked complete and deterministic detection finds no
qualifying identifier.

## Admin category verification

Admin selection creates explicit high-trust category evidence but still runs
through `ScoringCategoryResolver`. Red meat requires at least 20% and primary
ingredient confirmation. Cheese requires plant-alternative and compound-product
exclusions. A supplied nut/seed percentage must be greater than 50%. Beverage,
plain-water, general-food, and out-of-scope facts remain separate explicit
choices. `generalFood` is not an automatic fallback.

## Merge precedence

Approval and staging merges operate per evidence field. Rejected and unknown
incoming evidence cannot overwrite known evidence. Provenance precedence is:

1. `adminVerified`
2. `declaredLabel`
3. `ocrDeclaredLabel`
4. `databaseImport`
5. `derivedFromSodium` / `derivedFromKcal`
6. `unknown`

Verification is used as a secondary distinction within the same provenance.
Equal-trust contradictions retain the existing value. All known-value
contradictions are returned as internal `ScoringEvidenceConflict` records and
approval repositories log the conflicting field names in debug builds. The
admin approval confirmation also presents concise Turkish conflict warnings;
it never exposes serialized enum names. Existing higher-trust evidence remains
authoritative.

## Legacy and rollout behavior

`ProductScoringInputAdapter` uses a supported persisted snapshot when one is
present. Otherwise it retains the Phase 2B-1 legacy behavior: nutrition values
are database imports, kcal-to-kJ and sodium-to-salt conversions remain marked
as derived, and nutrition basis/state/FVL/NNS remain unknown. A legacy product
with nutrition numbers but no persisted basis is still not scorable.

Migration `20260808010000_add_scoring_evidence.sql` proposes one nullable JSONB
column named `scoring_evidence` on `products`, `product_staging`, and
`product_submissions`. Reads use wildcard selects and all model parsing is
optional, so a client with no evidence-producing call path remains compatible
before migration. Any client or importer that writes non-null scoring evidence
must be released only after the migration is manually reviewed and applied.
The migration is not deployed by this phase. After review, rollout order is:

1. Manually apply the reviewed nullable `scoring_evidence` migration.
2. Manually deploy the backward-compatible OCR backend response.
3. Verify `/ocr/product-label` through the existing authenticated Edge proxy.
4. Release the Flutter client only after the database and backend are ready.

The Edge proxy itself requires no Phase 2B-3 change or deployment.

## Methodology reference

The requirement sets follow the updated public Nutri-Score 2023 methodology:
the 2022 solid-food update, the 2023 beverage update, and the Santé publique
France Questions & Answers dated 17 March 2025. This reference does not make
Etiketly's future combined result an official Nutri-Score.

Before changing official nutrition threshold code, consult:

- [NUTRITION_METHODOLOGY_2023.md](NUTRITION_METHODOLOGY_2023.md)
- [OFFICIAL_REFERENCE_FIXTURES_2023.md](OFFICIAL_REFERENCE_FIXTURES_2023.md)

These documents are the local source-of-truth record for the implemented raw
calculator's numeric methodology and official-calculator controls. They do
not define the final Etiketly 0-100 score. The verified methodology records a
known Belgian FPS workbook discrepancy at exact beverage salt `3.2 g/100 mL`:
the March 2025 normative specification and current Q&A assign 15 points, while
the workbook returns 16. The explicit textual specification is authoritative
for the local boundary decision.

## Raw nutrition calculator

Phase 2B-4 implements the deterministic raw nutrition component in:

- `domain/models/validated_nutrition_scoring_input.dart`
- `domain/models/nutrition_raw_score_result.dart`
- `domain/services/nutrition_point_calculator.dart`
- `domain/services/nutrition_raw_score_calculator.dart`

All paths above are under `lib/features/scoring/`. The stable component
methodology identifier is `updated_nutrition_profile_2023_v1`. It identifies
only this updated raw nutrition methodology, not a combined Etiketly algorithm.

`ValidatedNutritionScoringInput.validate` reruns `ScoringReadinessEvaluator`
and is the only public construction path into the calculator. Missing evidence,
wrong basis, unknown/out-of-scope category, unknown beverage NNS, non-finite or
negative values, invalid FVL, and impossible fat-ratio states are rejected;
values are never clamped or repaired. Accepted salt and energy kJ are consumed
as provided, so the calculator performs no sodium or kcal conversion.

`NutritionRawScoreResult` separates negative and positive point breakdowns,
calculated protein from methodology-applied protein, and raw points. General
food, red meat, and fats can suppress calculated protein at their documented N
thresholds; red meat also retains the pre-cap calculation. Cheese retains its
special high-N protein behavior. Plain water returns
`PlainWaterNutritionRawScoreResult`, whose numeric totals and `rawScore` are
null rather than fabricated.

Tests under `test/scoring/` cover every numeric threshold below, exactly, and
above; category suppression/cap rules; official-calculator verified controls;
plain water; and internal arithmetic archetypes. The known workbook defect is
an explicit regression: exact beverage salt `3.2` follows the concordant
textual specification and receives 15 points.

This raw result is not an Etiketly Score. Phase 2B-5 transforms it only into the
internal nutrition component described below. There is no additive component,
nutrition/additive weighting, production A/B/C/D/E mapping, final Etiketly
Score, or normal-user score UI.

## Nutrition quality transform

Phase 2B-5 adds a separate pure normalization layer:

- `domain/models/nutrition_quality_result.dart`
- `domain/services/nutrition_quality_transformer.dart`

All paths above are under `lib/features/scoring/`. The transform version is
`nutrition_quality_transform_v1`, separate from the raw methodology version.
The transformer consumes only `NutritionRawScoreResult`; it does not access a
product, readiness evidence, database, network, clock, AI, Riverpod, or UI.

The category-specific piecewise-linear mapping is anchored to common quality
values at the official raw category transitions. It is deterministic,
continuous, monotonic, catalogue-independent, bounded to `0..100`, and keeps
internal `double` precision without rounding. Plain water maps directly from
its typed raw special case to `100`; no raw score is fabricated. Exact anchors,
tail behavior, candidate comparison, calibration results, and limitations are
documented in
[NUTRITION_QUALITY_TRANSFORM_V1.md](NUTRITION_QUALITY_TRANSFORM_V1.md).

The `41` synthetic cases are explicitly internal calibration fixtures, not
official products or public labels. Tests also cover exhaustive monotonicity,
official transition continuity, tail clamps, cross-category direction, and
one-factor sensitivity. This internal nutrition component is not exposed to
normal users and is not the final Etiketly Score.

## Canonical additive assessment

Phase 2B-6 implements the canonical runtime assessment in:

- `features/analysis/models/canonical_additive_assessment.dart`
- `features/analysis/services/canonical_ingredient_risk_service.dart`

Database ingredient identity is preferred; E-code and canonical-name fallbacks
are used only without an ID. Exact canonical, E-code, and alias matches can be
authoritative, while fuzzy candidates remain review-required. Repeated aliases,
names, and E-codes for one canonical identity are counted once. Ordinary
ingredients and unresolved tokens are explicitly separate from additives.

Reviewed database risk and reviewed explanation-catalogue risk are reconciled
only by the canonical service. A known conflict becomes `unknown` and is
recorded rather than silently selecting a more severe value. Product detail,
comparison, and `AnalysisEngine` no longer maintain independent risk decisions.

Qualifying beverage NNS can carry non-numeric nutrition-overlap metadata by
reusing the existing versioned NNS detector. Non-beverages and excluded polyols
do not receive that flag. This metadata does not alter nutrition scoring.

See
[ADDITIVE_ASSESSMENT_FOUNDATION.md](ADDITIVE_ASSESSMENT_FOUNDATION.md) for the
authority, identity, conflict, hard-coded-rule, and catalogue-gap audit.

## Additive quality transform

Phase 2B-7 implements `additiveQuality` in:

- `features/scoring/domain/models/additive_quality_result.dart`
- `features/scoring/domain/services/additive_quality_transformer.dart`

The transform consumes only `CanonicalAdditiveAssessment`, uses unique eligible
canonical additives, and applies a tier-wise diminishing-return penalty for
reviewed low/medium/high classifications. Unknown, unresolved, fuzzy,
conflicted, ordinary, and otherwise ineligible items receive no invented
numeric fallback and remain diagnostic.

Qualifying beverage NNS carrying the Phase 2B-6 nutrition-overlap flag remains
visible but is excluded from additive numeric contribution because that signal
is already represented in beverage nutrition methodology. Non-beverage
sweeteners are not automatically excluded.

The internal result retains unrounded `double` precision, a per-tier breakdown,
overlap exclusions, unknown/ineligible counts, clamp metadata, and transform
version `additive_quality_transform_v1`. Formula, constants, candidate
comparison, 50 calibration fixtures, limitations, and remaining catalogue gaps
are documented in
[ADDITIVE_QUALITY_TRANSFORM_V1.md](ADDITIVE_QUALITY_TRANSFORM_V1.md).

## Etiketly Score v1

Phase 2B-8 implements the internal final score in:

- `features/scoring/domain/models/etiketly_score_readiness_result.dart`
- `features/scoring/domain/models/etiketly_score_result.dart`
- `features/scoring/domain/services/etiketly_score_readiness_evaluator.dart`
- `features/scoring/domain/services/etiketly_score_calculator.dart`

The only production formula is:

```text
EtiketlyScore = 0.80 * nutritionQuality + 0.20 * additiveQuality
```

The transform version is `etiketly_score_v1`. It preserves unrounded component
precision and retains the nutrition methodology, nutrition transform, additive
transform, and final-score versions independently.

Final eligibility is stricter than numeric component availability. Nutrition
must pass existing readiness, ingredient evidence must be complete, and the
canonical additive assessment must have no unresolved tokens, review-required
additive matches, conflicts, unknown additive risks, or other ineligible
canonical additives. A recognized ordinary ingredient does not itself block.
Legacy and incomplete products may validly remain without a score.

Qualifying beverage NNS remains represented once through nutrition methodology;
the additive overlap exclusion is respected and final v1 adds no new NNS
penalty. Formula selection, five model candidates, six weight candidates, 60
calibration cases, 40 full-pipeline fixtures, extremes, readiness, rounding,
and limitations are documented in
[ETIKETLY_SCORE_V1.md](ETIKETLY_SCORE_V1.md).

The score is an Etiketly content-profile result, not a health/safety percentage,
medical advice, or disease-risk probability. It is not persisted and is not
used in lists or comparison. Product Detail now displays it only when final
readiness passes; incomplete and legacy products remain explicitly unavailable
without a fallback number. See
[ETIKETLY_SCORE_UI_V1.md](ETIKETLY_SCORE_UI_V1.md) for display rounding, public
bands, blocker wording, accessibility, and legacy behavior.

The result remains deterministic. AI and user voting do not affect the numeric
score. It is not medical advice, and initial catalogue score coverage is
expected to remain partial while verified evidence is rolled out.

## Next phase

Catalogue snapshot coverage analysis, list/comparison integration, backfill,
persistence, and caching remain separate controlled phases. Any future stored
score must include version invalidation and must never guess evidence from
product names.
