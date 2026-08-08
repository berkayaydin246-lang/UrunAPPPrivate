# Manufacturer And Product-Data Correction Process

Status: proposed operational process. It creates no contractual response or
resolution deadline. Legal notices are escalated separately.

## Who May Submit

- consumer;
- manufacturer or brand owner;
- authorised distributor/importer;
- another person with credible first-hand product evidence.

The public product-detail route is `Ürün verisinde hata mı var? > Hata bildir`.
The current form covers image, ingredients, nutrition, name/brand, category,
barcode and other errors. A manufacturer contact may initially use the support
email until a dedicated form is approved.

## Minimum Evidence

Request only what is necessary:

- exact product name and barcode;
- disputed field and current Etiketly value;
- clear current package/label evidence or an authoritative product source;
- evidence date and, if known, lot/market variant;
- reporter contact email only when follow-up is needed;
- for an organisation, name, role and a simple statement of authority to act.

Do not routinely request national ID, home address, health information or other
special-category/personal data. Ask for stronger authority evidence only when
identity/authority is genuinely disputed and after privacy/counsel review.

## Review Flow

1. Record the product/barcode, disputed field, evidence and receipt time.
2. Preserve the current product data, scoring evidence and methodology version.
3. Check whether evidence identifies the same market variant/product.
4. Compare package/source evidence against the current stored field.
5. If a factual error is proven, correct the product input through the normal
   reviewed admin path.
6. Recalculate the Etiketly Puanı automatically with the same active,
   deterministic methodology.
7. Do not manually set, round, waive or negotiate a score for any reporter.
8. Record the factual decision and evidence; avoid opinions about the company.
9. If evidence is inconclusive, retain the current value or mark the affected
   score unavailable where the data is manifestly unreliable.
10. Escalate legal demands to counsel under
    [PRODUCT_DISPUTE_PLAYBOOK.md](./PRODUCT_DISPUTE_PLAYBOOK.md).

## Status Language

Allowed public acknowledgment:

> Bildiriminiz incelemeye alınmıştır. Gönderim, ürün verisini veya Etiketly
> Puanını doğrudan değiştirmez. Sağladığınız kanıt ilgili ürün ve veri kaynağıyla
> karşılaştırılacaktır.

Do not promise “we will update”, “we will remove” or a binding SLA. Public copy
is `Bildirimler incelemeye alınır`. Internal target times, if later adopted, are
non-contractual and must not be published without operational/legal approval.

## Outcome Principles

- A company cannot buy or negotiate a higher score.
- Dislike of a correctly reproduced score is not itself a factual error.
- Credible contrary evidence must not be ignored.
- Corrected verified inputs trigger deterministic recalculation.
- Reporter content never directly enters production or changes the score.

## Privacy

The current `product_reports` flow stores a random app-install ID and optional
free-text details but no reporter email. A future manufacturer-contact channel
will process identity/contact data and needs an activity-specific Article 10
notice before collection. See
[KVKK_CORRECTION_FLOW_REVIEW.md](./KVKK_CORRECTION_FLOW_REVIEW.md).
