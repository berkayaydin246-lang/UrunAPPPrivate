# Etiketly Score V1

## Scope And Semantics

Phase 2B-8 creates the first internal final Etiketly score in `0..100` from
the two separately versioned components:

- `nutritionQuality` from the verified nutrition methodology pipeline;
- `additiveQuality` from the reviewed canonical additive assessment.

`100` is the strongest combined Etiketly content profile under the complete v1
inputs. `0` is the weakest end of the same combined scale. The score is not a
percentage healthy, a percentage safe, medical advice, a disease probability,
or a regulatory safety decision.

The result remains internal. Phase 2B-8 does not add a product-detail score,
badge, colour, public label, database column, cache, migration, or backfill.

## Input Boundary

`EtiketlyScoreCalculator` consumes only:

- a `NutritionQualityResult` produced by the existing nutrition pipeline;
- an `AdditiveQualityResult` produced by the existing additive transform;
- an `EtiketlyScoreReadinessResult` derived from strict nutrition readiness,
  ingredient completeness, and the same canonical additive result.

It does not accept a raw `Product`, parse ingredients, inspect a product name,
query a repository, use Riverpod or `BuildContext`, call a network/AI service,
read user votes, or depend on time or randomness. The existing nutrition and
additive component formulas remain unchanged.

## Combination Models Compared

| Candidate | Transparency | Monotonicity | Extreme behavior | Stability and maintenance | Decision |
| --- | --- | --- | --- | --- | --- |
| Weighted arithmetic mean | One continuous formula with visible component contributions | Strictly monotonic for positive weights | Neither component can collapse the other by itself | Stable, simple, and independently versionable | Selected |
| Weighted geometric mean | Formula is explainable but less familiar | Monotonic above zero | Either zero component collapses the final result to zero | Creates disproportionate bottleneck behavior | Rejected |
| Nutrition base plus additive penalty overlay | Additive effect reads as a reduction | Monotonic before clamping | Low nutrition values reach a zero floor where further additive evidence is invisible | Requires a penalty scale and clamp policy in addition to component transforms | Rejected |
| Arithmetic mean plus severity caps | Base formula is clear | Monotonic inside cap regions | High-additive thresholds create abrupt discontinuities | Adds hidden policy authority not supported by calibration | Rejected |
| Minimum/bottleneck-influenced model | Weakest component is prominent | Monotonic | Overweights a weak component and can dominate otherwise stable profiles | More complex without a demonstrated calibration benefit | Rejected |

The arithmetic model passed the representative `0..100` monotonicity grid,
all extreme cases, 60 internal calibration cases, and 40 full-pipeline
fixtures. Calibration did not demonstrate a need for caps or nonlinear rules.

## Weight Comparison

The comparison holds nutrition quality at `90` and measures the change from
additive quality `100` to one-high-like `76` or two-high-like `58`.

| Nutrition / additive | One-high reduction | Two-high reduction | Result at N=0, A=100 | Result at N=100, A=0 | Assessment |
| --- | ---: | ---: | ---: | ---: | --- |
| `90 / 10` | `2.4` | `4.2` | `10` | `90` | Additive evidence is too easy to lose |
| `85 / 15` | `3.6` | `6.3` | `15` | `85` | Still weak for one reviewed high additive |
| `80 / 20` | `4.8` | `8.4` | `20` | `80` | Selected balance |
| `75 / 25` | `6.0` | `10.5` | `25` | `75` | Gives the less strongly specified component more authority than needed |
| `70 / 30` | `7.2` | `12.6` | `30` | `70` | Additive component becomes too influential |
| `60 / 40` | `9.6` | `16.8` | `40` | `60` | Evidence-strength balance is not defensible |

Nutrition receives the larger weight because it is grounded in the strongly
specified, verified nutrition methodology. Additive quality remains material
but bounded because it is an Etiketly-specific transform of reviewed catalogue
tiers. The selection was not copied from a previous chat suggestion or fitted
to Yuka or any external brand score.

## Selected Formula

Let `N` be unrounded `nutritionQuality` and `A` be unrounded
`additiveQuality`:

```text
nutritionContribution = 0.80 * N
additiveContribution  = 0.20 * A
EtiketlyScore          = nutritionContribution + additiveContribution
```

Both inputs are already constrained to `0..100`, and the positive weights sum
to one. The result therefore remains in `0..100` without a hidden cap or floor.
There is exactly one production final-score formula, in
`EtiketlyScoreCalculator`.

## Extreme And Sensitivity Results

| Nutrition | Additives | Final v1 result | Interpretation within calibration only |
| ---: | ---: | ---: | --- |
| `100` | `100` | `100` | Maximum combined endpoint |
| `100` | `0` | `80` | Excellent nutrition cannot erase the weakest additive endpoint |
| `0` | `100` | `20` | No additive penalty cannot erase the weakest nutrition endpoint |
| `0` | `0` | `0` | Minimum combined endpoint |
| `90` | `76` | `87.2` | One-high-like additive profile remains visible and bounded |
| `90` | `58` | `83.6` | Two-high-like profile has a larger continuous effect |
| `90` | `44.5` | `80.9` | Three-high-like profile remains more influential without a cap |
| `30` | `100` | `44` | Weak nutrition is not presented as excellent because additives are clear |
| `30` | `30` | `30` | Equal components retain their value |

At constant nutrition, moving from no additive penalty (`A=100`) to one-high
(`A=76`) lowers the final result by `4.8`; two-high (`A=58`) lowers it by
`8.4`; three-high (`A=44.5`) lowers it by `11.1`. This was judged meaningful
without allowing additive classifications to dominate the nutrition method.

## Final-Score Readiness

A numeric component being technically available is not enough. Final score v1
is calculated only when every following condition holds:

- existing strict nutrition readiness is scorable;
- ingredient evidence completeness is `complete`;
- the canonical assessment has no unresolved ingredient token;
- no canonical additive match requires review;
- no canonical additive risk conflict exists;
- no canonical additive has unknown reviewed risk;
- every recognized canonical additive is eligible under the Phase 2B-6 policy.

Typed blocker codes are:

- `nutritionNotReady`;
- `ingredientEvidenceIncomplete`;
- `unresolvedIngredientEvidence`;
- `reviewRequiredAdditiveEvidence`;
- `additiveRiskConflict`;
- `unknownAdditiveRisk`;
- `additiveAssessmentIncomplete`.

The current canonical unresolved-token model cannot safely prove that an
unmatched token is ordinary rather than additive-like. Such evidence therefore
remains not calculable. A recognized canonical ordinary ingredient does not
block the final score merely because it is outside additive classification.
Legacy products with incomplete evidence remain unscored.

## Calculated And Not Calculable Results

`EtiketlyScoreResult` has explicit `calculated` and `notCalculable` states. A
not-calculable result has no score and no component contributions; it retains
the available source component results, readiness diagnostics, available
independent versions, and machine-readable explanation codes. If strict
nutrition readiness prevented a nutrition component from existing, the result
does not fabricate one. Missing evidence is never converted to a favorable
numeric default.

Calculated results can expose deterministic explanation codes for nutrition
being the dominant component, additive contribution, absence of an eligible
additive penalty, and beverage NNS handling. These codes are not medical advice
or public UI strings.

## Beverage NNS Overlap

Phase 2B-7 already excludes a qualifying beverage NNS from additive numeric
contribution when nutrition methodology represents the same signal. Final v1
uses the resulting `additiveQuality` unchanged and adds no NNS penalty or cap.
The overlap-excluded item remains visible in canonical and final diagnostics as
`beverageNnsHandledInNutrition`.

## Calibration And Integration

The internal final calibration matrix contains exactly `60` cases: ten
nutrition-quality levels (`100` through `10`) crossed with six canonical
additive profiles (none, one low, one medium, one high, two high, and three
high). Broad bands are test diagnostics only and are not public labels.

An additional `40` end-to-end synthetic fixtures run through:

```text
verified scoring input
-> strict nutrition validation
-> nutrition raw calculation
-> nutrition quality transform
-> canonical additive assessment
-> additive quality transform
-> final readiness
-> Etiketly Score v1
```

The set covers water, oats, breads, yogurts, cereals, biscuits, chips, cola,
NNS beverages, juice, cheeses, red meat, processed meat, oils, butter, nuts,
preservatives, colours, antioxidants, nitrite/nitrate, and mixed additive
profiles. Directional tests preserve water over regular cola, oats over sugary
cereal, olive-oil-like over butter-like, fresh lower-salt cheese over processed
salty cheese, no additive penalty over medium over high at equal nutrition, and
better nutrition over worse nutrition at equal additive quality.

## Precision, Rounding, And Versions

Components and the final result retain unrounded `double` precision. Components
are never rounded before combination. A future UI may display the nearest
integer using Dart `round()`, for example internal `78.4375` as `78 / 100`.
This phase does not render that display.

Independent versions retained by the result are:

```text
updated_nutrition_profile_2023_v1
nutrition_quality_transform_v1
additive_quality_transform_v1
etiketly_score_v1
```

## Read-Only Catalogue Coverage

No safe local catalogue snapshot was found that jointly contains verified
nutrition readiness, ingredient completeness, and canonical additive
assessment for real products. Example seed/YAML/CSV source files do not satisfy
that boundary. No production connection was opened and readiness was not
weakened, so a real-catalogue coverage count is intentionally not reported in
this phase.

## Limitations

- Component methodology limitations continue to apply to the final result.
- Incomplete or unresolved additive coverage intentionally reduces score
  availability rather than lowering a numeric score.
- The selected weights are a versioned Etiketly policy, not a clinical model.
- Catalogue updates can change a future canonical assessment, but the same
  complete canonical and nutrition inputs always produce the same v1 result.
- Public labels, colours, score UI, persistence, caching, and version
  invalidation policy remain outside Phase 2B-8.
