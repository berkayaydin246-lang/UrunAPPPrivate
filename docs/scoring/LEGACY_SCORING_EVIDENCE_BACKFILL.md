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
- The current category resolver must distinguish `per100g` from `per100ml`.
  Generic per-100 metadata otherwise remains `basis_unit_ambiguous`.
- Existing `NutritionData` parsing supplies only values present in
  `products.nutrition_text`; missing values remain unknown.
- Exact positive NNS matches use the current deterministic detector. No match
  remains unknown because legacy ingredient completeness is not established.
- FVL and ingredient completeness remain unknown. Product state remains
  unknown unless retained metadata explicitly supplies a supported value.
- Existing canonical ingredient matching and risk assessment determine the
  additive blockers. No independent additive classification is performed.
- Existing non-null `products.scoring_evidence` is never merged or overwritten.

Explicit retained metadata uses `databaseImport + verified`. Imported
nutrition values and positive NNS detections use
`databaseImport + unverified`. The tool never emits `adminVerified` evidence.

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
