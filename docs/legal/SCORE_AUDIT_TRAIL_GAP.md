# P0 Legal/Audit Trail Gap: Historical Score Reproducibility

Status: **P0 LEGAL/AUDIT TRAIL GAP**. Proposed design only; no migration was
created or deployed.

## Current Assessment

The app can deterministically calculate today's score from today's:

- `products.scoring_evidence` snapshot;
- current product/ingredient rows and canonical additive assessment;
- hard-coded score, nutrition and additive transform versions.

Current strengths:

- scoring evidence is versioned JSON and can include provenance, verification
  and `verified_at`;
- result objects expose score, nutrition-methodology, nutrition-transform and
  additive-transform versions;
- formula and readiness have extensive deterministic tests.

Current blockers:

- the numeric result and complete calculation payload are not persisted as an
  immutable dated audit record;
- product and `scoring_evidence` updates overwrite the current row;
- ingredient `risk_level` and explanation/source fields are mutable and have no
  risk-catalogue release/version history;
- no immutable link records exactly which canonical risk values and ingredient
  rows were used for score X on date Y;
- a later data/catalogue change can prevent exact reproduction of yesterday's
  public score.

Therefore the system cannot yet reliably answer “why did product/barcode B have
score X on date Y?” after mutable data changes.

## Proposed Minimum Schema

Subject to architecture, privacy and counsel review:

```sql
score_audit_snapshots
  id uuid primary key
  product_id uuid
  product_barcode_snapshot text
  calculated_at timestamptz
  product_updated_at_snapshot timestamptz
  score_version text
  nutrition_methodology_version text
  nutrition_transform_version text
  additive_transform_version text
  risk_catalog_version text
  input_snapshot jsonb
  additive_assessment_snapshot jsonb
  readiness_snapshot jsonb
  result_snapshot jsonb
  evidence_sha256 text

risk_catalog_releases
  version text primary key
  published_at timestamptz
  source_manifest jsonb
  changelog text

risk_catalog_release_items
  release_version text
  canonical_ingredient_key text
  risk_level text
  source_snapshot jsonb
  primary key (release_version, canonical_ingredient_key)
```

Snapshots should contain only product/scoring evidence needed for defence, not
reporter identities or correspondence.

## Migration Plan

1. Approve retention/purpose and immutable-access policy with counsel/privacy.
2. Define canonical JSON serialisation and hash algorithm.
3. Version the current risk catalogue without changing classifications.
4. Add append-only tables/RLS and tightly scoped admin/service access.
5. Dual-write audit snapshots for newly calculated public scores.
6. Verify replay: snapshot -> same readiness/components/final score.
7. Backfill only where evidence is sufficient; mark unknown history rather than
   reconstructing/fabricating it.
8. Add monitoring for missing snapshots and catalogue-version mismatches.

## Rollout

- Stage locally/test project first; no direct production push.
- Keep live score behaviour unchanged during dual-write validation.
- Do not expose audit JSON publicly; provide a curated explanation layer.
- Roll back writes, not the existing deterministic calculator, if snapshot
  persistence fails.
- Release gate requires replay tests and access-control review.

## Privacy And Retention

- Purpose: score explanation, correction, quality assurance and legal-dispute
  evidence.
- Avoid user IDs, install IDs, emails and free-text report content in score
  snapshots.
- Define retention by score/dispute need and legal obligations; do not choose an
  arbitrary “forever” period.
- Preserve legal-hold records separately with documented access and release.
- **COUNSEL REVIEW REQUIRED:** retention duration, legal basis, legal holds and
  data-subject interaction if any personal data is later linked.
