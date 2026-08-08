# Etiketly Scoring Evidence and Readiness

## Current scope

Phases 2B-1 through 2B-3 determine whether the available product evidence is
sufficient for a future deterministic nutrition calculation, persist that
source evidence, and let an admin verify submission evidence. They do not
calculate a raw nutrition value, a 0-100 Etiketly value, a letter, or a combined
nutrition and additive result.

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
only the serialization contract. It is not a methodology version and is not a
future scoring algorithm version. There is no scoring algorithm version yet,
because no score exists.

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

## Next phase

Any raw calculation, 0-100 transformation, additive weight, public result, and
score UI remain explicitly outside this phase. Legacy catalog backfill also
requires a separate controlled process and must not guess evidence from product
names.
