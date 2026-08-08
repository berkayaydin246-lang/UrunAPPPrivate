# Etiketly Score UI v1

## Scope

Phase 2B-9 exposes the existing deterministic Etiketly Score v1 on normal
Product Detail only. Search, category lists, comparison, submissions, and admin
screens do not show a public score in this phase. No score value is persisted or
cached in the database.

The UI does not implement scoring mathematics. A single Riverpod-backed
orchestration path consumes the loaded `Product`, persisted scoring evidence,
and the existing Product Detail canonical ingredient assessment. It then calls,
in order:

```text
ScoringReadinessEvaluator
NutritionRawScoreCalculator
NutritionQualityTransformer
AdditiveQualityTransformer
EtiketlyScoreReadinessEvaluator
EtiketlyScoreCalculator
EtiketlyScorePresentationMapper
```

The existing `productAnalysisProvider` remains the canonical matching pipeline.
The score provider watches that memoized result instead of parsing and matching
the ingredient list again.

## Public score card

A calculated card displays:

- the rounded Etiketly Score and `/100`
- a textual content-profile label
- unweighted nutrition-quality and additive-quality component values
- a deterministic canonical-additive summary
- an NNS overlap note when the beverage methodology already represents the
  qualifying sweetener signal

Weighted component contributions are not shown in the primary experience. The
internal score and both components retain `double` precision throughout the
calculation. Only the final score is rounded for public display with Dart
`round()`. Component rounding is display-only and occurs after final
calculation.

## Public label bands

The following bands are presentation semantics only. They do not alter the
formula, component values, readiness, or final score:

| Display score | Label |
| --- | --- |
| 80-100 | Çok iyi |
| 60-79 | İyi |
| 40-59 | Orta |
| 20-39 | Zayıf |
| 0-19 | Çok zayıf |

Band colour is always paired with the numeric value and text label. Colours use
muted app-native semantic tones and are not medical warning classifications.

## Formula transparency

The methodology sheet states that verified nutrition quality has `80%` weight
and canonical additive assessment has `20%` weight. These values are disclosure
text only in the widget. `EtiketlyScoreCalculator` remains the sole production
formula authority.

The internal version `etiketly_score_v1` is retained in the presentation state
for diagnostics and tests but is not displayed to normal users.

## Deterministic explanations

The score card describes component qualities, not weighted contribution values.
Canonical additive counts are deduplicated and include only eligible reviewed
low, medium, or high classifications. Ordinary ingredients, unresolved tokens,
fuzzy matches, conflicts, and unknown risks do not receive invented penalties.

A qualifying beverage NNS may remain visible in ingredient details. When its
numeric additive effect is excluded to prevent overlap, the card says:

```text
Tatlandırıcı etkisi beslenme bileşeninde hesaba katıldı.
```

No AI-generated copy or user vote participates in the explanation or score.

## Unavailable and error states

Final readiness is a strict gate. A numeric score, including zero, appears only
for a calculated domain result. An unavailable, loading, or error state never
uses `0`, `--`, `NaN`, or `null` as a placeholder. A calculated `0/100` remains
a valid real score.

The public blocker mapper translates typed readiness reasons into at most three
short Turkish messages. It prioritizes basis, missing fiber or nutrition,
category, ingredient completeness, composition evidence, and additive review
gaps. Enum names, serialized evidence, database messages, stack traces, and raw
network exceptions are never shown.

An unexpected scoring failure is isolated from the rest of Product Detail. The
card displays `Puan şu anda hesaplanamadı.` while technical details are logged
only in debug builds. Ingredients, nutrition, existing analysis, comparison,
and reporting remain available.

## Accessibility and responsive behavior

The calculated card exposes a semantic summary equivalent to the score, content
profile label, and both component qualities. Loading, unavailable, and error
states have explicit non-numeric semantic labels. The methodology affordance
remains independently accessible.

The header wraps on narrow screens, score and label content use a wrapping
layout, and component cards stack on narrow widths or large text scales. Widget
coverage includes a 320 logical-pixel width and 2x text scaling.

## Interpretation and legacy behavior

Etiketly Score is a deterministic content-profile presentation. It is not a
medical assessment, health or safety percentage, disease-risk probability, or
personal nutrition recommendation.

Legacy products and products with incomplete evidence continue to render normal
Product Detail content. They receive the unavailable score card without any
fabricated evidence or fallback number.

## Catalogue coverage snapshot

No safe local catalogue snapshot currently combines persisted scoring evidence,
complete ingredient text, and the canonical ingredient catalogue needed for an
honest coverage count. Production was not queried for this phase and no coverage
percentage is claimed.

A future coverage run must use this controlled read-only process:

1. An authorized operator uses a database role restricted to `SELECT` and
   exports only the required product scoring-evidence fields plus canonical
   ingredient catalogue fields.
2. The export is stored outside the repository and contains no auth tokens,
   user data, environment values, or service-role credentials.
3. A local analysis tool consumes the explicitly supplied snapshot, runs this
   same orchestration boundary, and reports calculated/unavailable counts plus
   grouped public blocker categories.
4. The tool performs no network calls and no writes; the snapshot and report are
   reviewed locally and are not committed unless deliberately sanitized.

Catalogue coverage is therefore expected to be partial at initial beta and can
be measured only after that snapshot process is implemented and reviewed.
