# Legacy scoring evidence backfill

`tool/legacy_scoring_evidence_backfill.dart` reconstructs only the scoring
evidence supported by retained `product_staging.raw_source_payload` metadata
and the current `products` row. It does not calculate audit snapshots and does
not make an incomplete legacy product publicly scorable.

## Recovery contract

- A product is matched to staging rows by its exact, trimmed `source_url`.
- Duplicate rows are accepted only when their relevant evidence is identical.
- Only an explicit `nutrition_basis: per_100` without the historical assumed
  per-100 warning is eligible.
- The category resolver's opt-in legacy policy maps deterministic persisted
  beverage taxonomy to `per100ml` and other resolved in-scope categories to
  `per100g`. Ordinary known food tags may resolve `generalFood`; unresolved
  special-category evidence never falls through to that default.
- Existing `NutritionData` parsing supplies only values present in
  `products.nutrition_text`; missing values remain unknown.
- Nutrition becomes source-verified declared-label evidence only when the
  staging nutrition JSON matches the product, its extraction strategy is
  retained, and web-scraper provenance is present.
- Ingredient completeness requires `ingredients_ok`, retained raw text,
  web-scraper provenance, and exact normalized staging/product text equality.
- A source-complete list with no qualifying FVL signal proves FVL absence. An
  explicit qualifying percentage is retained; qualifying but insufficient or
  factor-dependent evidence remains unknown.
- Exact NNS detection becomes present. Absence is emitted only for a
  source-complete list.
- A resolved in-scope legacy product defaults to the as-sold state unless
  retained metadata explicitly supplies another supported state.
- Existing canonical ingredient matching and risk assessment determine
  additive results. Legacy assessment ignores unresolved ordinary food tokens,
  but unresolved additive-like tokens, fuzzy/review matches, conflicts, and
  unknown canonical risks remain blockers.
- Existing non-null `products.scoring_evidence` is never merged or overwritten.

Explicit retained metadata, derived state, completeness-dependent absence, and
NNS evidence use `databaseImport + verified`. Source-matched nutrition and
literal FVL percentages use `declaredLabel + verified`. Unsupported partial
nutrition remains `databaseImport + unverified` and cannot pass strict energy
readiness. The tool never emits `adminVerified` evidence.

## Safe operation

Credentials must already exist in the process environment as `SUPABASE_URL`
and `SUPABASE_SERVICE_ROLE_KEY`. Do not place them on the command line. The
project ref must match the Supabase URL host.

Start with bounded read-only inspection:

```bash
dart run tool/legacy_scoring_evidence_backfill.dart \
  --project-ref PROJECT_REF \
  --sample-product-ids PRODUCT_UUID[,PRODUCT_UUID...]

dart run tool/legacy_scoring_evidence_backfill.dart \
  --project-ref PROJECT_REF \
  --dry-run \
  --batch-size 50 \
  --max-products 100
```

Apply is intentionally gated and bounded:

```bash
dart run tool/legacy_scoring_evidence_backfill.dart \
  --project-ref PROJECT_REF \
  --apply \
  --confirm-write-scoring-evidence \
  --batch-size 50 \
  --max-products 100 \
  --start-after LAST_SAFE_CURSOR
```

The PATCH condition includes `scoring_evidence IS NULL`, so concurrent or
repeated execution cannot overwrite evidence. Resume from
`safe_resume_cursor`, not `last_examined_cursor`, after any product error.
Dry-run and sample inspection perform no writes. Run
`tool/score_audit_backfill.dart` separately only after eligible scoring
evidence has been reviewed and accepted.
