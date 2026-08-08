# Data Verification Semantics

## Meaning

In Etiketly, “verified/doğrulanmış” describes the review state and provenance of
specific product-data inputs used by the application. Depending on the field,
this can include label-derived nutrition values, ingredient-list completeness,
measurement basis, category evidence and admin review metadata.

## It Does Not Mean

Verification is not:

- product safety certification;
- medical or dietary suitability;
- government/regulatory approval;
- laboratory testing of the physical product;
- manufacturer endorsement;
- confirmation that a recipe will never change;
- a guarantee that all allergens are absent or identified.

## UI Rules

- Prefer field/scope language such as “puanlama girdileri doğrulandı”.
- Do not show a generic shield/check badge labelled only “Onaylı ürün”.
- Any badge must have an accessible explanation of the reviewed field and date.
- Open Food Facts previews remain explicitly “doğrulanmamış” and do not become
  verified catalogue data without the existing review path.
- Product changes require new evidence; old verification must not be carried
  forward silently.

## Current Gap

`products.verification_status` is broad and does not itself preserve a full
field-level historical audit trail. `products.scoring_evidence` improves current
input provenance but is mutable with the product row. Historical verification
semantics therefore remain a release issue described in
[SCORE_AUDIT_TRAIL_GAP.md](./SCORE_AUDIT_TRAIL_GAP.md).
