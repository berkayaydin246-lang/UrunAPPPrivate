# Etiketly Scoring Readiness

## Current scope

Phase 2B-1 only determines whether the available product evidence is sufficient
for a future deterministic nutrition calculation. It does not calculate a raw
nutrition value, a 0-100 Etiketly value, a letter, or a combined nutrition and
additive result.

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

## Methodology reference

The requirement sets follow the updated public Nutri-Score 2023 methodology:
the 2022 solid-food update, the 2023 beverage update, and the Santé publique
France Questions & Answers dated 17 March 2025. This reference does not make
Etiketly's future combined result an official Nutri-Score.

## Next phase

Phase 2B-2 may add verified persistence/adapters and the threshold-based raw
nutrition calculator. Any raw calculation, 0-100 transformation, additive
weight, and score UI remain explicitly outside this phase.
