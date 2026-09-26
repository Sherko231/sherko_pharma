# Sherko Pharma — Development Status

Updated: 2026-09-26
Task record: SP-015 / Issue #38; GitHub Issue/PR state is authoritative for live execution and merge status.
Status: SP-013 is complete, merged, and verified. SP-014 remains deferred. SP-015 is the final current-scope delivery-preparation task and does not depend on SP-014.

## Verified baseline

- The latest functional feature baseline is SP-013 merge `2f00898ff7cdeb5060c215c6997c62fe5791bd26` from PR #30; later documentation-only handoff commits do not change application behavior.
- SP-000 through SP-013 and CI-001 are merged.
- Issue #29 is closed as completed and PR #30 is merged; post-merge CI run `36250531971` passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.
- No open Issue or PR existed immediately before SP-012 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

## SP-015 delivery contract

- Preserve the implemented SP-000 through SP-013 product behavior while preparing release-mode Android and Windows candidates.
- Android identity is `com.sherko.pharma`; release builds must not fall back to the Flutter debug key.
- Production signing material remains outside Git. Hosted CI may use only a disposable synthetic key to exercise the release configuration.
- Windows release verification covers the complete runner bundle; no production code-signing claim is made without an external certificate.
- CI does not publish distributable artifacts. Owner-controlled packaging, checksums, signing, and runtime configuration follow `RELEASE.md`.
- The acceptance matrix in `DELIVERY_ACCEPTANCE.md` records deferred SP-014 and the remaining owner-only actions before public distribution.

## SP-013 contract

- Android camera scanning resolves complete barcode text through the existing bounded owner-authorized catalog API.
- Match either approved barcode field, preserve leading zeroes, deduplicate the same product identity, and reject ambiguous distinct-product matches.
- Re-read the resolved product with `catalog_get` before mutating the order so current authoritative selling values are used.
- Repeated frames from one physical presentation must not increment quantity; a deliberate later scan can increment the existing line.
- Unknown, ambiguous, invalid-price, permission, and camera interruption states are non-destructive and recoverable.
- No Windows reader integration, inventory, checkout/history, cloud order sync, full catalog cache, or production release work belongs to SP-013.

## Implementation state

- Added an Android-only order Scan action backed by `mobile_scanner`, pinned to a reviewed upstream commit in the application lockfile.
- Added exact `catalog_lookup_barcode` repository access without direct product-table reads or a new backend migration.
- Barcode lookup preserves the scanned string, deduplicates results by product ID, and treats multiple distinct product matches as ambiguous.
- The scan controller is single-flight, revalidates the resolved product with `catalog_get`, and delegates price/currency/overflow rules to the existing order controller.
- The camera stops after the first accepted frame. Failed/unknown scans require explicit rearm; successful scans return to the order, so a later deliberate scan starts a new scan session.
- Scanner lifecycle handling stops the camera while inactive and only resumes an uncommitted scan after the app returns active.
- Android camera permission is declared without making camera hardware a required installation feature.

## Verification

Requirement-derived tests cover exact barcode RPC mapping, leading-zero preservation, authoritative product revalidation, unknown/ambiguous rejection, invalid-price rejection, and concurrent duplicate-frame suppression.

PR #30 merged as `2f00898ff7cdeb5060c215c6997c62fe5791bd26`. The owner explicitly reported the real Android camera test as PASS on 2026-09-26. Post-merge CI run `36250531971` passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.

SP-013 is complete. Issue #31 / PR #32 reconciled its post-merge handoff, and post-merge CI run `36251023929` passed. On 2026-09-26 the owner deferred SP-014 Windows external-reader integration and Issue #35 was closed as not planned for now. SP-015 is tracked by Issue #38; its Issue/PR handoff records revision-specific CI, review, merge, and post-merge evidence. Future SP-014 work still requires fresh owner authorization and selected hardware/input-mode evidence.
