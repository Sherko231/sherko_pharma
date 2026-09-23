# Sherko Pharma — Interaction Flows

Status: Core interaction and session rules confirmed; detailed visual design remains open. These are requirements, not implemented screens. Initial UI labels are in English; Arabic explanations in the planning conversation describe their meaning.

Use `PRODUCT.md` for scope, `DATA_MODEL.md` for data rules, and `ARCHITECTURE.md` for persistence and connectivity boundaries.

## Start a new customer order

- Provide a `New Order` action on the customer order screen.
- If the current order contains products, show a confirmation explaining that its items will be cleared and no historical sale will be saved. Suggested actions: `Cancel` and `Clear and Start New`.
- Cancel or dismiss: leave the order, quantities, captured prices/currencies, and saved session unchanged.
- Confirm: clear all order lines and currency totals, remain on the order screen, and persist the new empty active order.
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

- Restore the active screen, customer order, and active edit draft as already specified. Restoring search text or the exact list scroll position is not required; those controls may return to their initial state. Filter restoration is not an initial acceptance requirement.
- Signing out retains the current order and unfinished edit draft on that device. It does not clear them, complete a sale, or upload the draft.
- Show the signed-out/login UI and remove protected order/draft content from the visible application state. Only successful authentication as the same account can restore its retained session.
- A different account must never receive another account's order or draft. Retention is device-local and does not introduce cross-device session synchronization.
- When signing out from a changed form, preserve its draft under the confirmed retention rule; do not treat sign-out as an implicit Discard or Save. General navigation away from an edit form still follows the existing three-choice flow.

## Remaining decisions

- Detailed screen layout and visual design.
