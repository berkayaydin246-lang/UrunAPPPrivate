# Nutri-Score Trademark And Public UI Audit

Audit date: **8 August 2026**

## Technical Result

- No Nutri-Score logo asset was found under `assets/`.
- No A-E Nutri-Score grade is rendered by Flutter public UI.
- No runtime public string calls Etiketly an official Nutri-Score implementation,
  certification or affiliate.
- Etiketly uses a numeric 0-100 score and textual content-profile bands, not the
  protected A-E front-of-pack logo presentation.
- Internal developer/scoring documentation and the NNS identifier version retain
  source attribution to the updated Nutri-Score scientific methodology. These
  are implementation references, not public grades.

## Separation Rules

- Do not add the Nutri-Score logo, A-E letters, official graphic charter or a
  lookalike front-of-pack badge without registration/licence and counsel review.
- Do not say `official Nutri-Score`, `Nutri-Score approved`, `certified` or imply
  endorsement by Santé publique France or another authority.
- Public Etiketly component names remain `Beslenme bileşeni` and `Katkı bileşeni`.
- If a public methodology page references scientific ancestry, it must clearly
  identify Etiketly's independent transform/combined score and absence of
  official affiliation.

## Unresolved Question

**COUNSEL REVIEW REQUIRED:** Can Etiketly publicly state that its nutrition
component is based on the updated Nutri-Score scientific methodology while using
its own name, 0-100 transform and no Nutri-Score logo/A-E grade? What attribution,
trademark notice, permission or limitations are required in Turkey and the
target distribution markets?

Official material: [Santé publique France Nutri-Score page](https://www.santepubliquefrance.fr/nutrition-et-activite-physique/nutri-score)
and [trademark Conditions of Use](https://www.santepubliquefrance.fr/content/download/150258/file/Nutriscore_reglement_usage_EN_20240626.pdf),
reviewed 8 August 2026.

## Release Decision

No Nutri-Score trademark/logo removal is needed in current runtime/assets.
Public methodology attribution remains blocked pending counsel; internal factual
developer attribution remains unchanged.
