# Legal Release Risk Matrix

Assessment date: **8 August 2026**

This is engineering triage, not a legal conclusion. Priority reflects current
release exposure and reversibility. “Resolved in code” still requires final
product/counsel review where stated.

## P0 - Resolve Before Public Scoring Release

| Finding | Evidence/status | Required resolution |
|---|---|---|
| Historical score cannot be fully reproduced after mutable product/risk-catalogue changes | No immutable result/input/catalogue snapshot; documented in `SCORE_AUDIT_TRAIL_GAP.md` | Approve and implement minimum versioned append-only audit trail; replay test before broad public score release. |
| Public ingredient explanations contain unaudited health-effect/legal-status claims | Local and remote fields include cancer, reaction, cardiovascular, legal-limit and consumption language | Complete field-level primary-source/editorial/counsel audit or suppress unapproved claim fields. |
| Operator/data-controller identity is absent | Live Terms/Privacy use support email but no established legal identity/address | Establish and publish truthful operator/controller details and KVKK channel. |
| Live Terms do not cover Etiketly Score methodology, versioning, independence and correction rules | Live page dated 30 June 2026 predates score feature | Counsel-approve and publish updated Terms; record effective version/acceptance decision. |
| Live Privacy/KVKK disclosure lacks activity-specific legal bases, transfer and concrete retention | Current page uses general purposes/“reasonable periods”; score/report/submission facts incomplete | Approve processing inventory, transfer mechanism, retention and Article 10 notices; publish actual policy. |
| Google Play Health declaration/store disclaimer not yet manually re-evaluated | Console was not accessed/changed in this phase | Complete accurate declaration, likely Nutrition and Weight Management, update disclaimer and archive answers before release. |

## P1 - Resolve Before Broad Production Release

| Finding | Evidence/status | Required resolution |
|---|---|---|
| Score/band/additive public wording needs Turkish counsel confirmation | Safer contextual wording implemented; legal classification unresolved | Counsel questions 1-3. |
| Comparison/ranking may engage comparative advertising/unfair competition | Objective basis controls exist; policy drafted; monetisation absent | Counsel approval before score ranking, affiliate or sponsored alternative features. |
| User-submitted photo/data licence is underspecified | Live Terms says submissions may be used; limited licence is draft | Approve licence and collection-point Terms acknowledgment where required. |
| Correction/dispute retention and legal hold are undefined | Workflow exists; no binding SLA; no retention schedule | Approve schedule, evidence-preservation and deletion process. |
| Manufacturer correction contact lacks dedicated notice/process implementation | Process drafted; current path is consumer report/support email | Publish contact/process and activity-specific KVKK notice after identity resolution. |
| Nutri-Score methodology attribution/trademark wording unresolved | No logo/A-E/public affiliation found; developer docs reference methodology | Counsel questions 13-14 before public attribution. |
| Verification semantics can be overread | Documentation added; broad `verification_status` remains | Add scoped UI explanation if a public verification badge is introduced. |

## P2 - Follow-Up Improvement

| Finding | Current mitigation | Follow-up |
|---|---|---|
| Legal/methodology content is only a bottom sheet plus external Terms links | Concise layered score disclosure exists | Add approved public methodology URL from Settings/score sheet. |
| Consumer reports cannot receive status updates | Data-minimising no-email flow | Decide whether optional follow-up is valuable; add only with KVKK notice. |
| Store screenshot copy has no score-specific legal context | Current alt text is factual | Re-audit screenshots/captions whenever score UI is added to listing. |
| Internal/public terminology depends on adapters | Public risk labels neutralised | Add lint/content tests for newly introduced public strings. |

## Resolved/Reduced In This Phase

- Score band is contextualised as `İçerik profili: ...`.
- Score component and additive summaries use neutral Etiketly context.
- Legacy public health-risk/consumption recommendation output was neutralised.
- Allergen non-detection now directs users to the current package.
- Product correction entry is discoverable and no longer promises an update.
- Methodology sheet states 80/20, determinism, no AI/user/manufacturer numeric
  control, no-score gating, version/change and medical/certification boundaries.
- No Nutri-Score logo, A-E grade or official affiliation was found in app/assets.
