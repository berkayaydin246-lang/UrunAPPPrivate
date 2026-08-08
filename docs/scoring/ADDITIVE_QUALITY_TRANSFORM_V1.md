# Additive Quality Transform V1

## Scope And Meaning

Phase 2B-7 transforms the reviewed, canonical additive assessment into the
internal `additiveQuality` component in `0..100`.

`100` means that no eligible canonical additive contributes a penalty under
this transform. Lower values mean that reviewed canonical additive concerns
produce a larger internal Etiketly additive-component impact. The value is not
a toxicity percentage, medical-risk probability, disease probability,
regulatory authorization decision, or claim that a product is a percentage
safe.

This phase does not combine `additiveQuality` with `nutritionQuality`, choose a
component weight, create a final Etiketly Score, or expose a public score UI.

## Canonical Input Boundary

`AdditiveQualityTransformer` accepts only `CanonicalAdditiveAssessment`. It
does not parse ingredient text, inspect a product name, query a catalogue,
network, repository, AI service, clock, user vote, Riverpod provider, or UI
context.

The Phase 2B-6 authority has already resolved identity, deduplication, risk,
match authority, conflicts, additive status, future-score eligibility, and
nutrition-methodology overlap. The transform does not duplicate those rules.

Only canonical additives with `eligibleForFutureAdditiveScore == true` and a
known reviewed risk tier can contribute numerically. Ordinary ingredients,
unresolved tokens, review-required fuzzy matches, unknown risks, conflicts,
and other ineligible items receive no invented fallback penalty. They remain
available through result diagnostics.

## Candidate Comparison

| Candidate | Strengths | Main failure | Decision |
| --- | --- | --- | --- |
| Linear weighted unique count | Very simple, monotonic, auditable | Long lists fall through the floor at a constant rate and become highly sensitive to catalogue expansion | Rejected |
| Maximum-risk-only | Stable and resistant to long lists | A second distinct high additive or many medium additives have no effect | Rejected |
| Capped weighted unique sum | Bounded and duplicate-safe | The cap creates an abrupt saturation cliff; all later reviewed evidence becomes numerically invisible | Rejected |
| Tier-wise diminishing-return weighted sum | Monotonic, severity-sensitive, count-sensitive, bounded by explicit tier tails, and easy to audit | Requires a documented decay constant | Selected |
| Hybrid highest-severity base plus count | Represents worst tier and additional count | Adds a separate base-reduction authority and more interaction constants without improving traceability | Rejected |

The candidates were also checked against the complete behavioral criteria:

| Candidate | Explainability and auditability | Duplicate resistance | One high / several medium / many low | Long-list stability | Catalogue expansion | Future combination |
| --- | --- | --- | --- | --- | --- | --- |
| Linear weighted count | High | Safe only after canonical deduplication | Severity ordering is clear, but every additional item has full impact | Poor without a hard floor | Abruptly more punitive as reviewed coverage grows | Simple, but an unstable tail would dominate a later combination |
| Maximum-risk-only | High | Inherently resistant after canonicalization | One high is visible; several medium and many low collapse to one-item behavior | Very high | Stable, but newly reviewed same-tier evidence remains invisible | Stable but discards too much additive evidence |
| Capped weighted sum | High | Safe after canonical deduplication | Distinguishes counts until the cap | High after an abrupt saturation point | New evidence has full impact before the cap and none after it | Bounded, but the cap cliff complicates interpretation |
| Tier-wise diminishing return | High with explicit constants | Safe after canonical deduplication | Distinguishes severity and unique count with progressively smaller additions | High through smooth, explicit tier tails | New reviewed items have bounded marginal impact | Bounded and continuous enough for a future separately calibrated combination |
| Hybrid severity plus count | Medium | Safe after canonical deduplication | Distinguishes worst severity and extra items | Depends on multiple caps and interaction rules | Sensitive to both base-tier and count-policy changes | Possible, but carries unnecessary interaction authorities forward |

All count-sensitive candidates are monotonic when fed canonical unique items.
The selected candidate provides the best balance of deterministic ordering,
duplicate resistance, bounded behavior, catalogue-growth stability, and a
traceable future combination boundary. Its constants are Etiketly-specific
calibration choices; they are not copied from an external consumer score.

The selected model distinguishes one high from one medium, distinguishes two
high additives from one, and allows several medium additives to accumulate
without a linear count explosion. A common decay factor preserves the impact
ordering at the same within-tier occurrence position.

## Exact Formula

After canonical deduplication and eligibility/overlap filtering, let `n_t` be
the number of penalized unique additives in risk tier `t`.

For tier `t`, first-item impact `w_t`, and common decay `d`:

```text
P_t(n_t) = w_t * sum(i = 0 .. n_t - 1, d^i)
           = w_t * (1 - d^n_t) / (1 - d)

unclampedQuality = 100 - (P_low + P_medium + P_high)
additiveQuality = clamp(unclampedQuality, 0, 100)
```

V1 constants are:

| Canonical risk tier | First unique item impact `w_t` | Decay `d` | Asymptotic tier penalty cap |
| --- | ---: | ---: | ---: |
| low | `2` | `0.75` | `8` |
| medium | `9` | `0.75` | `36` |
| high | `24` | `0.75` | `96` |

The first reviewed low additive therefore has a small impact and does not
collapse quality. Low is not zero because it remains a reviewed eligible
Etiketly tier, but its first impact is intentionally much smaller than medium
or high. At an equal position within each tier, high impact remains greater
than medium impact, which remains greater than low impact.

Illustrative internal outcomes are `98` for one low, `91` for one medium, `76`
for one high, `58` for two distinct high additives, and `79.1875` for three
distinct medium additives. These are internal transform diagnostics, not
public product targets or labels.

## Tail And Clamp Behavior

Additional unique additives in one tier contribute `75%` of the preceding
same-tier contribution. This creates explicit asymptotic tier caps of `8`,
`36`, and `96` while preserving monotonicity. Contributions from different
tiers are then summed. Mixed severe tails can exceed a total penalty of `100`;
the final quality is clamped at `0`, and the result records the unclamped value
and whether the floor was applied.

Repeating the same canonical additive never advances `n_t`. Occurrence count is
diagnostic only. Different canonical additives in the same additive group
remain separate and can each contribute.

## Beverage NNS Overlap

An eligible item carrying
`NutritionMethodologyOverlap.beverageNnsAlreadyRepresented` remains present in
the canonical assessment, risk counts, explanations, and result diagnostics,
but is excluded from additive numeric contribution. The result retains the
excluded canonical item and the explicit
`beverageNnsAlreadyRepresented` reason.

This prevents automatic duplication of the qualifying beverage-NNS signal
already represented in nutrition methodology. The exclusion is not global:
the same sweetener in a non-beverage remains numerically eligible, and an
excluded polyol does not gain the overlap exemption merely from being a
sweetener.

## Result And Precision

`AdditiveQualityResult` retains:

- unrounded `qualityScore`, total penalty, and unclamped quality;
- transform version and source canonical assessment;
- eligible and penalized low/medium/high counts;
- overlap-excluded item diagnostics;
- unknown/ineligible and ordinary-ingredient counts;
- per-tier impact, decay, count, penalty, and asymptotic cap;
- floor metadata.

Internal calculation uses `double` precision and is not rounded. Presentation
rounding belongs to a future versioned UI/final-component phase.

The transform version is:

```text
additive_quality_transform_v1
```

It is separate from `updated_nutrition_profile_2023_v1` and
`nutrition_quality_transform_v1`. Any future combined Etiketly result requires
its own independently versioned policy.

## Calibration

Calibration uses `50` **INTERNAL CALIBRATION FIXTURES** built from existing
reviewed catalogue entries and canonical Phase 2B-6 states. The fixture set
covers no additives; individual and multiple low/medium/high tiers; mixed
tiers; long lists; aliases and E-codes for one identity; distinct additives in
one group; ordinary, unresolved, fuzzy, unknown, and conflicted items;
preservatives, colors, antioxidants, nitrites/nitrates, sweeteners; beverage
NNS overlap; non-beverage sweeteners; and polyol exclusion behavior.

Broad internal diagnostic bands are used only to catch implausible behavior:

| Internal calibration band | Inclusive quality range |
| --- | ---: |
| VERY_HIGH | `95..100` |
| HIGH | `80..<95` |
| MID | `55..<80` |
| LOW | `25..<55` |
| VERY_LOW | `0..<25` |

These are not public labels. The selected constants passed the complete
fixture set without a fixture-specific adjustment. Exhaustive table-driven
tests also verify tier monotonicity, severity replacement ordering, removal
direction, bounds, determinism, deduplication, and the explicit beverage-NNS
overlap exception.

## Catalogue Gaps

The reviewed local catalogue gaps remain `E249`, `E252`, `E957`, `E959`,
`E960`, `E961`, `E962`, and `E969`. Authorization, ADI, E-number family, and
NNS status do not create an Etiketly risk tier. These items remain canonical
`unknown`, ineligible, diagnostic, and numerically unpenalized until a separate
reviewed catalogue process supplies a classification.

Catalogue expansion can make a previously unknown canonical additive eligible
in a later assessment. The transform itself remains catalogue-independent and
unchanged; such a data change must remain reviewed and auditable.

## Limitations

- Constants express an internal Etiketly additive-component policy, not a
  clinical or toxicological dose-response model.
- Presence is assessed, not additive quantity or exposure dose.
- Diminishing returns deliberately reduce sensitivity to very long lists.
- Incomplete reviewed catalogue coverage remains visible but has no invented
  numeric fallback.
- Final nutrition/additive interaction and weighting are outside this phase.
