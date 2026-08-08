# Official Calculator Reference Fixtures 2023

## Status and provenance

Every case below is an **OFFICIAL CALCULATOR VERIFIED CONTROL FIXTURE**. The
nutrition inputs were constructed locally and entered into the official
Belgian FPS workbook. They are not official published product examples.

Verifier: Belgian FPS Public Health, *Nutri-Score calculation tool for the
updated algorithm*, from the official
[calculation-tool page](https://www.health.belgium.be/en/tools/nutri-score-calculation-tool).
The page and workbook were last updated 24 October 2025; the workbook exposes
no separate semantic version. This fixture set identifies it by:

```text
filename: va_nutri-score_calculation_tool_updated_algorithm.xlsx
sha256: c80ea768ee8fae68b25e4dc04584d8494e22d632e49cf9763af39c79ca8aa590
retrieved_and_verified: 2026-08-08
calculation_host: LibreOffice 24.2.7.2
```

The workbook was loaded without editing formulas. Inputs were entered into
blank rows, recalculation was forced, outputs were read, and the workbook was
closed without saving. Grades below are source-verification metadata only, not
Etiketly production mapping.

The known exact-`3.2` beverage-salt workbook discrepancy is documented in
[NUTRITION_METHODOLOGY_2023.md](NUTRITION_METHODOLOGY_2023.md). The current
Sante publique France Q&A and normative Conditions of Use agree that exact
`3.2` receives 15 points; the workbook remains a reference implementation and
does not override those concordant textual specifications.

## General food control

**Category:** `GENERAL_FOOD`

| Input | Value per 100 g | Points | Workbook cells |
| --- | ---: | ---: | --- |
| Energy | `1000 kJ` | 2 | `B6 -> K6` |
| Sugars | `8 g` | 2 | `C6 -> AA6` |
| Saturated fat | `2 g` | 1 | `D6 -> M6` |
| Salt | `0.6 g` | 2 | `F6 -> Z6` |
| FVL | `50%` | 1 | `H6 -> W6` |
| Fiber | `4 g` | 1 | `I6 -> X6` |
| Protein | `8 g` | 3 | `J6 -> Y6` |

```text
N = 2 + 2 + 1 + 2 = 7
calculated P = applied P = 1 + 1 + 3 = 5
raw nutritional score = 7 - 5 = 2
official workbook grade metadata = B
```

`General foods!AB6:AE6` returned `N=7`, `P=5`, `raw=2`, `Nutriscore_B`.

## Cheese control

**Category:** `CHEESE`

| Input | Value per 100 g | Points | Workbook cells |
| --- | ---: | ---: | --- |
| Energy | `1400 kJ` | 4 | `B6 -> J6` |
| Sugars | `18 g` | 5 | `C6 -> Y6` |
| Saturated fat | `6 g` | 5 | `D6 -> L6` |
| Salt | `1.4 g` | 6 | `F6 -> X6` |
| FVL | `0%` | 0 | `G6 -> N6` |
| Fiber | `0 g` | 0 | `H6 -> V6` |
| Protein | `18 g` | 7 | `I6 -> W6` |

```text
N = 4 + 5 + 5 + 6 = 20
calculated P = applied P = 0 + 0 + 7 = 7
raw nutritional score = 20 - 7 = 13
official workbook grade metadata = D
```

This verifies cheese protein remains applied at `N >= 11`.
`Cheese!Z6:AC6` returned `N=20`, `P=7`, `raw=13`, `Nutriscore_D`.

## Red-meat control

**Category:** `RED_MEAT`

This fixture presumes the product already met the official category conditions;
it does not use a product name as evidence.

| Input | Value per 100 g | Points | Workbook cells |
| --- | ---: | ---: | --- |
| Energy | `1000 kJ` | 2 | `B6 -> J6` |
| Sugars | `0 g` | 0 | `C6 -> Y6` |
| Saturated fat | `2 g` | 1 | `D6 -> L6` |
| Salt | `0.2 g` | 0 | `F6 -> X6` |
| FVL | `0%` | 0 | `G6 -> N6` |
| Fiber | `0 g` | 0 | `H6 -> V6` |
| Protein | `18 g` | 7 calculated, 2 applied | `I6 -> W6` |

```text
N = 2 + 0 + 1 + 0 = 3
calculated protein points = 7
category-applied protein points = min(7, 2) = 2
calculated P = applied P = 0 + 0 + 2 = 2
raw nutritional score = 3 - 2 = 1
official workbook grade metadata = B
```

`Red meat!Z6:AC6` returned `N=3`, `P=2`, `raw=1`, `Nutriscore_B`; capped
protein was observable at `W6=2`.

## Fats, oils, nuts, and seeds control

**Category:** `FATS_OILS_NUTS_SEEDS`

| Input/derived value | Value per 100 g | Points | Workbook cells |
| --- | ---: | ---: | --- |
| Total fat | `80 g` | - | `C6` |
| Saturated fat | `16 g` | - | `D6` |
| Saturated/total ratio | `20%` | 2 | `E6 -> Z6` |
| Energy from saturated fat | `592 kJ` | 4 | `F6 -> AE6` |
| Sugars | `8 g` | 2 | `G6 -> AD6` |
| Salt | `0.4 g` | 1 | `I6 -> AC6` |
| FVL | `50%` | 1 | `K6 -> AF6` |
| Fiber | `4.1 g` | 1 | `L6 -> AA6` |
| Protein | `8 g` | 3 calculated, not applied | `M6 -> AB6` |

```text
N = 2 + 4 + 2 + 1 = 9
calculated P = 1 + 1 + 3 = 5
applied P at N >= 7 = FVL 1 + fiber 1 = 2
raw nutritional score = 9 - 2 = 7
official workbook grade metadata = C
```

`Fats, oils, nuts and seeds!AG6:AJ6` returned `N=9`, displayed `P=5`,
`raw=7`, `Nutriscore_C`. Raw 7 confirms protein suppression at `N >= 7`.

## Beverage control

**Category:** `BEVERAGE`

| Input | Value per 100 mL | Points | Workbook cells |
| --- | ---: | ---: | --- |
| Plain water selector | `NO` | - | `B6` |
| Energy | `90 kJ` | 1 | `C6 -> AB6` |
| Sugars | `2 g` | 1 | `D6 -> AD6` |
| Saturated fat | `1 g` | 0 | `E6 -> O6` |
| Salt | `0.2 g` | 0 | `G6 -> AC6` |
| NNS | present (`YES`) | 4 | `H6`, included in `AE6` |
| FVL | `60%` | 2 | `J6 -> Y6` |
| Fiber | `3 g` | 0 | `K6 -> Z6` |
| Protein | `1.5 g` | 1 | `L6 -> AA6` |

```text
N = 1 + 1 + 0 + 0 + 4 = 6
calculated P = applied P = 2 + 0 + 1 = 3
raw nutritional score = 6 - 3 = 3
official workbook grade metadata = C
```

`Beverages!AE6:AH6` returned `N=6`, `P=3`, `raw=3`, `Nutriscore_C`.

## Plain-water special-case control

**Category:** plain-water beverage special case

The official selector was set to `YES` at `Beverages!B7`; nutrient, FVL, and
NNS inputs in that row were left empty.

| Result | Cell | Observed value |
| --- | --- | --- |
| N | `Beverages!AE7` | `#VALUE!` |
| P | `Beverages!AF7` | `#VALUE!` |
| Raw score | `Beverages!AG7` | `#VALUE!` |
| Official grade metadata | `Beverages!AH7` | `Nutriscore_A` |

The workbook does not assign water a standard numeric raw result. Future code
must preserve a typed special outcome instead of inventing an integer.

## Exact-boundary controls

These values were independently entered into the current official workbook.
Each row records the observable output, not a local reimplementation.

| Component | Input | Points | Location |
| --- | ---: | ---: | --- |
| General energy | `335` | 0 | `General foods!B8 -> K8` |
| General energy | `335.0001` | 1 | `General foods!B8 -> K8` |
| General energy | `670` | 1 | `General foods!B8 -> K8` |
| General sugar | `3.4` | 0 | `General foods!C8 -> AA8` |
| General sugar | `3.4001` | 1 | `General foods!C8 -> AA8` |
| General sugar | `6.8` | 1 | `General foods!C8 -> AA8` |
| General salt | `0.2` | 0 | `General foods!F8 -> Z8` |
| General salt | `0.4` | 1 | `General foods!F8 -> Z8` |
| General protein | `2.4` | 0 | `General foods!J8 -> Y8` |
| General protein | `4.8` | 1 | `General foods!J8 -> Y8` |
| General fiber | `3.0` | 0 | `General foods!I8 -> X8` |
| General fiber | `4.1` | 1 | `General foods!I8 -> X8` |
| Beverage sugar | `0.5` | 0 | `Beverages!D8 -> AD8` |
| Beverage sugar | `2.0` | 1 | `Beverages!D8 -> AD8` |
| Beverage energy | `30` | 0 | `Beverages!C8 -> AB8` |
| Beverage energy | `90` | 1 | `Beverages!C8 -> AB8` |
| Fat ratio | `10%` | 1 | `Fats, oils, nuts and seeds!E8 -> Z8` |
| Fat ratio | `16%` | 2 | `Fats, oils, nuts and seeds!E8 -> Z8` |
| Fat ratio | `64%` | 10 | `Fats, oils, nuts and seeds!E8 -> Z8` |

Exact upper thresholds remain in the lower point band; fat-ratio bands are
lower-inclusive.

## Known official-tool discrepancy control

| Salt input (g/100 mL) | Q&A | Conditions of Use | `Beverages!AC8` | Etiketly methodology |
| ---: | ---: | ---: | ---: | ---: |
| `3.1999` | 15 | 15 | 15 | 15 |
| `3.2` | 15 | 15 | 16 | 15 |
| `3.2001` | 16 | 16 | 16 | 16 |

The raw XLSX formula uses `salt < 3.2` for point 15, followed by
`salt <= 3.4` for point 16. This explains why exact `3.2` is assigned 16 by the
workbook; no conversion or display-rounding step is involved. The March 2025
Sante publique France
[Q&A Table 9](https://www.santepubliquefrance.fr/content/download/150263/file/FAQ-updatedAlgo-EN_20240626.pdf)
and
[Conditions of Use Exhibit 1-B Table 9](https://www.santepubliquefrance.fr/content/download/150258/file/march2025CoU_EN.pdf)
both start point 16 only when `salt > 3.2`. Etiketly therefore follows the
explicit textual rule and assigns exact `3.2` to point 15 while retaining this
workbook result as a known discrepancy fixture.
