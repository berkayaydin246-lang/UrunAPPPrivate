# Product Scoring Lifecycle

Status: release-freeze contract for Etiketly Score v2.

## Production boundary

Every approved catalogue insert or scoring-relevant product update must call
`ProductScoringLifecycleService.processCurrent` after the canonical `products`
row has been saved. The lifecycle is source-neutral: it receives a product ID,
an audit trigger, and optionally a trusted evidence resolver. It never branches
on Migros, A101, Open Food Facts, a user submission, or another merchant name.

Source adapters are responsible only for preserving source data and provenance:

- Staging approval supplies reviewed `scoring_evidence` when present. For older
  web staging rows, its adapter may invoke the existing conservative legacy
  evidence recovery using that exact staging row.
- Product-submission approval persists the admin-reviewed OCR evidence.
- Direct Dart product updates call the lifecycle through the Flutter data source.
- Python operational tools call `tool/product_scoring_lifecycle.dart` through
  `scoring_lifecycle_bridge.py`. The Python process does not implement scoring.

No ingestion adapter may calculate nutrition points, additive quality, the
final score, or an audit fingerprint.

## Source-neutral input contract

A current or future merchant adapter supplies canonical source facts, not score
rules. Its trusted evidence must preserve, when present:

- Barcode, ingredient text, declared percentages, and whether the complete
  ingredient list was captured.
- Nutrition values and units, including energy kJ/kcal, fat, saturated fat,
  carbohydrates, sugars, fiber, protein, salt, and sodium.
- The explicit nutrition basis (`per100g`, `per100ml`, serving, or unknown) and
  product-state evidence (`asSold`, `asPrepared`, or unknown).
- Category/classification facts and their provenance.
- Source URL, source identity, extraction strategy, verification state, and
  other provenance needed to distinguish declared facts from assumptions.

Unknown facts remain unknown. Adding A101, CarrefourSA, Migros, or another
source requires only an adapter to this contract; it must not add a merchant
branch to scoring.

## Required flow

1. Save the canonical product fields and trusted ingestion evidence.
2. Load the persisted product and reviewed ingredient catalogue.
3. If a trusted resolver is supplied, rebuild evidence from the current source
   input. Persist it only when its JSON differs, using compare-and-set against
   the evidence that was read. Without a resolver, preserve existing evidence.
   Failure to rebuild required current evidence blocks a new audit rather than
   scoring stale evidence.
4. Run `ProductScoreAuditEvaluator`, which owns canonical additive matching via
   `assessForScoring`, readiness, v2 calculation, snapshot building, validation,
   and fingerprint generation.
5. If readiness is blocked, write no audit and return ordered blockers.
6. If ready, reuse a matching current fingerprint or call the immutable audit
   RPC with the ingestion trigger.
7. Return `ProductScoringLifecycleResult` with evidence status, nutrition and
   additive readiness, final readiness, blockers, score, fingerprint, and audit
   status.

## Material changes and idempotency

Scoring inputs are the ingredient text, persisted scoring evidence (nutrition,
basis, state, classification, FVL and NNS facts), and canonical additive facts
captured by the evaluator. A changed scoring input produces a changed
fingerprint and a new immutable audit row. Historical rows are never updated.
An equal trusted-evidence rerun performs no evidence write. A formula change
rebuilds and replaces the source evidence, then evaluates only the reloaded
canonical product.

Names, brands, images, search keywords, timestamps, and other presentation-only
metadata are not fingerprint inputs. Updating only those fields reuses the
current audit and must not create a new snapshot. The RPC uniqueness constraint
also makes concurrent retries idempotent.

## Failure isolation

A lifecycle failure is returned as `auditStatus=failed` with a non-secret error
type. It does not delete or roll back an otherwise valid product write. Callers
must log or retain this structured result; they must not treat it as a fabricated
score. Existing explicit database transactions retain their own atomicity rules.

## Connected write paths

- `ProductStagingApprovalRepository`: manual staging approval and enrichment.
- `ProductSubmissionApprovalRepository`: reviewed missing-product submission.
- `ProductDraftRepository`: legacy approved user-submission draft creation.
- `OpenFoodFactsRepository`: admin-only scoring-relevant enrichment of an
  existing product. The normal consumer barcode flow remains read-only and
  returns the local row or an external OFF preview.
- Web scraper opt-in auto-approval: Dart CLI bridge after product upsert.
- OFF dump/import tools and category-tag maintenance: Dart CLI bridge after each
  product write.

Product report status updates do not modify `products` and are outside this
boundary. Image-only, name-only, and search-keyword-only repairs do not require
a scoring run because they cannot change the fingerprint. A tool that also
changes category tags must invoke the lifecycle.

`20260814010000_restrict_product_catalogue_writes.sql` removes the original
development policies that allowed anonymous catalogue writes. Mobile catalogue
writes require the trusted admin claim; service-role operational tools must use
the Dart lifecycle bridge. This prevents an untrusted direct REST write from
bypassing lifecycle orchestration.

The exact controlled application, verification, and fail-closed rollback for
that migration are documented in
`docs/scoring/PRODUCT_CATALOGUE_RLS_ROLLOUT.md`. It must be applied alone after
the lifecycle-enabled application and operational tools are deployed. Do not
use `supabase db push` for this repository.

## Frozen v2 contract

- score version: `etiketly_score_v2`
- nutrition methodology: `updated_nutrition_profile_2023_v1`
- nutrition transform: `nutrition_quality_transform_v2`
- additive transform: `additive_quality_transform_v1`
- evidence schema: `1`
- audit snapshot schema: `1`
- final weights: nutrition `0.80`, additives `0.20`

Changing any frozen item requires an explicit versioned scoring release, new
calibration evidence, updated validation/RPC support, and migration planning.
