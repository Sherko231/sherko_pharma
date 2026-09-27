# Sherko Pharma — Interaction Flows

Status: Core interaction and session rules confirmed. SP-022 refines the single Cart into a POS-style workspace with persistent cart context, transient search results, a unified search/scan command surface, and adaptive supporting-pane layout. Initial UI labels are in English; Arabic explanations in the planning conversation describe their meaning.

Use `PRODUCT.md` for scope, `DATA_MODEL.md` for data rules, and `ARCHITECTURE.md` for persistence and connectivity boundaries.

## Primary Cart workflow

- After authentication, open the `Cart` workspace directly. Do not require switching between Catalog and Order pages.
- Keep manual catalog search, Android Scan, cart totals, `New Order`, current lines and quantity/remove controls on the same page.
- Treat search and scanner as acquisition modes in one command surface: tapping Scan clears/dismisses an active manual search, and tapping Search closes an open scanner so the user does not manage two competing input surfaces.
- Manual search results appear as a temporary elevated result surface anchored to the search controls. They may overlap the cart visually but must not reflow or permanently shrink it.
- Tapping Add revalidates the selected product through the existing authoritative catalog read before capture. On successful add/increment, clear the query and keep the search field ready for rapid entry of the next product.
- Keep cart item count, SYP/USD totals and New Order visible above the independently scrolling cart lines.
- Use flat list rows with dividers for the cart. Prioritize product identity, line total and quantity controls; use secondary styling for unit price and de-emphasize destructive Remove.
- On wider desktop layouts, search/scanning occupy a supporting side pane while the cart remains the main pane. On phones, stack the same workflow vertically without introducing a separate destination.
- Product detail/create/edit remain focused secondary routes and return to the same Cart workspace.
- Empty-cart guidance should point to Search or Scan on the current page.

## Start a new customer order

- Provide a `New Order` action on the Cart workspace.
- If the current order contains products, show a confirmation explaining that its items will be cleared and no historical sale will be saved. Suggested actions: `Cancel` and `Clear and Start New`.
- Cancel or dismiss: leave the order, quantities, captured prices/currencies, and saved session unchanged.
- Confirm: clear all order lines and currency totals, remain in Cart, and persist the new empty active order.
- An already empty order does not require a destructive-action confirmation.
- Do not create a sales-history entry, checkout record, or stock movement.
- Do not restore the previous order after a successfully persisted reset. If persistence fails, show an explicit error; do not silently claim a durable reset.
- Discard results from lookups initiated for the previous order so a late response cannot add its product to the newly started order.

## Leave an edited product without saving

When the owner attempts to leave the product-edit screen using in-app navigation or back navigation:

| State or choice | Result |
| --- | --- |
| No unsaved changes | Navigate normally |
| Unsaved changes | Offer `Save`, `Discard Changes`, and `Stay` |
| `Stay` or dialog dismissal | Remain in the form and retain input; do not write to the server |
| `Discard Changes` | Discard only the unsaved form changes and continue the requested navigation; do not revert earlier confirmed server edits |
| `Save` with valid input | Submit through the normal authenticated server-save flow; navigate only after confirmed success |
| Validation error, server error, or connection failure | Remain in the form, retain input, and show the problem; do not claim success |
| Revision conflict | Remain in the resolution flow and require the owner's choice under the existing conflict rules; do not overwrite the newer version silently |

If the write outcome is uncertain, reconcile it before retrying or claiming it failed/succeeded. This follows the existing server-save rules; it does not introduce automatic offline writes.

These navigation choices do not establish that an operating-system termination can be intercepted. Persist unfinished edits during editing as described below instead of relying on a close prompt.

## Resolve a concurrent catalog edit

When a revision-checked product update reports that the server row changed since editing began:

- Keep the local form input visible; do not silently replace it.
- Fetch/show the latest server row when available.
- `Stay`: keep the local input and make no server write.
- `Use server version`: explicitly discard the current unsaved local edits and load the latest server row as the new clean baseline.
- `Overwrite with my changes`: explicitly resubmit the current form values using the latest observed server revision. If another edit wins before that write, show conflict resolution again.
- If the latest row cannot be loaded, keep the local input and require a retry of the server read before overwrite is available.
- A conflict is not a successful save and must not navigate away automatically.

These choices are an explicit resolution step; the default remains optimistic concurrency with no silent last-writer-wins behavior.

## Restore an unfinished edit

- Save the active product-edit form locally as a draft while the owner changes it, so it can be resumed after closing or terminating and reopening the application.
- After authentication as the same owner, restore the edited values and clearly identify them as an unsaved draft. Draft restoration must not show a server-save success message.
- Do not upload the draft on startup, reconnect, restoration, or a timer. Only the owner's explicit Save action may submit it, with connectivity, validation, and normal server confirmation.
- Preserve the original product identity and the server revision on which editing began. Fetching a newer version must not silently replace draft input or rebase its revision; use the agreed conflict resolution before overwriting newer server data.
- Clear the corresponding persisted draft after a confirmed successful save or explicit Discard Changes. Stay, validation failure, network failure, and unresolved conflicts retain it.
- If server-save outcome is uncertain, retain and reconcile the draft before retrying. A stale draft recovered after an interrupted save must not cause an automatic second write.
- A local storage error must be visible; do not promise that a draft is safely persisted if the write failed.
- Drafts are device-local session data, not a full offline catalog, cloud-synchronized drafts, or a queue of pending server mutations.

## Existing confirmed interaction constraints

- A barcode with no match shows a message and leaves the order unchanged. Product creation is a separate action.
- Ambiguous barcode matches display distinct products for selection; cancelling selection leaves the order unchanged.
- A missing or zero product price prevents addition and explains that the catalog price needs correction.
- Server price/currency changes preserve captured order values, show a notice, and offer an explicit update.
- Restore the active order and page/location after restart, protecting the session through authentication. Do not confuse session restoration with historical sales storage.

## Session restoration and sign-out

- Restore the customer order into Cart and restore the active edit draft as already specified. Legacy persisted page identifiers must not reintroduce separate Catalog/Order navigation. Restoring search text or the exact list scroll position is not required; those controls may return to their initial state. Filter restoration is not an initial acceptance requirement.
- Signing out retains the current order and unfinished edit draft on that device. It does not clear them, complete a sale, or upload the draft.
- Show the signed-out/login UI and remove protected order/draft content from the visible application state. Only successful authentication as the same account can restore its retained session.
- A different account must never receive another account's order or draft. Retention is device-local and does not introduce cross-device session synchronization.
- When signing out from a changed form, preserve its draft under the confirmed retention rule; do not treat sign-out as an implicit Discard or Save. General navigation away from an edit form still follows the existing three-choice flow.

## Durable visual rules

- Treat compact density as the default across application UI: prefer concise headers, small intentional gaps, compact controls and bounded inline panels while preserving readability and usable interaction targets.
- Use visual hierarchy instead of repeated cards: primary acquisition controls and totals may use contained surfaces, while repeated cart/search rows should normally be flat list items separated by subtle dividers.
- Search results are transient foreground context; the active cart is persistent background context.
- On large windows, prefer a supporting pane for secondary acquisition tools while retaining the cart as the primary pane.
- Format whole-unit monetary values with comma thousands grouping (for example `245,000`) everywhere they are displayed or edited; domain/storage values remain integers.
- Prefer same-page inline interactions when they are part of one operational flow rather than adding navigation destinations.

## UX reference basis

SP-022 uses current retail/POS and adaptive-layout guidance as reference, without importing their unrelated payment/inventory features:

- Shopify POS product search keeps the cart visible while search is active and supports direct add from search results: https://help.shopify.com/en/manual/sell-in-person/shopify-pos/inventory-management/searching-for-products
- Square Retail treats checkout/cart as the operational home and supports adding by barcode scan or keyword search: https://squareup.com/help/ca/en/article/8238-build-your-customer-s-cart-in-the-square-retail-pos-app
- Material/Android search guidance recommends a persistent search control when search is a primary task: https://developer.android.com/develop/ui/compose/components/search-bar
- Android adaptive guidance recommends supporting/list-detail panes on larger windows instead of stretching one compact layout: https://developer.android.com/develop/adaptive-apps/guides/build-a-supporting-pane-layout

## Remaining decisions

- Fine-grained visual polish may evolve within the permanent compact-density rules above.
