# Sherko Pharma — Product Requirements

Status: Initial product scope agreed with the owner; implementation details remain to be specified.
Repository: `sherko_pharma`
Updated: 2026-09-23

## Purpose and users

Provide an online medicine catalog and a customer order calculator for pharmacy use. The initial user is the project owner. Commercial distribution is a future goal, not a requirement to implement licensing or multiple-user management in this version.

The order screen calculates separate currency totals for selected products. It does not record completed sales or manage inventory.

## Platforms and language

- Initial platforms: Android and Windows.
- The initial interface is English. Existing Arabic data and temporary Arabic interface text are acceptable.
- Full Arabic interface localization is deferred. Arabic product data must remain readable in the initial version.
- Supabase holds the authoritative catalog. Catalog browsing/search, resolving a scan to a product, and product creation/editing require a working server connection.
- Do not download or bundle the complete catalog on the device. Offline catalog operation is deferred.
- Preserve the current session across interruptions and restarts. Local session storage contains only the data needed to resume the screen, customer order, and active unfinished product-edit draft; it is not a full catalog cache.

## Authentication and access

- Sign in with email and password using the owner's pre-provisioned account.
- No in-app account registration in this version.
- Server-side authorization restricts catalog access and editing to the owner's account. Hiding interface controls is not authorization.
- Licensing is separate and remains deferred.

## Catalog and source data

- Initial source for controlled server-side import: the corrected `sy-database(2).csv` supplied by the owner. It is not a shipped application asset.
- The inspected file contains 23,750 records and 25 columns. Records may include non-medicine pharmacy products; do not assume every record is a medicine.
- Preserve product names, composition, manufacturer, strength, dosage form, package description, prices, barcodes, and other supplied properties during data preparation. Full source-to-schema mapping and display layout remain to be specified.
- Allow editing Arabic and English names, composition, manufacturer/company, strength, dosage form, package description, both barcodes, selling price and currency, and notes. See `DATA_MODEL.md`. This does not authorize editing every source column or internal identifier.
- Search by Arabic name, English name, and active ingredient/composition.
- Allow the user to create products and edit catalog data manually.
- Source data provides the initial server values. User edits and new products are saved to Supabase and persist after closing and reopening the app. Successfully saved server values become authoritative across the owner's devices.
- Catalog edits are not temporary overrides for a single customer order. The editing feature is an interim administration mechanism, but its saved changes are persistent.
- Restarting the application must not overwrite saved edits with the original source values.
- Catalog mutations require connectivity. Show success only after confirming server persistence. Offline pending-write queues are deferred.
- Leaving an edited product form through app/back navigation offers Save, Discard Changes, or Stay. Saving navigates away only after server confirmation; failure retains input on the form. See `UX_FLOWS.md`.
- Refresh relevant displayed catalog data automatically while connected, including after reconnecting. Do not require a manual catalog download or replicate the whole catalog.
- If competing edits affect the same product, show a conflict and let the owner choose rather than silently overwriting a change.
- The catalog price field `price` is the selling price. Each product has an explicit currency, initially SYP or USD; products using different currencies can coexist. The owner confirmed that all current source CSV selling prices are in SYP; label them accordingly during initial import without conversion. `purchasePrice` must not be substituted for the selling price in customer totals.
- Selling prices are whole currency units only, including USD. Products with missing or zero selling prices cannot be added to an order until their catalog prices are corrected.
- New products require at least one nonempty name in Arabic or English and a positive integer selling price with a supported currency. The second language's name and barcodes are optional; products without a barcode remain available through search. Editing cannot leave both names empty.

## Barcode lookup

- Support camera barcode scanning on Android. Windows external-reader integration is deferred from the current initial delivery and remains a future hardware task that requires separate owner re-authorization after the reader model and input mode are selected. External readers on Android and camera scanning on Windows are also outside the current initial scope.
- Resolve the scanned barcode against both `barcode` and `barcode2`: either identifies the same product and package. Deduplicate matches by product identity; the same product matching both fields is one candidate. A code matching distinct products in either field remains ambiguous and requires selection.
- One matching product: add the product to the current order.
- Multiple matching products: display choices and let the user choose before adding anything.
- No matching product: display a not-found message and leave the order unchanged. Do not automatically create a product, link a barcode, or open a creation flow.
- Product creation remains separately available from catalog management.
- Treat barcode identifiers as text, preserving their exact characters and leading zeros.

### Source observations, not additional product features

In the corrected file, neither barcode column contains scientific-notation values. The primary `barcode` column has 8,260 blank entries and seven distinct values that each occur in multiple records. The secondary `barcode2` column also contains blanks and one duplicated value. Some nonempty barcode entries contain non-digit characters.

These observations do not establish that all supplied codes are valid or correspond to real packages. The owner confirmed that the secondary column is an alternative identifier for the same product/package. Apply the matching and cross-column ambiguity rules in `DATA_MODEL.md`; further source validation remains necessary. Do not silently discard records or choose the first match for an ambiguous code.

## Customer order calculator

- Add products by barcode scanning or manual selection from search results.
- Display selected products, unit selling prices with currencies, quantities, and separate totals for SYP and USD as applicable.
- Repeated deliberate scans of the same selected product increase its quantity on the existing line.
- Allow quantity changes and removal of individual order lines.
- Provide a New Order action. When the current order contains products, require confirmation before clearing it. Cancellation preserves the order; confirmation clears lines/totals and persists the empty active order without creating sales history. See `UX_FLOWS.md`.
- A quantity unit refers to the sellable package represented by that source record, whether a box, sachet, or another package.
- Fractional-package calculations and conversions between boxes, strips, and individual pieces are outside this version.
- Calculate each line as unit selling price multiplied by quantity, and sum line amounts separately by currency. Do not add different currencies together or perform currency conversion.
- When a product is first added to an order, capture its current server selling amount and currency together on the order line.
- If that product's server amount or currency changes while the order is open or before a saved order is resumed, preserve its captured pair and show a notification with an explicit option to adopt a valid new price and currency together.
- Adding quantity to an existing line preserves that line's captured price until the owner explicitly updates it. A new customer order uses current server prices.
- Do not add inventory deduction, checkout records, or sales history to this scope.

## Session continuity

- Save the active session and restore it after closing and reopening the application.
- Restore the current page/location and the active order, including selected products, quantities, captured unit prices, and their currencies. Protect access to the restored session through the sign-in flow.
- Persist and restore the active unfinished product edit as a local unsaved draft. Upload only after the owner explicitly chooses Save; restoring or reconnecting must not submit it. Preserve the original revision for conflict detection, and clear the draft after confirmed save or explicit discard. See `UX_FLOWS.md`.
- Restoring search text and exact list scroll position is not required. Filter restoration is not an initial acceptance requirement; this does not remove the requirement to restore the active screen, order, and edit draft.
- Signing out retains the order and edit draft on the device but hides them until successful sign-in to the same account. Never expose another account's retained session or automatically submit a draft on sign-out/sign-in. See `UX_FLOWS.md`.
- Session persistence is distinct from historical sales storage; it must not create a sales-history feature.

## Deferred scope

- Inventory quantities and stock deductions.
- Completed sales records, sales history, and editing or cancelling historical sales.
- Fractional-package sales calculations.
- Fractional currency amounts, currency conversion, and exchange-rate management.
- Full Arabic interface localization.
- User-facing backup export and restore.
- A separate administration application for product and price management. Supabase catalog storage and owner-only access are already in scope.
- Offline catalog operation, full local catalog download/encryption, and offline pending catalog writes.
- Licensing and activation.

The separate administration application will eventually replace in-app catalog editing. The current scope requires writes to the central server under owner-only authorization. The later online-only decision supersedes earlier proposals for an encrypted offline catalog and pending writes; do not implement those proposals in this version.

## Product acceptance criteria

1. On Android and Windows, an authorized owner can browse and search the server catalog while connected; connection failures are clearly distinguished from empty results.
2. Product creation and catalog edits persist on Supabase and survive a restart. Success is not shown for an unconfirmed write, and no offline catalog-write queue is created.
3. A recognized unique barcode adds the matching product; another deliberate scan increases its quantity on the same line.
4. Ambiguous barcode matches require a user selection. Cancelling selection does not add an item.
5. Unknown barcodes produce a message without modifying the order or creating a product.
6. Search supports Arabic name, English name, and active ingredient/composition, with manual addition to the order.
7. Quantity changes and line removal update the total correctly using the selling price and the source-defined package unit.
8. Closing and reopening the app restores the active order and page/location without creating a historical sale.
9. The English interface can display the supplied Arabic content readably.
10. Unauthorized or signed-out requests cannot access or modify the catalog, even outside the application UI.
11. A server price change does not silently change an existing order total. The owner is notified and can explicitly update the line price.
12. Concurrent catalog edits produce a user-resolvable conflict rather than silent replacement.
13. An order containing USD and SYP products displays separate correct totals, without conversion or a combined monetary total. Session restoration preserves each line's currency.
14. Missing or zero selling prices block addition with a clear message. New products require a name and positive whole-number selling price with currency; barcode remains optional.
15. Either Arabic name alone or English name alone satisfies the name requirement. All approved editable fields persist after a confirmed save without clearing unrelated properties.
16. Starting a new order requires confirmation when the current order is nonempty. Cancelling leaves it intact; a confirmed, successfully persisted reset does not reappear as the old order after restart.
17. Back/navigation from a changed product form offers save, discard, or stay. Failed or unconfirmed saves do not silently lose the form input or navigate away.
18. Closing and reopening restores the active unfinished edit as an unsaved draft for the same authenticated owner, without automatically modifying the server. Confirmed save or explicit discard removes the corresponding draft.
19. Signing out hides protected session content while retaining it locally. Signing back in as the same owner restores the order/draft; signed-out or different-account states cannot view them. Exact search text and scroll restoration are not required.

## Implementation questions still to resolve

These are explicit open questions, not permission to invent additional features:

- Exact display layout, complete source-to-schema mapping, and remaining validation limits; the editable fields and minimum name requirement are confirmed in `DATA_MODEL.md`.
- Scanner compatibility and the interaction for preventing repeated camera-frame additions.
- Handling invalid imported prices; see `DATA_MODEL.md` for confirmed source currency, integer-price, and per-currency rules.
- Detailed screen layout; confirmed session, sign-out, draft restoration, reset, and navigation rules are in `UX_FLOWS.md`.

Technical architecture, engineering workflow, quality gates, and delivery phases belong in their respective documents. Future ideas do not enter implementation scope until explicitly approved.
