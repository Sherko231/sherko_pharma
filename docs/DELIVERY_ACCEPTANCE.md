# SP-015 — Initial delivery acceptance

This checklist records the current initial-delivery scope and the evidence that exists before public distribution. It separates implemented/verified product behavior from external owner-only release actions.

## Current-scope acceptance matrix

| Area | Current evidence | Delivery status |
| --- | --- | --- |
| Hosted catalog schema, source mapping, owner-only API | SP-003/SP-004 migrations and historical isolated authorization/API verification | Verified baseline |
| Controlled initial catalog import | Dedicated hosted project contains exactly 23,750 approved source rows; `IMPORT.md` records fingerprint, rerun protection, and recovery procedure | Verified |
| Owner authentication/session gate | Automated auth/configuration/storage regressions pass; real Windows login/restart/sign-out acceptance is recorded in `AUTH_ACCEPTANCE.md` | Verified on Windows; Android-specific real auth checklist remains deferred |
| Catalog search/detail | SP-007 server-backed bounded search/detail regressions remain in the Flutter suite | Verified |
| Product create/edit and conflicts | SP-008 validation, confirmed-save, uncertain-outcome, and revision-conflict regressions remain in the Flutter suite | Verified |
| Persistent edit drafts | SP-009 account-scoped draft restoration/no-auto-upload regressions remain in the Flutter suite | Verified |
| Manual order calculator | SP-010 exact integer SYP/USD totals, quantity/removal, invalid-price, and New Order regressions remain in the Flutter suite | Verified |
| Order/session persistence and account isolation | SP-011 restart/sign-out/account-isolation/reset/late-response regressions remain in the Flutter suite | Verified |
| Scoped refresh and price changes | SP-012 bounded refresh and explicit captured-price/currency update regressions remain in the Flutter suite | Verified |
| Android camera barcode scanning | SP-013 automated barcode/duplicate-frame/failure-path coverage plus owner real-camera PASS on 2026-09-26 | Verified for current scanner behavior |
| Informational DDI repository implementation | SP-030–SP-037 trusted ingredient identity, typed provider client, complete batching/lifecycle/UI/detail flow, exact provider pair/summary integrity checks, privacy/transience rules and synthetic end-to-end regression | Repository implementation complete; not production-activated |
| DDI hosted backend | Repository migrations SP-025–SP-028 and SP-031/0013 are not deployed by the DDI tasks; hosted environment is documented through SP-024 only | Blocked pending separate owner-authorized migration/deployment + verification |
| DDI Android/Windows real-client acceptance | No SP-037 owner real-device DDI run is recorded | Pending owner acceptance |
| DDI public/commercial distribution permission | September 2026 Interaction Checker terms require disclaimer/backlink and prohibit building/selling the output as a clinical decision-support product | Blocked until compatible permission/license/source is obtained |
| Windows external barcode reader | Owner deferred SP-014 on 2026-09-26 | Deferred; not a SP-015 blocker |
| Android release identity/signing configuration | `com.samo.sherkopharma`; production release requires external private `key.properties`/keystore | Release configuration established; real production key remains owner-only |
| Windows release identity/bundle | Executable/window metadata use Sherko Pharma; local release build procedure is documented | No production code-signing certificate is configured |
| Artifact publication | No automated hosted artifact publication | Owner-controlled local handoff only |

## Current verification policy

The automated SP-015 CI evidence was historical delivery evidence at the time it ran. OPS-001 / Issue #42 retires hosted CI and Required verification as current requirements. Local commands remain optional, and the owner may pull/test the merged revision and report failures for follow-up fixes.

## Remaining owner-only actions before a public production release

These do not authorize new product features:

- create/select and securely back up the real Android upload/signing key;
- if distributing Windows publicly, choose the distribution channel and satisfy its installer/code-signing requirements;
- confirm Android real sign-in/session-restoration behavior if the previously deferred SP-006 Android physical checklist is required for the intended distribution;
- verify final store/package naming availability and store metadata before submission;
- build from the reviewed merged commit with the intended client runtime configuration and record final artifact checksums;
- before enabling DDI against the hosted project, separately authorize/deploy/verify the required repository migrations (SP-025–SP-028 and SP-031/0013);
- perform Android/Windows manual acceptance of the DDI Cart states, detail sheet and external links on the intended configured artifact;
- for any public/commercial build that contains enabled Interaction Checker output, obtain compatible provider permission/license or replace the source; the current September 2026 terms do not authorize clinical-decision-support distribution.

Until those external actions are satisfied for a concrete artifact, the project should not be described as a publicly production-signed release.
