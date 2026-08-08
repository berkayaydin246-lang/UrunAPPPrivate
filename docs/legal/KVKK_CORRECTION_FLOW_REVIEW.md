# KVKK Review: Reports And Manufacturer Corrections

Review date: **8 August 2026**

Status: gap analysis, not a final Article 10 notice. The responsible operator is
not fully identified in the repository or current live legal pages.

> **OPERATOR IDENTITY REQUIRED BEFORE PUBLICATION**

## Current Consumer Product Reports

Observed fields:

- product ID and server-side product name/brand/image snapshot;
- report type and optional free-text details;
- optional evidence URLs (current consumer UI submits none);
- random local app-install ID and client submission ID;
- status, timestamps, admin note and reviewer auth ID.

Free text may contain personal data even though the form does not request it.
The app should continue to discourage unnecessary personal, health and sensitive
information.

## Future Manufacturer Contact

Likely minimum fields:

- business contact name, work email and role;
- represented organisation and authority statement;
- product/barcode, disputed field and supporting evidence;
- correspondence and outcome record.

Do not collect national ID, private address, signature specimen, special-category
data or extensive corporate documentation by default.

## Article 10 Checklist

Before collection, an activity-specific notice must state:

- legal name and contact of the data controller and representative, if any;
- specific purposes (triage, verification, response, abuse prevention, dispute
  evidence);
- recipient groups and transfer purposes, including actual infrastructure;
- automated/non-automated collection method;
- exact KVKK Articles 5/6 processing condition for each purpose;
- Article 11 rights and application channel;
- retention/deletion criteria;
- overseas-transfer mechanism where providers/hosting create a transfer.

Official basis: [KVKK Article 10 information duty](https://www.kvkk.gov.tr/Icerik/2033/Aydinlatma-Yukumlulugu-)
and [information procedure Communique](https://www.kvkk.gov.tr/Icerik/4132/aydinlatma-yukumlulugunun-yerine-getirilmesinde-uyulacak-usul-ve-esaslar-hakkinda-teblig).

## Unresolved Decisions

- **COUNSEL REVIEW REQUIRED:** Identify the controller and, if applicable,
  representative/VERBIS position.
- **COUNSEL REVIEW REQUIRED:** Select the processing condition for consumer
  reports, anti-abuse install IDs, manufacturer correspondence and legal-defence
  preservation; do not default all activities to consent.
- **COUNSEL REVIEW REQUIRED:** Determine lawful international-transfer mechanism
  for Supabase, Render, Anthropic and any support-email provider in actual use.
- **COUNSEL REVIEW REQUIRED:** Set defensible retention periods separately for
  rejected reports, resolved corrections, anti-abuse identifiers and legal
  dispute evidence.
- Decide whether reporter follow-up is necessary; the current no-email consumer
  flow is more data-minimising but cannot deliver individual status updates.

## Engineering Actions Before Release

1. Publish controller identity and a valid KVKK application channel.
2. Add activity-specific notice at report/manufacturer collection points.
3. Add short “do not include personal or health data” helper copy to any new
   evidence/free-text form.
4. Document retention jobs and deletion outcomes; a policy sentence alone is
   insufficient.
5. Keep admin report RPCs restricted and avoid exposing install IDs in admin list
   payloads (current RPC already omits them from list/detail output).
6. Record notice version/date accepted where consent/acknowledgment is required.
