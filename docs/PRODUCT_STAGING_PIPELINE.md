# Product Staging Pipeline

## Why staging exists

We are building a Yuka-like food analyzer for packaged food products in Turkey.
External product data (Open Food Facts today; Migros/Trendyol later) is
**inconsistent in quality**: missing nutrition, English-only names, junk
fragments like `– 34g` / `–20₺`, wrong categories.

If we wrote that data straight into the clean `products` catalog, the app's
search, category browse, and analysis would all degrade.

So every external/manual/user-submitted **candidate** first lands in a holding
table — `product_staging` — where it is:

1. quality-scored deterministically (no AI),
2. assigned a review status,
3. reviewed (and later promoted to `products`) by an admin.

Nothing in `product_staging` is shown to end users.

---

## product_staging vs products

| | `products` | `product_staging` |
|---|---|---|
| Purpose | Clean, user-facing catalog | Raw candidates awaiting review |
| Shown to users | Yes | No |
| Data quality | Verified / curated | Mixed, unverified |
| barcode uniqueness | `barcode` is UNIQUE | NOT unique (multi-source) |
| Written by | App flows + admin approval | Connectors / seed / submissions |
| Source tracking | minimal (`source`, `source_url`) | full per-field provenance |

## product_staging vs product_submissions

| | `product_submissions` | `product_staging` |
|---|---|---|
| Origin | End-user photo submission of a missing barcode | Any candidate source (OFF, seed, market, later: submissions) |
| Contents | Front/label photos + OCR extraction | Normalized candidate fields + quality score |
| Flow | Existing admin approval → `products` | New staging review → `products` (later task) |
| Status in this task | **Unchanged** | New foundation |

`product_submissions` is **not modified, migrated, or deleted** in this task.

> **Future work**
> - `product_submissions` rows can be converted into `product_staging`
>   candidates.
> - A single unified admin queue can later review both sources.

---

## ProductCandidate standard

`lib/features/product_staging/models/product_candidate.dart`

`ProductCandidate` is the standard in-app shape for any product entering
staging, regardless of source. It maps 1:1 to `product_staging` columns and
provides:

- `fromJson` / `toJson` — full round-trip
- `toStagingInsertMap()` — insert payload (drops nulls/empties, always includes
  `source`, `quality_score`, `missing_fields`, `status`)
- `copyWith(...)` — immutable updates
- `nutrition` getter — reads `nutritionJson` as the existing
  [`NutritionData`](../lib/features/product/models/nutrition_data.dart)

`nutritionJson` uses the **exact same shape** as `NutritionData.toMap()` /
`NutritionData.fromMap()` (keys: `energy_kcal`, `fat`, `saturated_fat`,
`carbohydrates`, `sugars`, `fiber`, `proteins`, `salt`, `sodium`,
`serving_size`). No second nutrition model exists.

---

## quality_score rules

`lib/features/product_staging/services/product_candidate_quality_evaluator.dart`

Deterministic additive scoring (clamped to 100):

| Field present | Points |
|---|---|
| barcode | +15 |
| name | +15 |
| brand | +10 |
| front image | +15 |
| ingredients_text (length > 20) | +25 |
| nutrition_json (has any useful value) | +20 |
| category_suggestion or category_tags | +10 |

Suggested status from the score:

| Score | Status |
|---|---|
| ≥ 75 | `pending` |
| 45–74 | `needs_review` |
| < 45 | `insufficient_data` |

The evaluator **never approves** a product. It only prepares it for review.

## missing_fields

The complement of the score. Possible values:

`barcode`, `name`, `brand`, `front_image`, `ingredients`, `nutrition`,
`category`.

Stored on the row so admins can see at a glance what a candidate lacks.

---

## Source and field-level source tracking

Every candidate records where its data came from:

- `source` — overall origin: `open_food_facts`, `manual_seed`,
  `user_submission`, `migros`, `trendyol`
- `source_url` — canonical link when available
- `raw_source_payload` — the original payload (e.g. full OFF product JSON),
  always refreshed on upsert for auditing
- Per-field provenance: `name_source`, `brand_source`, `image_source`,
  `ingredients_source`, `nutrition_source`, `category_source`

Per-field provenance lets a future merge step trust, e.g., an OCR'd nutrition
table over an OFF guess, or a market name over an OFF name.

---

## How to stage one OFF product

### From Dart (authoritative path)

```dart
final connector = OpenFoodFactsCandidateConnector();
final candidate = await connector.fetchCandidateByBarcode('8690526069906');
if (candidate != null) {
  final staged = await ProductStagingRepository().upsertCandidate(candidate);
  // staged.qualityScore / staged.status are computed by the repository
}
```

`OpenFoodFactsCandidateConnector` maps OFF → `ProductCandidate` and reuses the
shared `parseOffNutriments` parser, so `nutrition_json` is identical to the
barcode-import path. It writes **only** to `product_staging`.

### From the command line (quick testing)

```bash
# Inspect only — no DB write
python3 scripts/stage_off_product.py --barcode 8690526069906 --dry-run

# Write to product_staging
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_SERVICE_KEY=your-service-role-key
python3 scripts/stage_off_product.py --barcode 8690526069906 --real
```

The Python script is a thin testing helper. The authoritative mapping/scoring
logic lives in Dart — do not grow the script into a parallel implementation.

---

## Upsert / dedupe behavior

`ProductStagingRepository.upsertCandidate` matches on **(barcode, source)**:

- No existing row → insert.
- Existing row → **fill only null/empty fields**; never overwrite existing
  non-null values. `raw_source_payload` and `updated_at` are always refreshed,
  and `quality_score` / `missing_fields` / `status` are recomputed after merge.

`barcode` is deliberately **not** globally unique: multiple sources may submit
a candidate for the same barcode, and they are kept as separate rows.

---

## How admin approval will later move staging → products

Not built in this task. The intended later flow:

1. Admin opens the staging review queue (`status in (pending, needs_review)`).
2. Admin edits/cleans fields if needed.
3. On approve, the candidate is upserted into `products` by barcode (reusing the
   existing product-approval merge rules: never overwrite verified data).
4. The staging row's `status` becomes `approved`.

---

## ⚠️ Scope warning

This task is the **foundation only**. Explicitly **out of scope** here:

- Market scrapers (Migros / Trendyol).
- Bulk Open Food Facts import.
- Auto-approval of staged products.
- Migrating or modifying `product_submissions`.

Those come in later tasks.
