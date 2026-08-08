# Data Provenance Assessment

Assessment date: **8 August 2026**

## Current Strengths

- `products` records source/source URL, verification status and update time.
- `scoring_evidence` stores versioned nutrition, measurement basis, product
  state, category/composition/NNS evidence, provenance, verification and optional
  admin verification metadata.
- Admin review paths preserve/merge higher-trust evidence rather than silently
  allowing OCR candidates to become verified facts.
- Ingredient rows can carry source URL, legacy source strings and structured
  authority/title/URL/access-date references.
- Product reports preserve product name/brand/image snapshots at submission time
  and are not permitted to modify product data directly.
- External Open Food Facts previews are labelled unverified and do not silently
  become verified products.

## Current Gaps

- Public product detail does not consistently expose field source/date/version;
  the generic package-check banner is helpful but not a provenance record.
- Product and scoring-evidence rows are mutable and lack immutable history.
- Ingredient risk/source rows lack a catalogue release version and history.
- Legacy `source_references` strings may have incomplete URL/date/section data;
  fallback rendering can assign an epoch access date internally.
- The app does not persist the full score result and exact additive-assessment
  snapshot used on a particular display date.
- Remote and local ingredient enrichment can merge fields without a public
  per-statement source decision.

## Public Wording Boundary

Only claim provenance that the stored evidence supports. `Doğrulanmış` means a
reviewed input state, not government/manufacturer approval, laboratory testing or
product safety certification. A source URL alone does not prove that every
public sentence is supported by that source.

## Required Follow-Up

- Implement the reviewed historical design in
  [SCORE_AUDIT_TRAIL_GAP.md](./SCORE_AUDIT_TRAIL_GAP.md).
- Complete the field-level content/source review in
  [REMOTE_CONTENT_AUDIT_REQUIRED.md](./REMOTE_CONTENT_AUDIT_REQUIRED.md).
- Define a curated public provenance view: source type, label/evidence date,
  review state and methodology version without exposing admin/user personal data.
- Reject incomplete source records for health-effect publication; do not infer a
  source from authority name alone.
