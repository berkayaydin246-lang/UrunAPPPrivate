# Remote And Catalogue Content Audit Required

Status: **P0 PUBLIC-CONTENT RELEASE BLOCKER** for ingredient health-effect
explanations. This file does not block the deterministic numeric score itself;
it blocks publishing unaudited explanatory claims as authoritative consumer
health statements.

## Why A Separate Audit Is Required

Ingredient detail content is assembled from both:

- Supabase `ingredients` fields; and
- local `lib/features/product/data/ingredient_explanation_catalog.dart`
  enrichment/fallback data.

The app can therefore render content that is not fully determined by a single
reviewable Flutter source file. A blanket rewrite in this phase could erase
important nuance or introduce new scientific/legal errors.

## Public Fields To Inventory

For every active ingredient/canonical additive, export and review:

- `name`, `normalized_name`, `e_code`, `category`, `risk_level`;
- `short_description`, `long_description`;
- `ingredient_type`, `short_purpose`, `processing_role`;
- `short_risk_summary`, `child_warning`, `caution_groups`;
- `additive_group`;
- `source_url`, `source_references`, `source_reference_entries` including
  authority, title, URL, document code, note and access date;
- `created_at`, `updated_at`;
- local enrichment override/fallback source and merge outcome.

Also audit public `product_reviews.summary`, `warning_text`, `positive_points`,
`negative_points`, `consumption_advice` and `suitable_for_children` if any live
screen consumes remote review rows.

## High-Priority Claim Patterns

Manually review every statement containing concepts such as:

- cancer/carcinogenic, cardiovascular, allergy/anaphylaxis, attention/activity;
- safe/dangerous/toxic/harmful, “risk görülmemiştir”, legal-limit assertions;
- diagnose/treat/prevent, disease, children/pregnancy/special populations;
- avoid/recommended consumption, frequency/amount advice;
- legal status in Turkey/EU/US or an authority's current conclusion.

The local catalogue currently includes cancer-association, cardiovascular,
reaction, legal-limit and consumption-advice language. These are not silently
approved merely because EFSA, WHO or IARC is named. Each claim needs an exact
primary source, scope, date/version, faithful wording and counsel/editorial
decision.

## Required Review Record

For each public statement store:

- canonical ingredient/additive ID and content version;
- exact public wording and language;
- statement type: factual function, legal status, population caution, health
  effect, consumption advice or Etiketly classification;
- primary source URL/document/version/access date and supporting section;
- evidence owner/reviewer and review date;
- permitted jurisdictions and expiry/recheck date;
- `GREEN/YELLOW/RED`, counsel requirement and approved public wording.

## Safe Default

Until approved, the safe public subset is identity/E-code, neutral technological
purpose, clearly contextualised Etiketly classification and traceable sources.
Do not infer “safe” from low classification or “dangerous” from high
classification. Do not claim allergen absence from failed detection.

## Engineering Follow-Up

1. Build a read-only audit export; do not mutate production data during export.
2. Resolve duplicate local/remote content and define source precedence.
3. Add `content_version`, `review_status`, `reviewed_at`, `reviewed_by` and
   source-specific approval only after schema/counsel review.
4. Hide or neutralise unapproved claim fields at presentation boundary.
5. Add tests with representative remote payloads and prohibited affirmative
   claims.
6. Publish only the counsel/editorial-approved catalogue release.

No migration or production-data rewrite is performed in Phase 2B-10.
