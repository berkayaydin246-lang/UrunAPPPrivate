# Google Play Health And UGC Review

Review date: **8 August 2026**

No Play Console setting was changed in this phase.

## Scope Assessment

Etiketly presents food ingredient, nutrition, additive, allergen-detection and
content-profile information. It does not currently track body measurements,
diagnose conditions, prescribe treatment or present itself as a medical device.

Google requires every published app, including testing tracks, to complete the
Health Apps Declaration. The conservative likely category is **Nutrition and
Weight Management**, because the official category includes nutrition tools and
apps focused on dietary needs/goals. Etiketly does not currently offer meal
planning or weight tracking, so the exact declaration answer remains dependent
on the wording shown in the current console.

**COUNSEL/PLAY REVIEW REQUIRED:** Confirm whether Etiketly's informational food
scoring alone should be declared under “Nutrition and Weight Management”. Do not
select “no health features” without re-evaluating the actual console prompts.

## Exact Manual Play Console Actions

1. Open Play Console and go to `Policy > App content > Health apps` (the UI may
   display this under `Monitor and improve > Policy > App content`).
2. Start or reopen the Health Apps Declaration.
3. Review every feature against the shipped build. Conservatively select
   `Nutrition and Weight Management` unless Play support/counsel confirms a
   different answer.
4. Do not declare `Medical Device Apps`; Etiketly does not claim that status.
5. Confirm no health permissions/Health Connect data are requested. Current
   Android manifest uses camera and internet only for core scanning/network use.
6. Put the concise non-medical-device disclaimer from
   [PLAY_STORE_LEGAL_COPY_TR.md](./PLAY_STORE_LEGAL_COPY_TR.md) in the store
   description.
7. Ensure the designated Privacy Policy field points to an active, public,
   non-geofenced, non-PDF HTTPS page and that the same link remains in-app.
8. Reconcile Data safety answers with actual camera/photo upload, OCR providers,
   Supabase processing, app-install ID, reports/submissions and admin auth.
9. Save screenshots/export of the submitted answers and date for the release
   record.

Official basis: [Health Content and Services](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en)
and [Health Apps Declaration instructions](https://support.google.com/googleplay/android-developer/answer/14738291?hl=en).

## Required Disclaimer Positioning

- Store listing: clear non-medical-device/no diagnosis-treatment-cure-prevention
  wording plus professional-advice reminder.
- In app: short onboarding/settings boundary and layered score methodology
  disclosure.
- Privacy policy: actual personal/sensitive data handling, not only a medical
  disclaimer.

## UGC Decision

Current product submissions and photos are sent to a private admin review flow.
Raw user submissions are not visible to other users. Approved facts may later be
incorporated into an editorial product catalogue without public user identity or
raw user post. On the present architecture this does **not** match Google's UGC
definition, which requires user-contributed content visible to at least a subset
of users.

Therefore this phase does not add social user blocking or public-content
reporting controls. Existing product-data reporting is a correction workflow,
not a social UGC moderation system.

If raw photos, user attribution, comments, reviews or submissions become visible
to users, release must be blocked until the app has:

- accepted Terms/user policy before upload;
- prohibited-content rules;
- ongoing moderation;
- in-app content/user reporting and blocking as applicable;
- content-rating and child-safety review.

Official basis: [Google Play UGC policy](https://support.google.com/googleplay/android-developer/answer/9876937?hl=en-GB).
