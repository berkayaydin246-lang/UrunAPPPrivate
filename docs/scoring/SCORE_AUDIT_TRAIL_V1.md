# Etiketly Score Audit Trail V1

Status: technically implemented locally; remote migration and controlled
catalogue rollout are pending.

## Purpose

The score audit trail is append-only evidence for a publicly displayed Etiketly
Score. It answers which verified product inputs, canonical additive facts, risk
values, component results, and named scoring versions produced that score. It
is not analytics, user tracking, or a performance cache.

The threat/legal scenario is a later product edit, ingredient-catalogue edit,
risk review, alias change, or methodology release making an old public score
impossible to explain from the current mutable database. A historical audit
record therefore contains the risk and canonical assessment facts used at the
time; it never resolves historical risk from today's catalogue.

## Architecture

`EtiketlyScoreAuditSnapshotBuilder` is pure and deterministic. It receives the
saved `Product` and the actual calculated `ProductEtiketlyScoreEvaluation`. It
does not read a clock, network, AI output, product name, or user data.

`EtiketlyScoreAuditValidator` parses conservatively and verifies supported
versions, the SHA-256 fingerprint, finite/ranged values, nutrition raw
breakdown, additive tier/item penalties, component contributions, and the V1
formula:

```text
finalScore = 0.80 * nutritionQuality + 0.20 * additiveQuality
```

`ScoreAuditSnapshotRepository` exposes only current-snapshot retrieval and a
trusted append operation. `ScoreAuditSnapshotFormatter` provides concise
internal/admin/legal text without exposing raw JSON in the consumer UI.

## Snapshot Schema

Audit schema version `1` records:

- Product ID, optional barcode, product `updated_at`, verification status, and
  persistence-supplied capture time.
- Exact ingredient text and source scoring-evidence schema version.
- Separate score, nutrition methodology, nutrition transform, and additive
  transform versions.
- Every resolved nutrition value with provenance and verification, nutrition
  basis/product state, resolved scoring category and its evidence, FVL/NNS
  evidence, ingredient completeness, and scoring classification facts.
- Canonical additive ID/key/name/e-code/group, risk value and risk source used
  at calculation time, match type/confidence/authority, eligibility, nutrition
  overlap, source tokens, per-item penalty, and exclusion reason.
- Nutrition negative/positive point breakdown, special rules, raw result, and
  nutrition quality.
- Additive counts, tier parameters/contributions, total penalty, unclamped
  quality, and additive quality.
- Exact nutrition/additive contributions and final internal score. The rounded
  display score remains derived.

No Flutter color, UI state, email, scanner/user ID, device ID, IP address,
location, AI output, community vote, or service credential is stored.

## Fingerprint

The fingerprint is lowercase SHA-256 over UTF-8 canonical JSON. Canonical JSON
recursively sorts map keys, preserves list order, normalises negative zero, and
rejects non-finite numbers. Canonical additive entries are sorted by canonical
key and trace ID before their score-affecting subset is serialized.

The exact V1 fingerprint payload is:

- Audit snapshot schema version.
- `score_version`.
- `nutrition_methodology_version`.
- `nutrition_transform_version`.
- `additive_transform_version`.
- Exact trimmed ingredient text.
- Source scoring-evidence schema version.
- Resolved input: all nutrition values/provenance/verification, basis, product
  state, resolved category/source/evidence/reasons, FVL evidence, NNS evidence,
  ingredient completeness, and classification facts.
- For each canonical additive: canonical key, risk level at calculation time,
  risk source, match type, match confidence, match authority, additive-quality
  eligibility, and nutrition overlap decision.

Product ID, barcode, product timestamps/status, product name, brand, image,
source, UI/legal copy, capture time, calculated outputs, AI, and community data
do not participate. Outputs are independently reconciled by the validator and
trusted SQL RPC.

## Immutability And Versions

`product_score_audit_snapshots` is append-only. A database trigger rejects
`UPDATE` and `DELETE`, and the product foreign key uses `ON DELETE RESTRICT`.
The uniqueness key includes product, fingerprint, score version, nutrition
methodology version, nutrition transform version, and additive transform
version. Repeated capture of the same current state is idempotent.

Version namespaces remain independent:

- `updated_nutrition_profile_2023_v1`
- `nutrition_quality_transform_v1`
- `additive_quality_transform_v1`
- `etiketly_score_v1`
- Audit snapshot schema version `1`

A component-version change requires a new fingerprint and row. Existing rows
remain unchanged.

## Security

The table has RLS enabled and no `anon` or `authenticated` direct table
privileges/policies. Mobile clients cannot select history, insert, update, or
delete rows.

`record_product_score_audit_snapshot` is `SECURITY DEFINER` with a fixed search
path. It accepts only `service_role` or a user whose server-managed JWT
`app_metadata.role` passes `is_freshscan_admin()`. It checks product existence,
metadata mirroring, supported versions, score ranges, and 80/20 reconciliation.
No service-role secret is present in Flutter.

`get_current_product_score_audit_snapshot` exposes only the latest snapshot for
one product. It does not expose history or trigger/admin metadata.

## Creation Lifecycle

The policy is trusted-data-change capture, never product-view capture:

1. Admin approval writes or enriches the product and scoring evidence.
2. The capture service reloads that saved product state.
3. It runs the same deterministic ingredient matcher, canonical risk service,
   readiness checks, transforms, and final calculator used by Product Detail.
4. If not scoring-ready, no audit row is needed and approval may continue.
5. If scoring-ready, a validated snapshot must be appended through the trusted
   RPC before the submission/staging row reaches `approved`.
6. An RPC failure prevents approval finalisation. Even if the earlier product
   write exists, public gating prevents an unaudited number from appearing.

Both `product_submissions` and `product_staging` approval paths use this policy.

## Corrections And Catalogue Changes

The current report-resolution flow does not mutate product scoring fields. Any
future verified correction operation that does mutate score-affecting fields
must call `captureCurrent(... verifiedCorrection)` after saving and before
publishing the corrected state. It appends a new fingerprinted row; it never
edits the previous row.

If an ingredient risk, canonical mapping, or relevant catalogue decision
changes, historical snapshots retain the old risk-at-time facts. Current
recalculation may legitimately produce a new result, but public Product Detail
will treat the prior snapshot as stale. A reviewed `catalogueChange` capture is
required before the new number is public.

## Public Score Gating

Product Detail displays a number only when all conditions hold:

- Current final score readiness passes.
- A trusted current snapshot exists.
- The snapshot parses and validates under supported versions.
- Product ID, fingerprint, component versions, qualities, contributions, and
  final score match the current deterministic calculation.

Missing, stale, invalid, or unreadable audit state produces no number and the
neutral consumer message `Puan kaydı güncelleniyor.` A valid calculated `0`
remains a real visible zero; missing data never becomes zero. Legacy products
continue to render their ordinary unavailable state.

## Controlled Backfill Plan

No production backfill is part of this phase. After the migration is reviewed
and applied manually, a trusted operator can run a separately reviewed tool:

1. Select one bounded page of existing products with supported scoring evidence.
2. Reload each product and current reviewed ingredient catalogue.
3. Run `ProductScoreAuditCaptureService` with `controlledBackfill`.
4. Skip non-scorable products and report reasons without manufacturing values.
5. Let the unique key/RPC make retries idempotent and version-aware.
6. Review inserted/duplicate/skipped/error totals and sample formatted records.
7. Repeat by stable product-ID cursor; never embed a service-role key in source.

Execution credentials must be supplied manually from a trusted environment.
Do not run this through an anonymous/mobile client. Public scores remain gated
until matching rows exist.

## Retention And Privacy Questions

The record intentionally contains product/scoring facts, not personal data.
Append-only retention, product deletion restrictions, exceptional erasure,
legal hold, and storage duration still require counsel/KVKK review. If an
exceptional deletion mechanism is later required, it must be a separately
authorised, logged process rather than weakening the normal trigger or RLS.

## Limitations

- The migration is local and has not been applied remotely.
- Existing catalogue products are not backfilled in this phase.
- Full historical replay across future executable code versions may require a
  versioned replay package; V1 retains the exact inputs/results/rules metadata
  and validates the currently supported V1 transformations.
- This is technical audit engineering, not a legal conclusion. Operator
  identity, live Terms/Privacy, Play Console declarations, remote claims audit,
  and retention decisions remain separate release blockers.
