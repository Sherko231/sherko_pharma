# SP-015 — Initial delivery acceptance

This checklist records the current initial-delivery scope and the evidence that exists before public distribution. It separates implemented/verified product behavior from external owner-only release actions.

## Current-scope acceptance matrix

| Area | Current evidence | Delivery status |
| --- | --- | --- |
| Hosted catalog schema, source mapping, owner-only API | SP-003/SP-004 migrations and isolated authorization/API tests remain in full CI | Verified |
| Controlled initial catalog import | Dedicated hosted project contains exactly 23,750 approved source rows; `IMPORT.md` records fingerprint, rerun protection, and recovery procedure | Verified |
| Owner authentication/session gate | Automated auth/configuration/storage regressions pass; real Windows login/restart/sign-out acceptance is recorded in `AUTH_ACCEPTANCE.md` | Verified on Windows; Android-specific real auth checklist remains deferred |
| Catalog search/detail | SP-007 server-backed bounded search/detail regressions remain in the Flutter suite | Verified |
| Product create/edit and conflicts | SP-008 validation, confirmed-save, uncertain-outcome, and revision-conflict regressions remain in the Flutter suite | Verified |
| Persistent edit drafts | SP-009 account-scoped draft restoration/no-auto-upload regressions remain in the Flutter suite | Verified |
| Manual order calculator | SP-010 exact integer SYP/USD totals, quantity/removal, invalid-price, and New Order regressions remain in the Flutter suite | Verified |
| Order/session persistence and account isolation | SP-011 restart/sign-out/account-isolation/reset/late-response regressions remain in the Flutter suite | Verified |
| Scoped refresh and price changes | SP-012 bounded refresh and explicit captured-price/currency update regressions remain in the Flutter suite | Verified |
| Android camera barcode scanning | SP-013 automated barcode/duplicate-frame/failure-path coverage plus owner real-camera PASS on 2026-09-26 | Verified for current scanner behavior |
| Windows external barcode reader | Owner deferred SP-014 on 2026-09-26 | Deferred; not a SP-015 blocker |
| Android release identity/signing configuration | `com.samo.sherkopharma`; production release requires external private `key.properties`/keystore; CI exercises release signing with a disposable synthetic key | Verified by SP-015 CI; real production key remains owner-only |
| Windows release identity/bundle | Release-mode bundle built by CI; executable/window metadata use Sherko Pharma | Verified by SP-015 CI; no production code-signing certificate is configured |
| Artifact publication | CI intentionally retains no distributable release artifacts | Owner-controlled handoff only |

## Required SP-015 verification

The final SP-015 revision must pass:

- `python tool/verify.py docs`;
- verification-tool unit tests;
- `python tool/verify.py quick`;
- isolated Schema/API/import suite;
- Android signed release APK build using the CI-only disposable signing key;
- Windows release build;
- `Required verification`;
- separate full-diff review.

The PR/Issue handoff records the exact reviewed SHA, CI run, merge SHA, and post-merge CI result.

## Remaining owner-only actions before a public production release

These do not authorize new product features:

- create/select and securely back up the real Android upload/signing key;
- if distributing Windows publicly, choose the distribution channel and satisfy its installer/code-signing requirements;
- confirm Android real sign-in/session-restoration behavior if the previously deferred SP-006 Android physical checklist is required for the intended distribution;
- verify final store/package naming availability and store metadata before submission;
- build from the reviewed merged commit with the intended client runtime configuration and record final artifact checksums.

Until those external actions are satisfied for a concrete artifact, repository CI proves a release-mode delivery candidate, not a publicly production-signed release.
