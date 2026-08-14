# Nutrition Quality Transform V2

## Scope

Score v2 changes only the piecewise-linear mapping from the unchanged
`updated_nutrition_profile_2023_v1` raw result to `nutritionQuality`. It does
not change the per-100 g/per-100 ml basis, raw nutrient points, category rules,
additive assessment or penalty formula, readiness, or the final `80/20`
weighting.

Current versions are:

- `nutrition_quality_transform_v2`
- `etiketly_score_v2`

The v1 transform, constants, documentation, and audit snapshots remain
immutable historical evidence.

## Anchors

General food:

| Raw | Quality |
| ---: | ---: |
| `-5.5` | `100` |
| `0.5` | `94` |
| `2.5` | `86` |
| `10.5` | `72` |
| `18.5` | `66` |
| `26.5` | `42` |
| `34.5` | `18` |
| `42.5+` | `0` |

Cheese:

| Raw | Quality |
| ---: | ---: |
| `-5.5` | `100` |
| `0.5` | `92` |
| `2.5` | `84` |
| `10.5` | `68` |
| `18.5` | `54` |
| `26.5` | `32` |
| `34.5` | `12` |
| `42.5+` | `0` |

Red meat:

| Raw | Quality |
| ---: | ---: |
| `-5.5` | `100` |
| `0.5` | `92` |
| `2.5` | `84` |
| `10.5` | `70` |
| `18.5` | `56` |
| `26.5` | `34` |
| `34.5` | `14` |
| `42.5+` | `0` |

Fats, oils, nuts, and seeds:

| Raw | Quality |
| ---: | ---: |
| `-11.5` | `100` |
| `-5.5` | `94` |
| `2.5` | `82` |
| `10.5` | `68` |
| `18.5` | `50` |
| `26.5` | `30` |
| `34.5` | `12` |
| `42.5` | `0` |

Beverages use plain water as a typed `100` special case. Other beverages use:

| Raw | Quality |
| ---: | ---: |
| `-3.5` | `95` |
| `2.5` | `88` |
| `6.5` | `75` |
| `9.5` | `60` |
| `13.5` | `40` |
| `17.5` | `20` |
| `21.5+` | `0` |

Values between anchors use unrounded linear interpolation. Values outside the
first and last anchors clamp to the corresponding endpoint. No nutrient bonus,
exception, serving-size adjustment, package-size input, or product-name rule is
applied after the raw methodology.

## Public Bands

Public labels use the rounded integer final score:

| Display score | Label |
| ---: | --- |
| `85-100` | Çok iyi |
| `70-84` | İyi |
| `50-69` | Orta |
| `30-49` | Zayıf |
| `0-29` | Çok zayıf |

The score card separately exposes deterministic attention text when the
unchanged raw breakdown contains a major salt, sugar, or saturated-fat signal.
This does not modify the score and does not make health, safety, or medical
claims.

## Calibration Report

Run the local, production-independent v1/v2 comparison with:

```bash
dart run tool/score_v2_calibration_report.dart
```

The report includes fixture name, category, raw score, both nutrition quality
values, additive quality, both final scores, and both public bands. Regression
tests cover every anchor and interpolation region, balanced and one-negative
profiles, multi-negative products, beverages, fats/oils/nuts/seeds, positive
fiber/protein effects, and package-size invariance.
