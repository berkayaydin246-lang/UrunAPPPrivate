# Nutrition Quality Transform V1

## Scope and status

This document defines the internal Phase 2B-5 transformation from the verified
updated-methodology raw nutrition result to `nutritionQuality` in `0..100`.
It does not define an Etiketly Score, additive penalties, nutrition/additive
weighting, a public label, or user-facing UI.

The raw methodology remains versioned separately as
`updated_nutrition_profile_2023_v1`. This transform is versioned as
`nutrition_quality_transform_v1`.

Numeric raw inputs and category rules come only from
[NUTRITION_METHODOLOGY_2023.md](NUTRITION_METHODOLOGY_2023.md). In particular,
this transform does not modify any raw threshold or the verified exact beverage
salt `3.2 g/100 mL -> 15 points` decision.

## Candidate comparison

| Candidate | Stability | Category meaning and comparability | Within-band behavior | Decision |
| --- | --- | --- | --- | --- |
| Global linear normalization | Stable and deterministic | Fails because the same raw value can represent a different official quality class for fats and beverages | Continuous, but semantically misaligned | Rejected |
| Category-specific theoretical min/max linear normalization | Stable until methodology extrema change | Treats rare mathematical extrema as equally meaningful and gives different official boundaries inconsistent quality values | Continuous, but official bands receive accidental widths | Rejected |
| Category-specific boundary-anchored piecewise linear | Stable, deterministic, and catalogue-independent | Uses common quality values at matching official transitions while retaining each category's raw structure | Continuous and preserves resolution inside broad bands | Selected |
| Catalogue percentile/distribution normalization | Changes as products are added or removed | Relative rank can be compared, but the same product changes without an evidence or methodology change | Sensitive to catalogue mix and outliers | Rejected |

The selected transform is explainable from official boundary structure and is
independent of catalogue composition, user votes, AI, network state, and time.

## Common semantic anchors

The values below are internal component anchors, not product labels or a
production A/B/C/D/E mapping.

| Official transition semantics | Nutrition quality |
| --- | ---: |
| exceptional top saturation | `100` |
| A/B transition | `85` |
| B/C transition | `70` |
| C/D transition | `45` |
| D/E transition | `20` |
| far adverse tail saturation | `0` |

The `85` and `70` anchors give the two narrow favorable regions 15 points each,
so a single raw point near the top does not create a 20-30 point jump. The broad
C and D regions receive 25 points each, preserving useful within-band
resolution. The last 20 points remain available for the adverse E tail. This
spacing is intentionally asymmetric rather than the uncalibrated
`100/75/50/25/0` pattern.

Transitions are placed halfway between adjacent integer raw classes. A result
of raw `2`, for example, remains on the favorable side of a `2/3` transition,
while raw `3` remains on the other side; interpolation itself is continuous at
the midpoint.

## Category anchor tables

General food, cheese, and red meat share these anchors:

| Raw coordinate | Nutrition quality | Meaning |
| ---: | ---: | --- |
| `-5.5` | `100` | favorable tail saturation |
| `0.5` | `85` | A/B transition |
| `2.5` | `70` | B/C transition |
| `10.5` | `45` | C/D transition |
| `18.5` | `20` | D/E transition |
| `26.5` | `0` | adverse tail saturation |

Fats, oils, nuts, and seeds use their separate official A/B boundary:

| Raw coordinate | Nutrition quality | Meaning |
| ---: | ---: | --- |
| `-11.5` | `100` | favorable tail saturation |
| `-5.5` | `85` | A/B transition |
| `2.5` | `70` | B/C transition |
| `10.5` | `45` | C/D transition |
| `18.5` | `20` | D/E transition |
| `26.5` | `0` | adverse tail saturation |

Non-water beverages have no official A raw band. Their best standard band is
B, while plain water has the unique official top classification:

| Raw coordinate | Nutrition quality | Meaning |
| ---: | ---: | --- |
| `-3.5` | `85` | favorable non-water saturation |
| `2.5` | `70` | B/C transition |
| `6.5` | `45` | C/D transition |
| `9.5` | `20` | D/E transition |
| `17.5` | `0` | adverse tail saturation |

The non-water cap of `85` preserves plain water's unique top status without
inventing a numeric raw score for water.

## Exact mathematical mapping

For the category's ordered anchors `(r_i, q_i)`, raw value `r` is transformed
as follows:

```text
if r <= first.r: quality = first.q
if r >= last.r:  quality = last.q

otherwise find adjacent anchors i and i+1 where:
  r_i <= r <= r_(i+1)

quality = q_i
          + (r - r_i) * (q_(i+1) - q_i)
            / (r_(i+1) - r_i)
```

This is continuous, deterministic, monotonic non-increasing in raw score, and
bounded to `0..100`. Adjacent integer raw values differ by at most `7.5` points
for general/cheese/red meat and by at most approximately `8.3334` points for
beverages. There is no fixed grade-point jump.

## Tail behavior

Values better than the first category anchor saturate at its first quality
value. Values worse than the last category anchor saturate at `0`. Tail clamps
avoid extrapolation below 0 or above 100 and prevent rare theoretical extrema
from controlling the meaning of the central official bands.

The theoretical raw extrema remain useful for monotonicity tests, but they are
not calibration anchors: general and cheese can mathematically reach `-17`, red
meat `-12`, fats `-17`, and beverages `-18`; adverse theoretical maxima are in
the mid-50s. These combinations need not receive extra semantic distance after
the selected tail saturation points.

## Plain water

`PlainWaterNutritionRawScoreResult` maps directly to nutrition quality `100`
with a typed plain-water transform special case. No raw value is fabricated.
This follows the methodology's unique official top classification for plain
water and does not authorize a user-facing grade or score.

## Precision and rounding

The canonical internal result is a `double`. Piecewise interpolation is not
rounded. Future presentation or final-component combination may define its own
versioned rounding rule; this phase does not. Tests use a small floating-point
tolerance only when comparing calculated decimal values.

## Calibration and sensitivity policy

Calibration uses synthetic but realistic **INTERNAL CALIBRATION FIXTURE**
inputs across every supported category. Expectations are deliberately broad
internal directions (`VERY_HIGH`, `HIGH`, `MID`, `LOW`, `VERY_LOW`), never
brand claims or public labels. The suite also checks cross-category ordering,
all official boundary transitions, exhaustive monotonicity over ranges wider
than the theoretical extrema, and one-factor sensitivity for sugars, salt,
saturated fat, fiber, protein, FVL, and beverage NNS.

The transform cannot create sensitivity absent from the integer raw
methodology. Input changes inside the same official component threshold remain
on a raw-score plateau and therefore intentionally retain the same nutrition
quality.

## Calibration outcome

The selected anchors passed the first complete calibration run without a
fixture-driven constant change:

- `41` internal calibration fixtures covered 12 beverages, 14 general foods,
  3 cheeses, 3 red-meat cases, and 9 fats/oils/nuts/seeds cases.
- Every fixture landed in its broad expected internal direction.
- Plain water outranked regular cola, olive-oil-like input outranked butter,
  plain oats outranked high-sugar cereal, and fresh lower-salt cheese outranked
  processed salty cheese.
- One-factor increases in sugars, salt, saturated fat, and beverage NNS moved
  quality downward when they changed raw points.
- One-factor increases in applicable fiber, protein, and FVL moved quality
  upward when they changed raw points.
- A within-threshold sugar change retained the same raw result and therefore
  the same quality, confirming that no fake continuous sensitivity was added.
- Exhaustive integer checks from raw `-100` through `100` were monotonic for all
  five supported calculation categories.

No archetype failed the selected broad-direction expectations, so no anchor was
tuned around an individual fixture.

## Limitations

- The transform preserves the information and plateaus of the raw methodology;
  it does not infer continuous nutrient effects between raw point thresholds.
- Cross-category comparability is anchored to official quality transitions,
  not validated against long-term health outcomes or catalogue percentiles.
- Synthetic calibration fixtures test directional plausibility and cannot
  establish product-specific claims.
- This component must be versioned and recalibrated if the official raw
  methodology or the internal anchor policy changes.
