# Sherko Pharma — Development Status

Updated: 2026-09-25
Active task: [SP-009 / Issue #21](https://github.com/Sherko231/sherko_pharma/issues/21).
Branch: `feat/sp-009-edit-drafts`.
Status: SP-008 is merged. SP-009 persistent product-edit draft storage and restoration are implemented on PR #22; full CI run 36125103876 passed on revision `ae08562e1a0961d46c268bbf15de605660c3fe83`. Final documentation-only revision and separate review remain before merge.

## Verified baseline

- Protected `main` is at `e5fc0e9860628190e1cf0e78bcc8b67a62cea8b4`, the SP-008 merge from PR #20.
- SP-000 through SP-008 and CI-001 are merged.
- Issue #19 is closed as completed and PR #20 is merged.
- No open Issue or PR existed immediately before SP-009 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

## SP-009 contract

- Persist dirty product create/edit input locally for the authenticated owner.
- Restore only for the same account and form identity; signed-out or different-account states must not expose it.
- Preserve the original edit product revision and the stable create UUID.
- Restoring a draft must perform zero catalog mutations.
- Confirmed Save and explicit Discard clear the corresponding draft.
- Validation failure, rejected/failed save, unresolved conflict, and uncertain save outcome retain recoverable draft input.
- Persist uncertain-save metadata so restart cannot turn an unknown write result into a blind retry.
- Malformed local draft data fails closed without a server write.
- Local storage failures are visible and must not be reported as safe persistence.
- No full catalog cache, offline mutation queue, order persistence, scanner feature, delete/archive flow, or admin/user-role redesign belongs to SP-009.

## Implementation state

- Added account- and form-scoped catalog draft storage using the existing secure key-value storage dependency; no new package was introduced.
- Runtime injection keeps auth session and draft keys separate under the same Supabase-project namespace.
- Product create/edit forms restore local input asynchronously, preserve create identity/edit base revision, and keep uncertain outcomes reconcilable.
- Draft writes are serialized so a stale pending local write cannot resurrect data after a later Save/Discard clear.
- Requirement-derived tests are being added for restoration, account isolation, revision preservation, clearing, corruption, and local-storage failure behavior.
- Repository handoff documents were refreshed to record the completed 23,750-row hosted import.

## Verification

Full CI run 36125103876 passed on revision `ae08562e1a0961d46c268bbf15de605660c3fe83`:

- Change scope: passed.
- Quality: passed, including documentation checks, Python verification tests, Flutter analysis, and the full Flutter regression suite.
- Schema: passed, including migrations, authorization regressions, and controlled-import regressions.
- Android build: passed.
- Windows build: passed.
- Required verification: passed.

The final documentation-only status commit still requires its current-revision CI result and the separate diff review required by `QUALITY.md`. No hardware acceptance applies to SP-009. After merge, remote `main` and post-merge CI must be verified.
