# Sherko Pharma — Development Status

Updated: 2026-09-25
Active task: [SP-008 / Issue #19](https://github.com/Sherko231/sherko_pharma/issues/19).
Branch: `feat/sp-008-product-editor`.
PR: [#20](https://github.com/Sherko231/sherko_pharma/pull/20).
Status: Product create/edit implementation, additive idempotent-create migration, and requirement-derived regressions are on the task branch. Final current-revision CI and separate review remain pending.

## Verified baseline

- Protected `main` was `efd87540435624dcd8af52495f6675a1ff2cdb1f` when SP-008 started.
- SP-000 through SP-007 and CI-001 are merged.
- SP-007 post-merge run 36059319010 passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.
- No open Issue or PR existed before SP-008 was authorized.
- The dedicated Sherko Pharma Supabase project remains on the Free plan; SP-003/SP-004 and owner auth are deployed.
- The hosted catalog still has 0 products because the real corrected source import remains undeployed. SP-008 automated verification does not mutate the hosted catalog.

## SP-008 implementation

- New and edit forms expose exactly the approved canonical fields: English/Arabic names, composition, manufacturer, strength, dosage form, package description, both barcodes, selling amount/currency, and notes.
- Validation accepts either language name alone, rejects both names blank/whitespace-only, requires a positive whole-number selling amount, and restricts currency to SYP/USD.
- Barcode values remain text and preserve leading zeros/non-digit characters.
- New-product forms generate one RFC4122-shaped random UUID and retain it across safe retries.
- Migration `0003_idempotent_catalog_create.sql` adds `catalog_create_idempotent` without changing the legacy SP-004 create RPC.
- Exact create replay with the same UUID/input returns the same row; mismatched replay raises SQLSTATE `40001`. Anonymous/non-owner access remains denied and manual create does not populate source provenance.
- The client mutation repository uses only owner-authorized RPCs. No direct `products` table access was added.
- Create/update failures reconcile through `catalog_get` before a retry is considered safe. An unreadable outcome becomes an explicit uncertain state and blind retry is blocked.
- Revision conflicts retain local input. The owner can Stay, Use server version, or explicitly Overwrite with current changes against the latest observed revision.
- Dirty back/app navigation offers Save, Discard Changes, or Stay. Save leaves the form only after a confirmed server row; failed/conflicted/uncertain writes keep the form.
- Persistent unfinished drafts are not added; they remain SP-009.
- Catalog exposes New product and product detail exposes Edit product. Confirmed results update/open product detail.
- No delete API/UI, order mutation, scanner flow, offline mutation queue, full catalog cache, dependency addition, or paid service was introduced.

## Verification

Requirement-derived coverage includes:

- idempotent create replay, mismatched replay conflict, owner authorization, and source-provenance preservation in isolated PostgreSQL;
- exact create/update RPC parameter mapping;
- mutation reconciliation for confirmed, definitely-not-applied, conflict, missing, and uncertain outcomes;
- English-only and Arabic-only name acceptance, whitespace-name rejection, positive whole-integer price validation, supported currency validation, and exact barcode text;
- create/edit widget flows;
- failed-save input retention;
- uncertain create status checking with the same stable UUID;
- dirty-navigation Save / Discard Changes / Stay;
- conflict Use server version and explicit Overwrite paths;
- existing auth/search/detail regressions.

Early CI findings were implementation-test harness issues only: the idempotent SQL conflict target was changed to the named primary-key constraint to avoid PL/pgSQL output-column ambiguity, and the long-form validation widget test scrolls to price feedback because Flutter lazily builds the form ListView. No product requirement or assertion was removed.

No hardware acceptance or sensitive-change exception applies. The final branch revision must still pass full Quality, Schema, Android, Windows, and Required verification gates plus separate diff review before merge. After merge, the additive migration must be applied/read back on the dedicated hosted project before the hosted app can use the new create RPC.
