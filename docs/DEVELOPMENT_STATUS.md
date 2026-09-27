# Sherko Pharma — Development Status

Updated: 2026-09-27
Task record: SP-016 / Issue #44 refines Android barcode responsiveness and framing. OPS-001 / Issue #42 retires hosted GitHub Actions and mandatory CI gates. REL-001 / Issue #40 and SP-015 / Issue #38 remain completed baselines.
Status: SP-016 preserves the SP-013 barcode/order contract while adding focused scan guidance and faster camera-side detection. SP-014 remains deferred. Current verification policy is owner-local after pull; hosted CI is retired.

## Verified baseline

- The latest functional feature baseline is SP-013 merge `2f00898ff7cdeb5060c215c6997c62fe5791bd26` from PR #30; later documentation-only handoff commits do not change application behavior.
- SP-000 through SP-013 and CI-001 are merged.
- Issue #29 is closed as completed and PR #30 is merged; post-merge CI run `36250531971` passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.
- No open Issue or PR existed immediately before SP-012 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

## SP-016 scanner refinement contract

- Keep the existing exact barcode identity, ambiguity, authoritative catalog re-read, order mutation, and deliberate-repeat behavior unchanged.
- Show a centered horizontal barcode guide and use the same rectangle as the actual scanner scan window.
- Keep throttled `DetectionSpeed.normal` behavior while reducing the camera-side detection timeout from 250 ms to 100 ms.
- Enable Android-supported auto zoom and tap-to-focus without restricting the accepted barcode formats.
- Pause frame analysis after the first accepted capture so retries can rearm the existing camera session quickly while repeated frames remain blocked.
- Real-device responsiveness and framing remain owner verification after pull/merge.

## SP-015 delivery contract

- Preserve the implemented SP-000 through SP-013 product behavior while preparing release-mode Android and Windows candidates.
- Android identity is `com.samo.sherkopharma`; release builds must not fall back to the Flutter debug key.
- Production signing material remains outside Git.
- Windows release packaging covers the complete runner bundle; no production code-signing claim is made without an external certificate.
- Hosted CI is retired. Owner-controlled local builds, packaging, checksums, signing, runtime configuration and testing follow `RELEASE.md` and `QUALITY.md`.
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

## Verification policy

Requirement-derived tests remain in the repository and can be run locally when useful. The owner explicitly reported the real Android camera test as PASS on 2026-09-26. Historical CI evidence from earlier completed tasks remains part of Git history, but it is no longer a current merge or completion requirement.

Under OPS-001, the owner pulls/tests revisions locally and reports problems for bounded follow-up fixes. Future SP-014 work still requires fresh owner authorization and selected hardware/input-mode evidence.
