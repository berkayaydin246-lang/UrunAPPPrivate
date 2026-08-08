# Etiketly Scoring Evidence and Readiness

## Current scope

Phases 2B-1 and 2B-2 only determine whether the available product evidence is
sufficient for a future deterministic nutrition calculation and persist that
source evidence. They do not calculate a raw nutrition value, a 0-100 Etiketly
value, a letter, or a combined nutrition and additive result.

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
approval repositories log the conflicting field names in debug builds. There
is intentionally no conflict UI in this phase.

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
The migration is not deployed by this phase.

## Methodology reference

The requirement sets follow the updated public Nutri-Score 2023 methodology:
the 2022 solid-food update, the 2023 beverage update, and the Santé publique
France Questions & Answers dated 17 March 2025. This reference does not make
Etiketly's future combined result an official Nutri-Score.

## Next phase

Phase 2B-3 can populate this contract from explicitly supported sources,
including reviewed OCR/admin workflows. OCR extraction for basis, FVL, NNS,
classification facts, and ingredient completeness is not implemented here.
Any raw calculation, 0-100 transformation, additive weight, and score UI remain
explicitly outside this phase.
