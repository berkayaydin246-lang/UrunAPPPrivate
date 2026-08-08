# Etiketly Public Claims Matrix

Audit date: **8 August 2026**

`GREEN`, `YELLOW` and `RED` are engineering risk triage labels, not legal
conclusions. `GREEN` does not guarantee compliance. Official materials are listed
in [OFFICIAL_SOURCE_REGISTER.md](./OFFICIAL_SOURCE_REGISTER.md).

## Matrix

| Class | Current/previous wording | Public location | Reason | Safer wording/action | Engineering | Lawyer |
|---|---|---|---|---|---|---|
| YELLOW | “Çok iyi içerik profili” | Etiketly score card | Evaluative label could be read as whole-product health judgment. | “İçerik profili: Çok iyi” while preserving thresholds. | Changed | Yes |
| YELLOW | “Etiketly Puanı … 0-100” | Score card/methodology | Defensible only with clear definition, inputs, version and boundaries. | Canonical content-profile definition plus layered disclaimer. | Changed | Yes |
| YELLOW | “Beslenme kalitesi / Katkı kalitesi” | Score component cards | “Quality” may be read more broadly than the calculated component. | “Beslenme bileşeni / Katkı bileşeni.” | Changed | Yes |
| RED | “yüksek riskli içerik / orta riskli içerik” | Legacy analysis result | Unqualified risk language can imply human-health risk. | “Etiketly değerlendirmesinde yüksek/orta düzey içerik.” | Changed | Yes |
| RED | “bazı içerikler sağlık açısından risk taşıyabilir” | Legacy analysis warning | Direct health-risk claim without claim-specific public substantiation. | “Etiketly değerlendirmesinde daha fazla dikkat gerektiren düzey.” | Changed | Yes |
| RED | “Bu ürün sık tüketim için uygun olmayabilir” | Legacy analysis summary | Product-level consumption recommendation. | “İçerik profili daha fazla dikkat gerektiriyor.” | Changed | Yes |
| YELLOW | “Düşük/Orta/Yüksek Risk” | Ingredient match and comparison | Internal classification shown as an absolute public risk. | “Etiketly değerlendirmesi: düşük/orta/yüksek düzey.” | Changed | Yes |
| RED | Ingredient catalogue statements concerning cancer, cardiovascular effects, reactions, safety or consumption | Ingredient detail dialogs/pages | Some claims are health-related and may combine local and remote fields; source-by-source approval is incomplete. | Keep out of launch until field-level source/legal/editorial audit; do not mass-rewrite blindly. | Audit blocker documented | Yes |
| YELLOW | “Belirgin alerjen eşleşmesi yok” | Comparison | Detection absence can be mistaken for allergen absence/safety. | “Etiket metninde alerjen eşleşmesi tespit edilmedi. Güncel ambalajı kontrol edin.” | Changed | Yes |
| GREEN | “Etikette tespit edilen alerjenler” | Product analysis/comparison | Describes detection scope rather than certifying absence. | Retain with package-check reminder. | Changed | Review |
| YELLOW | “daha iyi seçenek” | Comparison accessibility semantics | May imply an overall recommendation despite metric-specific comparison. | “bu ölçütte vurgulanan değer.” | Changed | Yes if ranking/monetisation launches |
| GREEN | “Daha düşük / Daha yüksek” | Objective nutrition comparison | Factual when basis and values are comparable; current code suppresses incompatible bases. | Retain with basis disclosure. | No | Review |
| YELLOW | “İnceledikten sonra ürün bilgilerini güncelleyeceğiz” | Report success message | Creates an outcome promise; a report may be unsupported/rejected. | “Bildirim incelemeye alınır; veriyi doğrudan değiştirmez.” | Changed | No |
| GREEN | “Ürün verisinde hata mı var?” | Product detail correction entry | Neutral, discoverable correction route. | Retain. | Changed | Review |
| YELLOW | “doğrulanmış veri” | Score readiness/methodology | Could imply product certification if undefined. | Define as reviewed input data only, never safety/regulatory/manufacturer certification. | Documentation added | Yes |
| GREEN | “Open Food Facts (doğrulanmamış)” | Barcode external preview | Clearly identifies external/unverified status. | Retain; external data is not scored as verified evidence. | No | Review |
| YELLOW | “tıbbi veya diyetetik tavsiye değildir” | Onboarding/settings/methodology | Appropriate boundary but not a cure for misleading substantive claims. | Use canonical layered disclaimer and independently remove aggressive claims. | Changed | Yes |
| YELLOW | Broad liability exclusion | Live Terms section 9 | Consumer-law effectiveness and fairness are unresolved. | Replace only after counsel approves a balanced limitation. | Local draft only | Required |
| YELLOW | “Gönderilen … görseller … kullanılabilir” | Live Terms submissions section | Licence scope, duration, display and rights warranty are underspecified. | Limited operational/photo licence draft; consent flow decision. | Local draft only | Required |
| RED | “safe/healthy/dangerous/toxic/carcinogenic” as score conclusions | Marketing/store/in-app (prohibited rule) | Absolute health/safety or medical implications. | Do not publish as Etiketly score conclusions. | Test/rule added | Required for exceptions |

## Public Versus Internal Terminology

- Internal enums such as `riskLevel`, `high`, `medium`, `low`, score bands and
  comparison outcomes remain unchanged.
- Public adapters must provide Etiketly context. Internal names must not leak as
  standalone health or safety conclusions.
- Nutrition threshold labels such as “Yüksek” or “Düşük” remain metric-specific;
  they must not be promoted as whole-product health claims.

## Outstanding RED Audit

The ingredient explanation catalogue remains the principal public-claims launch
blocker. See
[REMOTE_CONTENT_AUDIT_REQUIRED.md](./REMOTE_CONTENT_AUDIT_REQUIRED.md). This
phase does not assert that a disclaimer alone makes those statements publishable.
