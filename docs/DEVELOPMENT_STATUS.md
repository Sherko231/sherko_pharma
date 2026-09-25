# Sherko Pharma — Development Status

Updated: 2026-09-25
Active task: [SP-010 / Issue #23](https://github.com/Sherko231/sherko_pharma/issues/23).
Branch: `feat/sp-010-manual-order`.
PR: [#24](https://github.com/Sherko231/sherko_pharma/pull/24).
Status: SP-009 is merged. SP-010 manual customer-order calculation is implemented on the task branch and is under full CI/review.


## Verified baseline

- Protected `main` is at `41bcc69edae80a8e8337d6920231e504d81a9e1a`, the SP-009 merge from PR #22.
- SP-000 through SP-009 and CI-001 are merged.
- Issue #21 is closed as completed and PR #22 is merged; post-merge CI run 36126038712 passed.
- No open Issue or PR existed immediately before SP-009 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

## SP-010 contract

- Add valid-priced products manually from catalog search without catalog mutations.
- Keep one line per product; repeated adds increment quantity.
- Capture selling amount/currency on first add and preserve that pair for the open line.
- Use positive whole-number quantities and exact checked integer arithmetic.
- Keep SYP and USD totals separate; never convert or combine currencies.
- Reject zero/invalid selling prices and overflow without mutating the order.
- New Order confirms before clearing a nonempty in-memory order.
- No sales history, inventory movement, checkout, barcode input, automatic price refresh, or durable order persistence belongs to SP-010.

## Implementation state

- Added an order domain model and Riverpod controller with checked whole-unit arithmetic.
- Catalog search results can add products directly to the active order.
- The Order workspace now shows lines, captured unit prices, quantities, line amounts, separate SYP/USD totals, remove controls, and New Order reset.
- Existing order lines retain captured price/currency when quantity changes or the same product is added again.
- Requirement-derived controller/widget tests cover repeat add, mixed currencies, invalid price rejection, removal, reset, overflow, and catalog integration.
- SP-011 remains responsible for durable order/session restoration and account-scoped retained orders.

## Verification

Initial PR CI run 36128819449 found one analysis-only issue (`unnecessary_underscores`) in the new order screen after Schema and Android had passed; the code was corrected without changing behavior. A fresh full current-revision CI run is required before merge.

No hardware acceptance applies to SP-010. Separate diff review and post-merge CI remain required.
