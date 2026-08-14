# Etiketly Additive Risk Methodology V1 Proposal

- Status: **proposal only**
- Evidence cut-off: **2026-08-14**
- Runtime/catalogue effect: **none**

This document proposes a deterministic method for assigning the canonical
Etiketly additive tiers `low`, `medium`, `high`, and `unknown`. It does not
change any catalogue row, score formula, additive-quality penalty, nutrition
methodology, or final-score weight.

## 1. Why This Methodology Is Needed

The existing implementation defines two later parts of the pipeline, but not
the scientific classification step:

- `ADDITIVE_ASSESSMENT_FOUNDATION.md` deterministically reconciles database
  and reviewed-local tier values. It correctly turns a disagreement into
  `unknown`, but it does not define how official evidence becomes a tier.
- `ADDITIVE_QUALITY_TRANSFORM_V1.md` assigns presence-based impacts of `2`,
  `9`, and `24` to reviewed low, medium, and high canonical identities. It
  explicitly states that these are not toxicity probabilities or a clinical
  dose-response model.
- `CanonicalIngredientRiskService` applies the reconciliation policy. It does
  not interpret EFSA, European Commission, JECFA, or IARC findings.

Consequently, the current catalogue's tier labels cannot be reproduced from a
documented evidence-to-tier rule. The conflicts for E202 and E471, and the
unknown tier for E282, are valid fail-closed outcomes of that omission.

## 2. Meaning Of An Etiketly Tier

An Etiketly additive tier is an **additive-specific evidence attention tier**.
It summarizes the latest applicable official hazard, exposure, uncertainty,
specification, special-population, and risk-management findings for a
canonical food additive.

It is not:

- a declaration that a product is safe or unsafe;
- a probability that a consumer will be harmed;
- a replacement for an ADI/TDI or an exposure assessment;
- a statement about the amount of the additive in a particular product;
- a consequence of EU authorization, an E-number, or additive function alone;
- a nutrition-quality classification.

Etiketly currently observes additive presence, not product-level additive
quantity. The tier therefore controls only the existing presence-based
additive-quality component. Public wording must continue to avoid converting
the tier into individualized medical or dose advice.

### Tier semantics

| Tier | Deterministic meaning |
| --- | --- |
| `low` | The latest applicable official assessment reaches a current-use no-concern conclusion, and no material open modifier below applies. |
| `medium` | A usable current-use assessment exists, but an official material exposure, uncertainty, specification, use-condition, or population-specific modifier requires additional attention. |
| `high` | An official current-use concern, strong applicable hazard-plus-exposure trigger, or mandatory adverse-effect warning meets a high rule below. |
| `unknown` | The evidence is insufficient, conflicting, inapplicable, or too incomplete to assign a tier without inventing a conclusion. `unknown` is not a neutral or low tier. |

## 3. Evidence Record Required Before Classification

Every reviewed canonical identity must retain these fields independently:

1. Canonical identity, E-code, salts/group scope, and intended food-additive
   use.
2. Current EU authorization and specification status.
3. Latest applicable EFSA opinion and any later EFSA follow-up opinion.
4. JECFA conclusion when EFSA is absent, older, or when JECFA supplies a
   compatible later assessment.
5. IARC classification only where the classified agent and exposure route are
   applicable to the additive identity.
6. Genotoxicity and carcinogenicity conclusions.
7. Permanent, temporary, withdrawn, unnecessary, or unavailable ADI/TDI and
   the reason for that status.
8. Refined mean and high-percentile exposure relative to the health-based
   guidance value for every assessed population.
9. Officially identified data gaps, uncertainty, special-population findings,
   impurity/specification concerns, and requested follow-up.
10. Later European Commission measures that close, control, or leave those
    findings open.
11. Evidence cut-off date, reviewer, exact rule IDs, and confidence.

Authorization is recorded but never used as a shortcut for `low`. Likewise,
the existence or absence of a numerical ADI is not itself a tier: EFSA may
decide that a numerical ADI is unnecessary on an adequate evidence basis.

## 4. Source Hierarchy And Scope Resolution

Apply sources in this order:

1. The latest applicable EFSA food-additive opinion or follow-up opinion.
2. Current European Commission legislation for authorization, warnings,
   restrictions, specifications, and whether requested controls were adopted.
3. JECFA/WHO when EFSA has not assessed the issue, or as a compatible later
   food-additive risk assessment.
4. IARC only for an applicable carcinogenic-hazard finding. IARC hazard
   identification and EFSA/JECFA dietary risk assessment are complementary,
   not interchangeable.

A newer source supersedes an older source only for the same identity, use,
population, and endpoint that it explicitly revisits. A later Commission limit
can close an impurity-control action, but authorization alone cannot erase an
unresolved scientific finding.

Two official conclusions are a conflict only if they address the same identity,
scope, endpoint, and evidence period and cannot be reconciled by those scope
rules. A hazard classification and an exposure-based risk conclusion are not,
by themselves, a conflict.

## 5. Deterministic Decision Rules

Evaluate the rules in the order below. Stop at the first applicable outcome,
except that a later source may first close an older follow-up item under the
source hierarchy.

### Step 0: identity and scope gate

Return `unknown` under rule `U0` if the canonical identity, E-code/group scope,
or food-additive use cannot be established from authoritative material.

### Step 1: explicit high findings

Return `high` when any rule applies:

- `H1` - The latest applicable EFSA/JECFA conclusion or current EU action says
  the additive is unsafe, is of safety concern, or must be suspended/removed
  for safety at authorized or reported uses.
- `H2` - Refined **mean** additive exposure exceeds the applicable ADI/TDI for
  any assessed population, unless the authority explicitly concludes that the
  exceedance is not a health concern for a stated methodological reason.
- `H3` - IARC classifies the applicable agent/exposure circumstance as Group 1
  or 2A, and an applicable EFSA/JECFA/Commission assessment confirms that the
  relevant exposure or mechanistic pathway can occur from the food-additive
  use. An IARC class alone is insufficient.
- `H4` - Current EU law requires an additive-specific label warning about a
  possible adverse health or behavioural effect.
- `H5` - A genotoxic/carcinogenic concern is identified and the applicable
  authority expressly concludes that current uses raise a concern. If the
  authority cannot conclude instead, use `unknown` under `U2`.

### Step 2: evidence too incomplete to tier

Return `unknown` when any rule applies and no explicit `high` rule already did:

- `U1` - No current, applicable EFSA/JECFA food-additive assessment or
  equivalent official conclusion exists.
- `U2` - A critical endpoint, including genotoxicity, cannot be assessed and
  the authority cannot reach a current-use conclusion.
- `U3` - Exposure cannot be compared with a required ADI/TDI and no official
  alternative margin/current-use conclusion is available.
- `U4` - Applicable official sources conflict on the same endpoint and scope,
  with no later review resolving the conflict.
- `U5` - An open data gap is broad enough that the authority cannot conclude
  for the additive's general authorized uses, rather than only a defined
  population or condition.

### Step 3: material attention modifiers

Return `medium` when any rule applies and neither `high` nor `unknown` did:

- `M1` - A temporary/provisional ADI/TDI is in force or a follow-up study is
  required before it can become permanent.
- `M2` - Refined high-percentile exposure reaches or exceeds the ADI/TDI in any
  assessed population while mean exposure remains below it.
- `M3` - The authority reaches a usable general/current-use conclusion but
  cannot demonstrate safety for a defined authorized use, processing
  condition, vulnerable population, or other bounded scope.
- `M4` - The authority identifies an impurity/specification issue with a
  plausible toxicological concern and requests a control that is not yet
  effective in current EU specifications.
- `M5` - IARC classifies the applicable additive identity as Group 2B, while
  EFSA/JECFA retains a current-use no-concern conclusion or ADI. This records
  the hazard signal without treating it as exposure-based proof of harm.
- `M6` - The authority identifies additive-specific sensitivity or intolerance
  at or below the ADI, but no current EU warning or broader concern triggers a
  high rule.
- `M7` - A current risk-management measure materially restricts exposure for a
  stated safety concern, but the applicable official assessment still supports
  use under those controls.

A gap is material only when an official conclusion, recommendation, or formal
call for data says it could affect hazard characterization, exposure, a
vulnerable population, or control of a toxicologically relevant impurity.
Editorial, analytical, identity, or specification refinements that the
authority says do not affect the safety conclusion are not material by
themselves.

### Step 4: low criteria

Return `low` under rule `L1` only when all are true:

- the latest applicable authority concludes no safety concern at authorized or
  reported uses;
- genotoxicity/carcinogenicity concerns have been excluded on the available
  evidence, found inapplicable, or otherwise incorporated into that explicit
  conclusion;
- a permanent ADI/TDI exists and refined mean/high-percentile exposure is below
  it for all assessed populations, **or** the authority concludes that a
  numerical ADI/TDI is unnecessary on an adequate basis;
- no `H`, `U`, or `M` rule remains open; and
- any older material specification/follow-up issue has been closed by a later
  applicable opinion or an effective EU control.

## 6. Confidence Is Separate From Tier

Confidence must not raise or lower the tier. Record it separately:

| Confidence | Required provenance |
| --- | --- |
| `high` | Exact identity plus a current EFSA assessment/follow-up and current EU status; relevant endpoints and exposure are directly addressed. |
| `medium` | Exact identity and a usable official assessment exist, but it is older, group/read-across based, or a bounded uncertainty remains without changing the tier rule. |
| `low` | The tier relies mainly on JECFA or indirect official evidence because no applicable EFSA assessment exists. A second review is mandatory. |

## 7. Proposed Application To E202, E471, And E282

These are report-only outcomes. They are not catalogue changes.

### E202 - potassium sorbate: proposed `low`

**Primary evidence**

- EFSA Journal 2019;17(3):5625 replaced the temporary group ADI with a group
  ADI of 11 mg sorbic acid/kg bw/day for E200/E202 after reviewing the requested
  reproductive study. The realistic non-brand-loyal exposure did not exceed
  that ADI.
- Commission Regulation (EU) 2024/2597 subsequently revised E200/E202 uses and
  specifications, including lower toxic-element limits and an E202 zinc limit.
- The unresolved calcium-sorbate evidence discussed in the group history does
  not transfer an unknown result to the separately identified E202.

**Decision**

- Rule: `L1`.
- Important uncertainty: older stability questions were not re-assessed in the
  2019 follow-up, but no current applicable authority uses that point to withhold
  the E202 current-use conclusion; later EU specifications are effective.
- Confidence: `high`.
- Provenance: EFSA DOI `10.2903/j.efsa.2019.5625`; Commission Regulation (EU)
  2024/2597.

### E471 - mono- and diglycerides of fatty acids: proposed `low`

**Primary evidence**

- EFSA Journal 2017;15(11):5045 found no indication of genotoxic,
  carcinogenic, or reproductive toxicity, found no need for a numerical ADI,
  and reached a no-concern conclusion at reported uses and levels. It requested
  tighter controls for toxic elements, 3-MCPD/glycidyl esters, erucic acid,
  trans fats, solvents, and related manufacturing impurities.
- EFSA Journal 2021;19(11):6885 retained the no-concern conclusion, including
  the assessed infant-food uses, while again recommending specification
  controls. It found no need for a solvent limit on the submitted manufacturing
  information and noted that the general EU trans-fat limit already protects
  finished foods.
- Commission Regulation (EU) 2023/1428 implemented lower toxic-element limits
  and limits for erucic acid, 3-MCPD/esters, and glycidyl esters, with stricter
  controls for infant and young-child foods. The transitional periods have
  expired.

**Decision**

- Rule: `L1`; the older `M4` candidate is closed by the 2021 follow-up and
  effective 2023 controls.
- Important uncertainty: E471 is a mixture and manufacturing quality remains
  relevant, but the current regulated specification addresses the material
  impurities identified in the applicable opinions.
- Confidence: `high`.
- Provenance: EFSA DOI `10.2903/j.efsa.2017.5045`, EFSA DOI
  `10.2903/j.efsa.2021.6885`; Commission Regulation (EU) 2023/1428.

### E282 - calcium propionate: proposed `low`

**Primary evidence**

- EFSA Journal 2014;12(7):3779 evaluated E280-E283. It found no genotoxic or
  carcinogenic concern and no systemic effect in the available studies.
- EFSA did not omit a numerical ADI merely because evidence was unavailable.
  It considered a numerical ADI unnecessary because the relevant observed
  effect was local irritation at the first contact site.
- The concentration producing that effect was about three times the highest
  permitted food concentration, and EFSA concluded that authorized uses and
  levels were not a safety concern.
- EFSA Journal 2016;14(8):4546 later retained the group assessment while
  evaluating an E281 extension; it did not identify a contrary E282 finding.

**Decision**

- Rule: `L1`. “No numerical ADI needed” is not `M1` or `U3` when the authority
  supplies an adequate alternative basis and an explicit current-use
  conclusion.
- Important uncertainty: the dedicated group opinion is older and contains
  some toxicology-database limitations, but those limitations did not prevent
  the official conclusion.
- Confidence: `medium` because the dedicated E282 evidence is group-based and
  dates to 2014, not because the proposed tier is uncertain.
- Provenance: EFSA DOI `10.2903/j.efsa.2014.3779`; corroborating scope context
  in EFSA DOI `10.2903/j.efsa.2016.4546`.

## 8. Ten-Additive Sanity Sample

The sample was selected before assigning the target outcomes and spans the
current static catalogue's low, medium, and high tiers. It deliberately excludes
E202, E471, and E282.

| Additive | Current | Proposal | Rule | Official evidence test | Result |
| --- | --- | --- | --- | --- | --- |
| E322 lecithins | low | **low** | `L1` | EFSA 2017 found no need for a numerical ADI/no concern; the 2020 infant and follow-up opinion found no concern up to the infant-formula MPL and supported specification updates. | agree |
| E412 guar gum | low | **medium** | `M3` | EFSA 2024 retained the general assessment but found submitted data insufficient to demonstrate safety for specified infant/young-child food categories. | **disagree** |
| E415 xanthan gum | low | **low** | `L1` | EFSA 2017 found no need for a numerical ADI/no concern for the general population; EFSA 2023 found no concern for assessed infant formula use up to 1,200 mg/L. | agree |
| E211 sodium benzoate | medium | **medium** | `M2` | EFSA 2016 derived a group ADI of 5 mg/kg bw/day; high brand-loyal exposure exceeded it for toddlers/children, with further carry-over exposure possible. | agree |
| E950 acesulfame K | medium | **medium** | `M4` | EFSA 2025 set an ADI of 15 mg/kg bw/day and found P95 generally below it/no current-use concern, but identified a genotoxicity concern for 5-chloro-acesulfame and requested a specification limit or data. | agree |
| E955 sucralose | medium | **medium** | `M3` | EFSA 2026 retained the 15 mg/kg bw/day ADI and found current-use exposure below it, but could not conclude on a bakery extension and requested attention to unwanted high-temperature degradation products in domestic frying/baking. | agree |
| E951 aspartame | high | **medium** | `M5` | EFSA 2013 and JECFA 2023 retained a 40 mg/kg bw/day ADI/no current-exposure concern; IARC 2023/2024 classified the hazard as Group 2B on limited evidence. | **disagree** |
| E102 tartrazine | high | **high** | `H4` | EFSA retained its ADI and recent EU monitoring found exposure below it, but EFSA also identified intolerance in a small sensitive fraction and EU Annex V requires the child activity/attention warning. | agree |
| E110 Sunset Yellow | high | **high** | `H4` | EFSA 2014 established a permanent ADI of 4 mg/kg bw/day with exposure below it; EU Annex V nevertheless requires the child activity/attention warning. | agree |
| E250 sodium nitrite | high | **high** | `H3` | EFSA 2017 found slight high-percentile ADI exceedance in children, evidence linking dietary nitrite with some cancers, and nitrosamine uncertainty; IARC classifies ingested nitrite under endogenous-nitrosation conditions as Group 2A, and EU 2023/2108 reduced permitted additions to minimize nitrosamines. | agree |

Outcome: **8 agreements and 2 disagreements**. The proposed method is not a
mechanism for preserving all existing tiers. It identifies E412 as understated
and E951 as overstated under one common rule set, while independently placing
the three 7 Days additives in `low`.

## 9. Effect On The 7 Days Case

Current read-only diagnostics for `7 Days Çilekli Kruvasan 60 G`
(`16dc5dac-4f37-4072-8e98-c2556ff76adf`) show:

- source-backed FVL is 5.5%;
- generic flavouring wording is outside additiveQuality scope;
- E202 has a database `low` versus reviewed-local `medium` conflict;
- E471 has a database `low` versus reviewed-local `medium` conflict;
- E282 resolves canonically but its reviewed risk is `unknown`;
- the remaining blockers are canonical additive incompleteness, risk conflict,
  and unknown risk.

If this proposal were separately approved and then applied consistently to all
canonical sources, E202, E471, and E282 would each be `low`. The two conflicts
and E282 unknown would disappear. With the already verified evidence unchanged,
the product would become `final_score_ready`.

That is a conditional impact statement, not a current runtime result. This
methodology task does not alter the database, reviewed catalogue, evidence,
snapshot, or product score.

## 10. Required Review Workflow Before Any Catalogue Change

1. A reviewer records the evidence fields in Section 3 and identifies the
   latest applicable scope.
2. The reviewer applies rule IDs in order and records the first result.
3. A second reviewer repeats the decision without seeing the proposed tier.
4. Disagreement about facts or scope yields `unknown` until resolved; reviewers
   must not average tiers.
5. A catalogue change must update every reconciled source atomically or stage
   them so runtime never sees a known-value conflict.
6. Existing canonical matching, deduplication, readiness, audit fingerprint,
   and score tests must run before rollout.
7. A new EFSA/JECFA/IARC opinion or relevant EU measure reopens the record; it
   does not silently change historical audit snapshots.

## 11. Primary Sources

### Framework and law

- [Regulation (EC) No 1333/2008 on food additives](https://eur-lex.europa.eu/eli/reg/2008/1333/oj/eng)
- [EFSA scientific assessment methodology and guidance](https://www.efsa.europa.eu/en/methodology/guidance)

### Target additives

- [EFSA 2019 E200/E202 follow-up, DOI 10.2903/j.efsa.2019.5625](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2019.5625)
- [Commission Regulation (EU) 2024/2597, E200/E202 uses and specifications](https://eur-lex.europa.eu/eli/reg/2024/2597/oj/eng)
- [EFSA 2017 E471 re-evaluation, DOI 10.2903/j.efsa.2017.5045](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2017.5045)
- [EFSA 2021 E471 infant/follow-up opinion, DOI 10.2903/j.efsa.2021.6885](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2021.6885)
- [Commission Regulation (EU) 2023/1428, E471 specifications](https://eur-lex.europa.eu/eli/reg/2023/1428/oj/eng)
- [EFSA 2014 E280-E283 re-evaluation, DOI 10.2903/j.efsa.2014.3779](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2014.3779)
- [EFSA 2016 E281 extension opinion, DOI 10.2903/j.efsa.2016.4546](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2016.4546)

### Sanity sample

- [EFSA 2020 E322 infant/follow-up opinion, DOI 10.2903/j.efsa.2020.6266](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2020.6266)
- [EFSA 2024 E412 infant/follow-up opinion, DOI 10.2903/j.efsa.2024.8748](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2024.8748)
- [EFSA 2023 E415 infant/follow-up opinion, DOI 10.2903/j.efsa.2023.7951](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2023.7951)
- [EFSA 2016 E210-E213 re-evaluation, DOI 10.2903/j.efsa.2016.4433](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2016.4433)
- [EFSA 2025 E950 re-evaluation, DOI 10.2903/j.efsa.2025.9317](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2025.9317)
- [EFSA 2026 E955 re-evaluation, DOI 10.2903/j.efsa.2026.9854](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2026.9854)
- [EFSA 2013 E951 re-evaluation, DOI 10.2903/j.efsa.2013.3496](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2013.3496)
- [WHO/JECFA 2023 aspartame evaluation](https://www.who.int/publications/i/item/9789240083059)
- [IARC Monographs Volume 134: aspartame](https://publications.iarc.who.int/Book-And-Report-Series/Iarc-Monographs-On-The-Identification-Of-Carcinogenic-Hazards-To-Humans/Aspartame-Methyleugenol-And-Isoeugenol-2024)
- [EFSA 2009 E102 re-evaluation, DOI 10.2903/j.efsa.2009.1331](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2009.1331)
- [EFSA 2014 E110 follow-up, DOI 10.2903/j.efsa.2014.3765](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2014.3765)
- [Regulation (EC) No 1333/2008 Annex V warning list](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32008R1333)
- [EFSA 2017 E249/E250 re-evaluation, DOI 10.2903/j.efsa.2017.4786](https://efsa.onlinelibrary.wiley.com/doi/10.2903/j.efsa.2017.4786)
- [IARC Monographs Volume 94: ingested nitrate and nitrite](https://publications.iarc.who.int/Book-And-Report-Series/Iarc-Monographs-On-The-Identification-Of-Carcinogenic-Hazards-To-Humans/Ingested-Nitrate-And-Nitrite-And-Cyanobacterial-Peptide-Toxins-2010)
- [Commission Regulation (EU) 2023/2108, nitrite/nitrate controls](https://eur-lex.europa.eu/eli/reg/2023/2108/oj/eng)

## 12. Proposal Boundary

Approval of this document would approve only the classification methodology.
Actual tier changes require a separate reviewed catalogue patch, conflict-safe
deployment plan, regression tests, and score/audit impact report. Historical
audit snapshots must remain immutable.
