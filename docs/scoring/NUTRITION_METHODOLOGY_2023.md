# Updated Nutri-Score 2023 Nutrition Methodology

> **Verification status: VERIFIED.** The March 2025 normative specification and
> current official Q&A agree that beverage salt point 16 begins only above
> `3.2 g/100 mL`; exactly `3.2` receives 15 points. The Belgian FPS workbook has
> a known one-boundary implementation discrepancy, documented below.

## Version and scope

| Field | Value |
| --- | --- |
| Methodology family | Updated Nutri-Score algorithm |
| Solid food update | Scientific Committee 2022 |
| Beverage update | Scientific Committee 2023 |
| Local Etiketly methodology document version | 1 |
| Verification date | 2026-08-08 |

This document describes **only the future NUTRITION component**. It is not the
Etiketly combined score. It does not define additive penalties, additive-risk
weighting, an Etiketly 0-100 transformation, public score UI, or permission to
display an official Nutri-Score grade.

## Official source registry

- **S1 - Solid-food report:** Scientific Committee of the Nutri-Score,
  *Update of the Nutri-Score algorithm - Update report from the Scientific
  Committee of the Nutri-Score*, 2022, voted 29 June 2022. Recap tables and
  formulas: PDF pages 130-134. Official
  [Sante publique France download](https://www.santepubliquefrance.fr/content/download/457252/file/2022-main%20algorithm%20report%20update_FINAL.pdf)
  and accessible official
  [Belgian FPS mirror](https://www.health.belgium.be/sites/default/files/media/files/2025-11/2022-main_algorithm_report_update_final.pdf).
- **S2 - Beverage report:** Scientific Committee of the Nutri-Score,
  *Update of the Nutri-Score algorithm for beverages - Second update report
  from the Scientific Committee of the Nutri-Score*, V2-2023, voted 1 February
  2023. Category recap and tables: PDF pages 72-75. Official
  [Sante publique France publication](https://www.santepubliquefrance.fr/en/node/32929)
  and
  [report PDF](https://www.santepubliquefrance.fr/sites/default/files/rdd/document/Update%20report%20beverages_31%2001%202023-VOTED.pdf),
  with an accessible official
  [Netherlands government mirror](https://www.rijksoverheid.nl/binaries/rijksoverheid/documenten/rapporten/2023/03/30/second-update-report-from-the-scientific-committee-of-the-nutri-score-2023/Update%2Bof%2Bthe%2BNutri-Score%2Balgorithm%2Bfor%2Bbeverages.pdf).
- **S3 - Current Q&A:** *Nutri-Score Questions & Answers*, English version
  dated 17 March 2025 and approved by Sante publique France. General rules:
  pages 11-14; categories: pages 16-20; updated tables/formulas: pages 26-32;
  FVL processing: pages 45-49. Official
  [Sante publique France Q&A PDF](https://www.santepubliquefrance.fr/content/download/150263/file/FAQ-updatedAlgo-EN_20240626.pdf)
  and accessible official
  [Belgian FPS mirror](https://www.health.belgium.be/sites/default/files/media/files/2025-10/va_faq-nutriscore_en.pdf).
- **S3b - Normative specification:** Sante publique France,
  *Conditions of Use of the trademark "Nutri-Score"*, version dated 17 March
  2025, `Exhibit 1-B: Specifications of the Updated Algorithm`, Table 9 on PDF
  page 30. Official
  [Conditions of Use PDF](https://www.santepubliquefrance.fr/content/download/150258/file/march2025CoU_EN.pdf).
- **S4 - Executable verifier:** Belgian FPS Public Health,
  *Nutri-Score calculation tool for the updated algorithm*, XLSX. Official page
  and workbook last updated 24 October 2025. Downloaded filename:
  `va_nutri-score_calculation_tool_updated_algorithm.xlsx`; SHA-256 verified on
  2026-08-08:
  `c80ea768ee8fae68b25e4dc04584d8494e22d632e49cf9763af39c79ca8aa590`.
  Official [tool page](https://www.health.belgium.be/en/tools/nutri-score-calculation-tool)
  and
  [XLSX](https://www.health.belgium.be/sites/default/files/media/files/2025-10/va_nutri-score_calculation_tool_updated_algorithm.xlsx).

Only these official/primary sources were used. Third-party calculators,
repositories, blogs, Yuka, and Open Food Facts are not authorities.

## Known official-tool discrepancy and decision

S3 Table 9 on page 31 and the normative S3b Table 9 on page 30 independently
assign beverage salt point 15 above `3.0` and point 16 above `3.2`. Under strict
mathematical interpretation, exactly `3.2` does not satisfy `> 3.2`; it remains
in the preceding 15-point band. S4 instead uses this condition in every tested
`Beverages` salt cell:

```text
... IF(salt <= 3.0, 14, IF(salt < 3.2, 15,
    IF(salt <= 3.4, 16, ...)))
```

S4 returns 15 at `3.1999`, 16 at exactly `3.2`, and 16 at `3.2001`. The raw
formula and `Beverages!AC8` both confirm that the workbook uses `< 3.2` rather
than `<= 3.2` for point 15. This is a workbook comparison defect, not a
precision conversion or rounding effect.

The local methodology uses this source precedence:

1. Current explicit normative algorithm specification (S3b).
2. Current official methodology Q&A tables (S3).
3. Official calculation workbook as a validation/reference implementation (S4).

The first two sources are concordant, so the local rule is **verified**:
exactly `3.2 g/100 mL` receives 15 points. The workbook discrepancy remains
visible and must be preserved as a regression fixture; it does not override the
two explicit textual rules.

S1 and S3 have a separate publication gap at exactly `335 kJ/100 g`: they print
`< 335` for zero energy points and `> 335` for one point. S4 resolves the
unassigned equality without contradicting an assigned band: `335` returns 0
and `335.0001` returns 1. The general table records that verified behavior.

## Input basis and rounding

Use the nutritional declaration per `100 g` or `100 mL` of product as sold,
except for officially supported prepared-product cases, and use the ingredient
list for FVL/NNS. Printed declaration values are used directly; there is no
special score-rounding rule. For liquid foods, use the unit on the mandatory
declaration; if both units are printed, S3 directs use of `100 g`. Prepared
calculation requires a corresponding per-100-unit declaration and detailed
preparation instructions.

Source: S3 pages 11-14; S4 `Instructions!B18:B35`.

## Calculation groups

- `GENERAL_FOOD`: official default methodology after special groups and
  out-of-scope products have been resolved.
- `CHEESE`: cheeses, processed cheeses, cheese specialties, and expressly
  listed cheese preparations. Quark, plant alternatives, and cheese merely
  incorporated in a composite product are excluded from the special rule.
- `RED_MEAT`: qualifying meat/meat products whose main or first ingredient is
  meat, which act as a dish's meat component, and whose red-meat share is at
  least 20%. Complete dishes and primarily-sauce products are excluded.
- `FATS_OILS_NUTS_SEEDS`: finished animal/vegetable fats and oils, cream,
  margarine, butter, and qualifying nuts/seeds. Processed or mixed nut/seed
  products require a combined share above 50%; chestnuts are excluded. Fat used
  only as a composite-product ingredient does not select this group.
- `BEVERAGE`: water/water-based beverages, juices, nectars, smoothies, milk and
  drinkable milk products, drinkable fermented milk products, coffee cream,
  and plant drinks. Soups/gazpacho remain general foods; culinary coconut milk
  and alcoholic drinks above 1.2% alcohol are excluded.
- Plain bottled mineral, spring, or table water is a beverage special case, not
  a standard numeric beverage calculation.

These definitions do not implement Etiketly resolution. Product names are
never category evidence. Source: S2 page 72; S3 pages 16-20.

## General food negative points

Values are per `100 g`. Exact upper thresholds belong to the lower point band.
Source: S1 page 130 section 1.1; S3 Table 5 page 27; S4 `General foods`
component columns `K`, `M`, `AA`, and `Z`.

| Points | Energy (kJ) | Saturated fat (g) | Sugars (g) | Salt (g) |
| ---: | --- | --- | --- | --- |
| 0 | `<= 335` | `<= 1` | `<= 3.4` | `<= 0.2` |
| 1 | `> 335 and <= 670` | `> 1 and <= 2` | `> 3.4 and <= 6.8` | `> 0.2 and <= 0.4` |
| 2 | `> 670 and <= 1005` | `> 2 and <= 3` | `> 6.8 and <= 10` | `> 0.4 and <= 0.6` |
| 3 | `> 1005 and <= 1340` | `> 3 and <= 4` | `> 10 and <= 14` | `> 0.6 and <= 0.8` |
| 4 | `> 1340 and <= 1675` | `> 4 and <= 5` | `> 14 and <= 17` | `> 0.8 and <= 1.0` |
| 5 | `> 1675 and <= 2010` | `> 5 and <= 6` | `> 17 and <= 20` | `> 1.0 and <= 1.2` |
| 6 | `> 2010 and <= 2345` | `> 6 and <= 7` | `> 20 and <= 24` | `> 1.2 and <= 1.4` |
| 7 | `> 2345 and <= 2680` | `> 7 and <= 8` | `> 24 and <= 27` | `> 1.4 and <= 1.6` |
| 8 | `> 2680 and <= 3015` | `> 8 and <= 9` | `> 27 and <= 31` | `> 1.6 and <= 1.8` |
| 9 | `> 3015 and <= 3350` | `> 9 and <= 10` | `> 31 and <= 34` | `> 1.8 and <= 2.0` |
| 10 | `> 3350` | `> 10` | `> 34 and <= 37` | `> 2.0 and <= 2.2` |
| 11 | - | - | `> 37 and <= 41` | `> 2.2 and <= 2.4` |
| 12 | - | - | `> 41 and <= 44` | `> 2.4 and <= 2.6` |
| 13 | - | - | `> 44 and <= 48` | `> 2.6 and <= 2.8` |
| 14 | - | - | `> 48 and <= 51` | `> 2.8 and <= 3.0` |
| 15 | - | - | `> 51` | `> 3.0 and <= 3.2` |
| 16 | - | - | - | `> 3.2 and <= 3.4` |
| 17 | - | - | - | `> 3.4 and <= 3.6` |
| 18 | - | - | - | `> 3.6 and <= 3.8` |
| 19 | - | - | - | `> 3.8 and <= 4.0` |
| 20 | - | - | - | `> 4.0` |

## General food positive points

Nutrients are per `100 g`; FVL is a percentage. Source: S1 page 130 section
1.2; S3 Table 6 page 28; S4 `General foods!W:Y`.

| Points | Protein (g) | Fiber (g) | FVL (%) |
| ---: | --- | --- | --- |
| 0 | `<= 2.4` | `<= 3.0` | `<= 40` |
| 1 | `> 2.4 and <= 4.8` | `> 3.0 and <= 4.1` | `> 40 and <= 60` |
| 2 | `> 4.8 and <= 7.2` | `> 4.1 and <= 5.2` | `> 60 and <= 80` |
| 3 | `> 7.2 and <= 9.6` | `> 5.2 and <= 6.3` | - |
| 4 | `> 9.6 and <= 12` | `> 6.3 and <= 7.4` | - |
| 5 | `> 12 and <= 14` | `> 7.4` | `> 80` |
| 6 | `> 14 and <= 17` | - | - |
| 7 | `> 17` | - | - |

## General, cheese, and red-meat formulas

Source: S1 pages 131-132 sections 1.2-1.3; S3 pages 17-20 and 28; S4
`General foods!AB:AD`, `Cheese!Z:AB`, and `Red meat!W:AB`.

```text
N = energyPoints + saturatedFatPoints + sugarPoints + saltPoints

GENERAL_FOOD, N < 11:
  raw = N - proteinPoints - fiberPoints - fvlPoints
GENERAL_FOOD, N >= 11:
  raw = N - fiberPoints - fvlPoints

CHEESE, for every N:
  raw = N - proteinPoints - fiberPoints - fvlPoints

RED_MEAT eligible protein:
  appliedProteinPoints = min(calculatedProteinPoints, 2)
RED_MEAT, N < 11:
  raw = N - appliedProteinPoints - fiberPoints - fvlPoints
RED_MEAT, N >= 11:
  raw = N - fiberPoints - fvlPoints
```

General and red-meat protein points are calculated but not applied at `N >=
11`. Red-meat calculation must follow the separate category conditions; it is
not equivalent to a generic red-meat tag.

## Fats, oils, nuts, and seeds

Source: S1 pages 133-134 sections 2.2-2.4; S3 Tables 7-8 and formula on pages
29-30; S4 `Fats, oils, nuts and seeds!E:F,Z:AI`.

```text
energyFromSaturatedFatKj = saturatedFat_g * 37
ratioPercent = 100 * saturatedFat_g / totalFat_g
```

Sugars and salt use the general tables. Protein, fiber, and FVL use the general
positive tables.

| Points | Saturated energy (kJ/100 g) | Sugars (g/100 g) | Saturated/total ratio | Salt (g/100 g) |
| ---: | --- | --- | --- | --- |
| 0 | `<= 120` | `<= 3.4` | `< 10%` | `<= 0.2` |
| 1 | `> 120 and <= 240` | `> 3.4 and <= 6.8` | `>= 10% and < 16%` | `> 0.2 and <= 0.4` |
| 2 | `> 240 and <= 360` | `> 6.8 and <= 10` | `>= 16% and < 22%` | `> 0.4 and <= 0.6` |
| 3 | `> 360 and <= 480` | `> 10 and <= 14` | `>= 22% and < 28%` | `> 0.6 and <= 0.8` |
| 4 | `> 480 and <= 600` | `> 14 and <= 17` | `>= 28% and < 34%` | `> 0.8 and <= 1.0` |
| 5 | `> 600 and <= 720` | `> 17 and <= 20` | `>= 34% and < 40%` | `> 1.0 and <= 1.2` |
| 6 | `> 720 and <= 840` | `> 20 and <= 24` | `>= 40% and < 46%` | `> 1.2 and <= 1.4` |
| 7 | `> 840 and <= 960` | `> 24 and <= 27` | `>= 46% and < 52%` | `> 1.4 and <= 1.6` |
| 8 | `> 960 and <= 1080` | `> 27 and <= 31` | `>= 52% and < 58%` | `> 1.6 and <= 1.8` |
| 9 | `> 1080 and <= 1200` | `> 31 and <= 34` | `>= 58% and < 64%` | `> 1.8 and <= 2.0` |
| 10 | `> 1200` | `> 34 and <= 37` | `>= 64%` | `> 2.0 and <= 2.2` |
| 11 | - | `> 37 and <= 41` | - | `> 2.2 and <= 2.4` |
| 12 | - | `> 41 and <= 44` | - | `> 2.4 and <= 2.6` |
| 13 | - | `> 44 and <= 48` | - | `> 2.6 and <= 2.8` |
| 14 | - | `> 48 and <= 51` | - | `> 2.8 and <= 3.0` |
| 15 | - | `> 51` | - | `> 3.0 and <= 3.2` |
| 16 | - | - | - | `> 3.2 and <= 3.4` |
| 17 | - | - | - | `> 3.4 and <= 3.6` |
| 18 | - | - | - | `> 3.6 and <= 3.8` |
| 19 | - | - | - | `> 3.8 and <= 4.0` |
| 20 | - | - | - | `> 4.0` |

```text
N = saturatedEnergyPoints + sugarPoints + ratioPoints + saltPoints
if N < 7:
  raw = N - proteinPoints - fiberPoints - fvlPoints
if N >= 7:
  raw = N - fiberPoints - fvlPoints
```

## Beverages excluding plain water

Basis is `100 mL` when that is the applicable declaration basis. Saturated fat
uses the general thresholds per `100 mL`. Source: S2 page 73; S3 Table 9 page
31; S4 `Beverages!O,AB,AD:AE`.

| Points | Energy (kJ/100 mL) | Sugars (g/100 mL) | Saturated fat (g/100 mL) | NNS |
| ---: | --- | --- | --- | --- |
| 0 | `<= 30` | `<= 0.5` | `<= 1` | absent |
| 1 | `> 30 and <= 90` | `> 0.5 and <= 2` | `> 1 and <= 2` | - |
| 2 | `> 90 and <= 150` | `> 2 and <= 3.5` | `> 2 and <= 3` | - |
| 3 | `> 150 and <= 210` | `> 3.5 and <= 5` | `> 3 and <= 4` | - |
| 4 | `> 210 and <= 240` | `> 5 and <= 6` | `> 4 and <= 5` | present |
| 5 | `> 240 and <= 270` | `> 6 and <= 7` | `> 5 and <= 6` | - |
| 6 | `> 270 and <= 300` | `> 7 and <= 8` | `> 6 and <= 7` | - |
| 7 | `> 300 and <= 330` | `> 8 and <= 9` | `> 7 and <= 8` | - |
| 8 | `> 330 and <= 360` | `> 9 and <= 10` | `> 8 and <= 9` | - |
| 9 | `> 360 and <= 390` | `> 10 and <= 11` | `> 9 and <= 10` | - |
| 10 | `> 390` | `> 11` | `> 10` | - |

NNS contributes 0 points when absent and 4 when present.

### Beverage salt points

The current textual rule is verified independently by S3 Table 9 on page 31
and the normative S3b Table 9 on page 30. Exact upper thresholds remain in the
lower point band.

| Points | Salt (g/100 mL) |
| ---: | --- |
| 0 | `<= 0.2` |
| 1 | `> 0.2 and <= 0.4` |
| 2 | `> 0.4 and <= 0.6` |
| 3 | `> 0.6 and <= 0.8` |
| 4 | `> 0.8 and <= 1.0` |
| 5 | `> 1.0 and <= 1.2` |
| 6 | `> 1.2 and <= 1.4` |
| 7 | `> 1.4 and <= 1.6` |
| 8 | `> 1.6 and <= 1.8` |
| 9 | `> 1.8 and <= 2.0` |
| 10 | `> 2.0 and <= 2.2` |
| 11 | `> 2.2 and <= 2.4` |
| 12 | `> 2.4 and <= 2.6` |
| 13 | `> 2.6 and <= 2.8` |
| 14 | `> 2.8 and <= 3.0` |
| 15 | `> 3.0 and <= 3.2` |
| 16 | `> 3.2 and <= 3.4` |
| 17 | `> 3.4 and <= 3.6` |
| 18 | `> 3.6 and <= 3.8` |
| 19 | `> 3.8 and <= 4.0` |
| 20 | `> 4.0` |

**Known official-tool discrepancy:** S4 returns 16 for an exact input of
`3.2`, while S3 and S3b specify that 16 points begin only above `3.2`. Etiketly
follows the explicit textual specification, so exact `3.2` receives 15 points.

### Beverage positive points and formula

Fiber uses the general fiber table per `100 mL`. Source: S2 pages 73-74; S3
Table 10 and formula on page 32; S4 `Beverages!Y:AG`.

| Points | Protein (g/100 mL) | Fiber (g/100 mL) | FVL (%) |
| ---: | --- | --- | --- |
| 0 | `<= 1.2` | `<= 3.0` | `<= 40` |
| 1 | `> 1.2 and <= 1.5` | `> 3.0 and <= 4.1` | - |
| 2 | `> 1.5 and <= 1.8` | `> 4.1 and <= 5.2` | `> 40 and <= 60` |
| 3 | `> 1.8 and <= 2.1` | `> 5.2 and <= 6.3` | - |
| 4 | `> 2.1 and <= 2.4` | `> 6.3 and <= 7.4` | `> 60 and <= 80` |
| 5 | `> 2.4 and <= 2.7` | `> 7.4` | - |
| 6 | `> 2.7 and <= 3.0` | - | `> 80` |
| 7 | `> 3.0` | - | - |

```text
N = energyPoints + sugarPoints + saturatedFatPoints + saltPoints + nnsPoints
P = proteinPoints + fiberPoints + fvlPoints
raw = N - P
```

There is no protein suppression.

## Plain-water special case

S2 page 75 reserves the unique top classification for plain water; S3 page 16
repeats the rule. In S4, selecting water with empty nutrient inputs produces
the top reference class while numeric `N`, `P`, and raw cells remain `#VALUE!`.
A future raw calculator must return a typed outcome such as
`plainWaterSpecialCase`, never a fabricated raw integer. This does not authorize
Etiketly to display an official grade.

## Official grade boundaries

> **REFERENCE ONLY - NOT YET IMPLEMENTED IN PRODUCTION.**

Source: S1 pages 132 and 134; S2 page 75; S4 grade columns `General foods!AE`,
`Cheese!AC`, `Red meat!AC`, `Fats, oils, nuts and seeds!AJ`, `Beverages!AH`.

| Group | A | B | C | D | E |
| --- | --- | --- | --- | --- | --- |
| General food | `raw <= 0` | `1..2` | `3..10` | `11..18` | `raw >= 19` |
| Cheese | `raw <= 0` | `1..2` | `3..10` | `11..18` | `raw >= 19` |
| Red meat | `raw <= 0` | `1..2` | `3..10` | `11..18` | `raw >= 19` |
| Fats/oils/nuts/seeds | `raw <= -6` | `-5..2` | `3..10` | `11..18` | `raw >= 19` |
| Beverage except water | unavailable | `raw <= 2` | `3..6` | `7..9` | `raw >= 10` |
| Plain water | special top classification | - | - | - | - |

## FVL input semantics

FVL is the qualifying fruit, vegetable, and legume proportion. Updated general
FVL does not automatically include nuts or the original oil set. In the fats
category only, oils from the whole edible part of a qualifying FVL ingredient
may count (official examples: olive, avocado, soybean; not grapeseed).

The percentage comes from the ingredient formulation/list basis. Vague presence
does not establish a percentage; explicit recipe/QUID percentages may support
evidence. Known absence and unknown differ. Composite ingredients must be in
the same raw/cooked state.

S3 pages 45-48 adds these implementation-relevant rules:

- Intact/minimally processed qualifying ingredients can count, including
  cooked, peeled, sliced, tinned, frozen, pureed, pulped, grilled, roasted, or
  marinated forms.
- Concentrated fruit-juice sugars, powders, freeze-dried products, candied
  fruit, and water-loss flours do not count.
- Fruit juice from concentrate may count after 100% reconstitution; an
  unreconstituted concentrated fruit juice or puree does not.
- Qualifying dried FVL and concentrated vegetables/legumes use a factor of 2:

```text
FVL% = 100 * (freshFvlWeight + 2 * driedOrConcentratedFvlWeight)
       / (freshFvlWeight + 2 * driedOrConcentratedFvlWeight
          + nonFvlWeight)
```

The factor is independent of concentration and is applied before
reconstitution. Product names are never evidence. Source: S1 pages 131 and
134; S3 pages 13 and 45-49; S4 `Eurocodes` and `Instructions!B35:B39`.

## NNS component

NNS is beverage-only: absent is 0 points and present is 4. The scoring-specific
identifier resource is versioned `nutri-score-2023.1`. Nutrition NNS impact is
not future additive-risk impact and creates no additive penalty. Source: S2
pages 73-74; S3 pages 31-32 and Appendix 3 page 58; S4
`Non-nutritive sweeteners` and `Beverages!H,AE`.

## Independently verified boundaries

Values below were entered into S4 on 2026-08-08 without changing/saving the
workbook. See [OFFICIAL_REFERENCE_FIXTURES_2023.md](OFFICIAL_REFERENCE_FIXTURES_2023.md).

| Component | Input | Points | Location |
| --- | ---: | ---: | --- |
| General energy | `335` | 0 | `General foods!B8 -> K8` |
| General energy | `335.0001` | 1 | `General foods!B8 -> K8` |
| General sugar | `3.4` | 0 | `General foods!C8 -> AA8` |
| General sugar | `3.4001` | 1 | `General foods!C8 -> AA8` |
| General sugar | `6.8` | 1 | `General foods!C8 -> AA8` |
| General salt | `0.2` | 0 | `General foods!F8 -> Z8` |
| General salt | `0.4` | 1 | `General foods!F8 -> Z8` |
| General protein | `2.4` | 0 | `General foods!J8 -> Y8` |
| General protein | `4.8` | 1 | `General foods!J8 -> Y8` |
| General fiber | `3.0` | 0 | `General foods!I8 -> X8` |
| General fiber | `4.1` | 1 | `General foods!I8 -> X8` |
| Beverage energy | `30` | 0 | `Beverages!C8 -> AB8` |
| Beverage energy | `90` | 1 | `Beverages!C8 -> AB8` |
| Beverage sugar | `0.5` | 0 | `Beverages!D8 -> AD8` |
| Beverage sugar | `2.0` | 1 | `Beverages!D8 -> AD8` |
| Fats ratio | `10%` | 1 | `Fats, oils, nuts and seeds!E8 -> Z8` |
| Fats ratio | `16%` | 2 | `Fats, oils, nuts and seeds!E8 -> Z8` |
| Fats ratio | `64%` | 10 | `Fats, oils, nuts and seeds!E8 -> Z8` |

Source: S4 cells above. Exact upper thresholds stay in the lower band; ratio
bands are lower-inclusive. The known workbook-discrepancy probe is:

| Beverage salt | S3 Q&A | S3b Conditions | S4 workbook | Local decision |
| ---: | ---: | ---: | ---: | ---: |
| `3.1999` | 15 | 15 | 15 | 15 |
| `3.2` | 15 | 15 | 16 | 15 |
| `3.2001` | 16 | 16 | 16 | 16 |

## Canonical implementation checklist

> This is a transcription-review checklist, not code.

Source: S1 pages 130-134; S2 pages 73-75; S3 Tables 5-10 pages 27-32; S3b
Exhibit 1-B Tables 5-10 pages 27-31; S4 boundary and fixture verification above.

- General energy upper thresholds, points 0-9:
  `[335, 670, 1005, 1340, 1675, 2010, 2345, 2680, 3015, 3350]`; above -> 10.
- General saturated-fat upper thresholds, points 0-9:
  `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]`; above -> 10.
- General sugar upper thresholds, points 0-14:
  `[3.4, 6.8, 10, 14, 17, 20, 24, 27, 31, 34, 37, 41, 44, 48, 51]`; above -> 15.
- General salt upper thresholds, points 0-19:
  `[0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.2, 3.4, 3.6, 3.8, 4.0]`; above -> 20.
- General protein upper thresholds, points 0-6:
  `[2.4, 4.8, 7.2, 9.6, 12, 14, 17]`; above -> 7.
- General fiber upper thresholds, points 0-4:
  `[3.0, 4.1, 5.2, 6.3, 7.4]`; above -> 5.
- General FVL: `<=40:0`, `>40..60:1`, `>60..80:2`, `>80:5`.
- General subtracts protein only for `N < 11`; cheese always subtracts it.
- Red meat caps eligible protein at 2 and suppresses it at `N >= 11`.
- Fats saturated-energy upper thresholds, points 0-9:
  `[120, 240, 360, 480, 600, 720, 840, 960, 1080, 1200]`; above -> 10.
- Fats ratio: `<10:0`; lower thresholds
  `[10, 16, 22, 28, 34, 40, 46, 52, 58, 64]` start points 1-10.
- Fats use `saturatedFat * 37`, general sugar/salt/positives, and subtract
  protein only for `N < 7`.
- Beverage energy upper thresholds, points 0-9:
  `[30, 90, 150, 210, 240, 270, 300, 330, 360, 390]`; above -> 10.
- Beverage sugar upper thresholds, points 0-9:
  `[0.5, 2, 3.5, 5, 6, 7, 8, 9, 10, 11]`; above -> 10.
- Beverage saturated fat uses the general table per applicable 100 mL basis.
- Beverage salt upper thresholds, points 0-19:
  `[0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6, 2.8, 3.0, 3.2, 3.4, 3.6, 3.8, 4.0]`; above -> 20. Exact `3.2` -> 15.
- S4 workbook exception: exact beverage salt `3.2` incorrectly returns 16;
  preserve this as a known tool-discrepancy regression case.
- Beverage NNS: absent 0; present 4.
- Beverage protein upper thresholds, points 0-6:
  `[1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0]`; above -> 7.
- Beverage fiber uses the general fiber table; FVL is `<=40:0`,
  `>40..60:2`, `>60..80:4`, `>80:6`.
- Beverage uses `raw = N - protein - fiber - FVL`; no protein suppression.
- Plain water is a typed special case, never a fabricated integer.
- Official grade boundaries are reference metadata only.
