# Sherko Pharma — Development Status

Updated: 2026-09-25
Active task: [SP-011 / Issue #25](https://github.com/Sherko231/sherko_pharma/issues/25).
Branch: `feat/sp-011-session-persistence`.
PR: [#26](https://github.com/Sherko231/sherko_pharma/pull/26).
Status: SP-010 is merged with passing post-merge CI. SP-011 account-scoped local page/order session persistence is implemented on the task branch and is under current-revision CI/review.

## Verified baseline

- Protected `main` is at `7f9d6282a16fb30e4c61e3baf7300550c3b6f0e5`, the SP-010 merge from PR #24.
- SP-000 through SP-010 and CI-001 are merged.
- Issue #23 is closed as completed and PR #24 is merged; post-merge CI run `36130287876` passed.
- No open Issue or PR existed immediately before SP-011 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

## SP-011 contract

- Persist only the authenticated owner's active top-level page and current order snapshot needed for local restoration.
- Preserve each order line's product identity, display name, positive whole-number quantity, captured selling amount/currency, and observed product revision.
- Restore protected page/order state only after successful authentication as the exact same `userId`.
- Signing out retains that account's persisted order and existing product draft while immediately hiding protected visible/in-memory state.
- A different account must never receive, merge with, or overwrite another account's retained order/draft state.
- Confirmed New Order persists an empty order so a restart cannot resurrect the previous order.
- Local snapshot failures and corrupt/incompatible data fail closed and surface a recoverable error.
- Serialize local writes and reject stale async restore/write effects that could repopulate a cleared or different-account session.
- No order data is written to Supabase; no full catalog cache, cross-device session sync, scanner behavior, automatic price refresh, sales history, inventory, or admin-role redesign belongs to SP-011.

## Implementation state

- Added a versioned secure app-session store using the existing `flutter_secure_storage` key-value boundary with a separate project/account-scoped key namespace.
- Added a stable session coordinator that listens to authenticated identity changes without rebuilding itself across account transitions.
- Protected order/navigation memory is cleared synchronously before signed-out or different-account restoration; the protected shell remains gated until same-account restoration is ready.
- Order and navigation changes queue serialized local snapshots; stale writes remain bound to the captured owner key.
- Confirmed New Order persists the resulting empty order through the same snapshot pipeline.
- Local write/restore failures are visible in the protected shell or signed-out screen and can be retried without server mutation.
- Existing SP-009 product-draft storage remains separate and its explicit Save/Discard semantics are unchanged.
- Requirement-derived tests cover secure snapshot validation, corruption/version rejection, same-account restoration, A/B isolation, delayed writes, persistence failure/retry, restart-style UI restoration, and durable New Order clearing.

## Verification

Initial PR CI run `36148992824` passed Change scope and Schema but exposed a real auth-transition race in two session-controller tests: the first implementation rebuilt the session provider while an earlier asynchronous restore still held an invalidated Riverpod ref. The controller was changed to remain stable and listen to identity changes, clear protected memory synchronously, and check mounted/generation/owner guards after async restore. A fresh full current-revision CI run is required on the final documentation revision before merge.

No hardware acceptance applies to SP-011. Separate diff review, merge verification, and post-merge CI remain required.
