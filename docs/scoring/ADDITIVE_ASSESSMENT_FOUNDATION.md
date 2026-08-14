# Canonical Additive Assessment Foundation

## Scope

Phase 2B-6 establishes one deterministic production API for ingredient identity,
risk resolution, additive eligibility, deduplication, match authority, and
nutrition-methodology overlap metadata. It does not calculate an additive
numeric result, combine additives with `nutritionQuality`, or define a final
Etiketly Score.

The canonical API is `CanonicalIngredientRiskService`. It is pure after
ingredient matching/catalogue loading: it makes no database, network, AI,
clock, or random call.

The `additiveQuality` component covers food additives under Regulation (EC)
No 1333/2008. A generic, unspecified flavouring label such as `aroma verici`
or `flavourings` does not identify a food additive and falls under the separate
flavourings scope of Regulation (EC) No 1334/2008. The parser preserves that
ingredient text, while canonical assessment records it as
`outOfScopeFlavouringEvidence`; it receives no risk tier or additive penalty
and does not make additive evidence incomplete by itself. A specifically
identified additive or chemical remains subject to the normal matching and
readiness rules.

Regulatory references: [Regulation (EC) No 1333/2008](https://eur-lex.europa.eu/eli/reg/2008/1333/oj/eng)
and [Regulation (EC) No 1334/2008](https://eur-lex.europa.eu/eli/reg/2008/1334/oj/eng).

## Previous Multiple-Authority Problem

The audit found these paths capable of assigning or changing risk:

- `Ingredient.riskLevel` loaded the database ingredient-catalogue value.
- `enrichIngredientKnowledge` replaced `unknown` with a local explanation-
  catalogue risk.
- `ProductRiskSpec` carried a second hard-coded risk value for product detail
  and comparison.
- `AnalysisEngine` promoted ingredients to high/medium lists from name
  fragments, independently of catalogue risk.
- Product-detail `_AttentionSpec` and `_riskLevelForParsedToken` assigned
  another hard-coded display risk, including to unmatched raw tokens.
- Match/result widgets read the raw `Ingredient` value directly and therefore
  could bypass conflict handling.

`ProductRiskSpec` and `_AttentionSpec` are now display-only metadata. The
analysis engine retains non-risk signal detection for legacy explanations and
context, but those signals cannot assign, upgrade, or downgrade risk. Unmatched
display tokens remain `unknown`.

## Canonical Risk Source

The service resolves the database ingredient catalogue and the reviewed local
explanation catalogue with this deterministic policy:

1. If both have the same reviewed low/medium/high value, use that value.
2. If only the database catalogue has a reviewed value, use it.
3. If the database value is `unknown` and the reviewed explanation catalogue
   has a value, use the reviewed fallback.
4. If two known values disagree, return `unknown`, record a
   `CanonicalRiskConflict`, and make the item ineligible for future scoring.
5. If neither source has a reviewed value, preserve `unknown`.

The explanation catalogue is source data, not a second decision API.
`enrichIngredientKnowledge` no longer changes risk.

## Identity And Deduplication

Canonical identity prefers `ingredients.id`. If no database ID exists, the
stable fallback uses a normalized E-code, then a normalized canonical name.
Raw OCR text is retained as evidence but is not the primary key after a
canonical match.

For scoring deduplication, catalogue rows that carry the same valid E-code
become one `CanonicalIngredientAssessment`, even if a legacy catalogue assigned
different row IDs. E-code, canonical-name, alias, and repeated references
preserve individual `CanonicalMatchEvidence` records and one diagnostic
occurrence count. Different ingredient IDs are never merged merely because
they share an additive/display group. Occurrence count has no numeric penalty.

## Match Authority

- `exactMatch`, `eCodeMatch`, and `aliasMatch` are authoritative under the
  current matcher guarantees.
- `highConfidenceFuzzy` and `lowConfidencePossible` remain review-required and
  are not automatically eligible for future additive scoring.
- Rejected and unmatched tokens are unresolved. Their raw token, normalized
  token, confidence, and candidate metadata are retained where available.

Risk and match authority are independent dimensions. A known high-risk fuzzy
candidate is still review-required.

## Additive Eligibility

An item is an additive only when canonical metadata has a valid E-code or a
non-empty `additiveGroup`. Ordinary recognized ingredients remain available to
legacy ingredient analysis but are excluded from canonical additive counts.

`eligibleForFutureAdditiveScore` is true only when all of these conditions hold:

- the item is a recognized additive;
- the match is authoritative and participates in current analysis;
- canonical risk is reviewed low/medium/high;
- no risk conflict exists.

This is non-numeric eligibility metadata. No additive score or penalty exists.

## NNS Nutrition Overlap

The service reuses `NnsEvidenceDetector` and its versioned canonical identifier
resource. For an explicitly resolved `ScoringCategory.beverage`, a qualifying
NNS receives `beverageNnsAlreadyRepresented`. The additive remains visible and
retains its canonical risk and eligibility metadata.

The flag is not applied to non-beverages. Excluded polyols remain excluded by
the existing NNS authority. The flag has no numeric effect and does not modify
`nutritionQuality`.

## Hard-Coded Rule Audit

- BHT/BHA/TBHQ: represented by reviewed E321/E320/E319 catalogue entries.
  Duplicate risk fields were removed from product-detail specs.
- Nitrites/nitrates: E250 and E251 are represented by reviewed entries. The old
  E249/E252 string coverage has no local reviewed entry and is catalogue debt;
  no risk was invented.
- Colors: E102, E110, E120, E129, and E133 represented by reviewed entries.
  Display categories remain, but no display rule assigns risk.
- Sweeteners: reviewed entries cover aspartame E951, acesulfame K E950,
  saccharin E954, sucralose E955, cyclamate E952, sorbitol, and maltitol E965.
  Display grouping and the nutrition NNS identifier list are not risk sources.
- Preservatives: reviewed entries cover E200, E202, E210, and E211. Legacy
  signal detection remains category metadata only.
- Analysis-engine oil, flavoring, emulsifier, phosphate, stimulant, sugar, and
  processing rules remain only for legacy explanatory signals. Canonical risk
  comes exclusively from `CanonicalIngredientRiskService`.

## Catalogue Coverage Debt

The code-reviewed local catalogue has no reviewed entries for nitrite/nitrate
E249 and E252. The broader nutrition-methodology NNS resource also contains
E957, E959, E960, E961, E962, and E969 without corresponding local explanation-
catalogue entries. This does not prove that a deployed database catalogue lacks
them. Runtime database entries remain authoritative inputs when present.

Unknown or absent coverage remains `unknown`; this phase adds no scientific
classification or health claim.

The active `ADDITIVE_RISK_METHODOLOGY_V1.md` defines the reviewed mapping from
official evidence to an Etiketly tier. Its initial approved catalogue decisions
assign `low` to E202, E471, and E282 under rule `L1`. E282 retains its static
canonical identity and aliases with EFSA Journal 2014;12(7):3779 provenance.
E202 and E471 retain their canonical identities and reconcile with matching
database `low` values without a catalogue risk conflict.

## Compatibility

`ProductAnalysisResult` now carries the canonical assessment while preserving
legacy recognized/risk ingredient lists for existing UI. Those lists contain
the canonical resolved risk. Product detail, comparison, and match widgets use
the canonical service; raw unmatched product-detail tokens may still be shown
using display metadata, but their risk remains unknown.

No schema migration or deployment is required for this runtime normalization.
