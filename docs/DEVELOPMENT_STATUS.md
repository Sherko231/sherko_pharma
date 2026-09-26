# Sherko Pharma — Development Status

Updated: 2026-09-26
Active task: [SP-012 / Issue #27](https://github.com/Sherko231/sherko_pharma/issues/27).
Branch: `feat/sp-012-scoped-refresh`.
PR: [#28](https://github.com/Sherko231/sherko_pharma/pull/28).
Status: SP-011 is merged with passing post-merge CI. SP-012 scoped automatic refresh and explicit order price-change handling are implemented on the task branch and are under current-revision CI/review.

## Verified baseline

- Protected `main` is at `594ad8b3958f64fa274c2debdf542364e589f6aa`, the SP-011 merge from PR #26.
- SP-000 through SP-011 and CI-001 are merged.
- Issue #25 is closed as completed and PR #26 is merged; post-merge CI run `36150363815` passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.
- No open Issue or PR existed immediately before SP-012 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

## SP-012 contract

- Refresh only catalog data currently relevant to the authenticated protected session: the active nonblank search, currently loaded product detail, and products already present in the active order.
- Refresh after application resume and retry with bounded polling while the protected app remains active; do not add a background service, full-table subscription, or local catalog replica.
- Preserve last-known visible search/detail/order state when a refresh fails and expose a recoverable stale/refresh warning.
- Re-read a selected product through the bounded `catalog_get` API before adding a new order line so a stale search result cannot silently capture an outdated server price.
- Preserve an existing order line's captured amount/currency when the server pair changes. Show the latest pair and require explicit owner acceptance before changing totals.
- Accept a new valid amount/currency atomically, preserve quantity, update the observed product revision, and recompute separate SYP/USD totals without conversion.
- Reject zero/invalid/unsupported or overflowing latest prices without changing the captured order.
- Refresh non-price order metadata/revision when the authoritative amount/currency pair remains unchanged.
- Discard refresh results that belong to an older lifecycle generation or authenticated identity.
- No scanner work, direct product-table reads, full catalog cache, cloud order sync, inventory, sales history, or new paid service belongs to SP-012.

## Implementation state

- Added a scoped refresh coordinator using existing Riverpod controllers and the existing bounded catalog repository; no dependency or backend schema change was introduced.
- The protected shell activates refresh after restoration, refreshes on resume, pauses refresh while inactive, and performs a bounded two-minute poll only while active.
- Active search and detail controllers support non-destructive refresh: a transient server failure keeps last-known visible data and marks it stale instead of replacing it with empty/error content.
- Active order lines are refreshed individually with `catalog_get`; a server price/currency change creates a per-line notice while leaving captured totals unchanged.
- Explicit price acceptance validates the new pair, checks exact-integer overflow, updates the line atomically, and then flows through the existing SP-011 session persistence listener.
- Catalog additions re-read the exact product before adding. A failed revalidation leaves the order unchanged rather than using a stale search result.
- Account/lifecycle generation checks prevent late refresh responses from repopulating a signed-out, inactive, or different-account session.
- Product create/edit success refreshes relevant visible catalog state without creating an offline mutation queue or full-catalog invalidation.

## Verification

Requirement-derived tests were added for stale-safe search/detail refresh, lifecycle resume refresh, active-order reconciliation, explicit SYP/USD price acceptance, invalid/overflowing latest prices, recovery after refresh failure, current-price add-to-order behavior, and stale prior-account response rejection.

PR #28 uses the full application gate matrix. A fresh current-revision CI run, separate diff review, merge eligibility check, merge verification, and post-merge CI are still required before SP-012 is complete.

No hardware acceptance applies to SP-012 because camera and external-reader behavior are unchanged.
