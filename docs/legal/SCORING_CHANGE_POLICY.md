# Etiketly Scoring Change Policy

## Invariants

- The same methodology version and same verified input must produce the same
  numeric result.
- A brand, manufacturer, advertiser, user or employee cannot receive a
  product-specific formula exception.
- Payments, sponsorships, complaints and legal pressure cannot change score
  mathematics.
- Correcting factual input triggers the ordinary deterministic recalculation.
- Missing required evidence continues to produce no score, not an estimate.

## Versioning

Every material mathematical or readiness change must receive a new explicit
version covering:

- final score formula/weights;
- nutrition raw methodology;
- nutrition quality transform;
- additive transform/classification catalogue;
- readiness rules and score bands.

Copy-only/legal-disclosure changes do not receive a mathematical version when
they cannot affect inputs, readiness or result. Their application release/commit
is still recorded.

## Change Process

1. Write the reason, evidence and affected product categories.
2. Define expected score/readiness changes before implementation.
3. Review for brand-neutral, uniformly applicable logic.
4. Add old/new version regression fixtures and calibration tests.
5. Obtain scientific, product and legal review appropriate to the change.
6. Publish a meaningful release note before or with broad rollout.
7. Recalculate with explicit version attribution; never overwrite historical
   evidence without retaining the prior defensible record.

## Public Disclosure

Scores may change when verified product data or methodology changes. Etiketly
does not promise that methodology or scores remain immutable forever. Significant
changes should explain what changed, effective date/version and which products
may be affected without implying that prior products were unsafe or illegal.

## Historical Reproducibility

Historical reproducibility is required where feasible, but the current schema
does not preserve all product and risk-catalogue versions. The release plan is
defined in [SCORE_AUDIT_TRAIL_GAP.md](./SCORE_AUDIT_TRAIL_GAP.md). No large
migration is created automatically in this phase.
