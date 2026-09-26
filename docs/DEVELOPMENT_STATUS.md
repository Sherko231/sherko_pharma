# Sherko Pharma — Development Status

Updated: 2026-09-26
Active task: [SP-013 / Issue #29](https://github.com/Sherko231/sherko_pharma/issues/29).
Branch: `feat/sp-013-android-camera-scanning`.
PR: [#30](https://github.com/Sherko231/sherko_pharma/pull/30).
Status: SP-012 is merged with passing post-merge CI. SP-013 Android camera scanning is implemented and reviewed on the task branch; current-revision CI passed and the owner explicitly accepted the real Android camera behavior on 2026-09-26. Final merge and post-merge CI verification remain.

## Verified baseline

- Protected `main` is at `334d61444f56d193897e713a6bd2b44deff7d975`, the SP-012 merge from PR #28.
- SP-000 through SP-012 and CI-001 are merged.
- Issue #27 is closed as completed and PR #28 is merged; post-merge CI run `36235010740` passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.
- No open Issue or PR existed immediately before SP-012 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

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

PR #30 uses the full application gate matrix. CI run `36244877949` passed Change scope, Quality, Schema, Android build, Windows build, and Required verification on reviewed SHA `5f6c07a05f2153c8ab052c4545204864a30e1213`. Separate diff review found no blocking findings. The owner explicitly reported the real Android camera test as PASS on 2026-09-26. Final merge eligibility, merge verification, and post-merge CI remain.
