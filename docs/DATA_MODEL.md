# Sherko Pharma — Data Rules

Status: SP-003 defines the initial versioned product schema and corrected-source mapping. No production schema or import has been deployed.

## Product identity and creation

- Each product has a stable identity independent of its name, barcode, and price. Duplicate barcode matches must not merge distinct products.
- Creating a product requires at least one nonempty name, Arabic or English, and a positive whole-number selling price with an explicit supported currency. The other language's name is optional. Whitespace-only names do not satisfy this requirement; editing must not leave both names empty.
- A barcode is optional. Products without a barcode can be found through search and selected manually.
- Preserve source properties during preparation; do not invent missing values or silently discard records.
- Barcodes are text identifiers. Preserve their characters and leading zeros. Both `barcode` and `barcode2` identify the same product and sellable package; either code is eligible for lookup.
- Look up a scanned code across both fields and deduplicate results by product identity. Matching both fields of one product produces one candidate, not two additions. Matching distinct products across either field requires user selection; do not privilege the primary field or silently pick the first result.
- Empty barcode fields are not identifiers and must not participate in lookup. A product with both fields empty remains searchable by its other properties.

## Editable catalog fields

The owner approved editing all of the following in the current application:

| Field | Rule |
| --- | --- |
| Arabic name and English name | At least one must remain nonempty; no automatic translation required |
| Composition / active ingredients | Preserve supplied content; editable |
| Manufacturer / company | Editable |
| Strength | Editable |
| Dosage form | Editable |
| Package description | Editable; does not introduce fractional-package conversion |
| Primary and secondary barcodes | Both editable and optional; retain text and ambiguity rules |
| Selling amount and currency | Editable together; follow the price rules below |
| Notes | Editable |

These edits persist centrally under the existing owner authorization, confirmed-save, and revision-conflict rules. This approval covers the listed fields, not every source column or internal database identifier. Preserve other supplied properties without exposing additional editing controls until their behavior is specified. Editing a selected field must not clear unrelated fields omitted from the form.

## Selling price and currency

- Each product has one current selling amount and currency. Different products may use different currencies in the same order.
- Supported initial currencies: Syrian pound (`SYP`) and US dollar (`USD`).
- The owner confirmed that all current selling-price values in the corrected initial CSV are in SYP. Assign explicit `SYP` currency during that controlled import without converting the amounts. This source-specific mapping does not force later edits or new products to use SYP.
- Amounts are whole currency units only, including USD: no cents or fractional prices in the current scope. Do not silently round fractional source values to make them valid.
- Store and validate the currency explicitly. Never infer currency from the amount, language, device locale, or currency of another product.
- The selling price is distinct from any purchase price. Do not substitute purchase price when selling price is missing.
- A product with a missing or zero selling price cannot be added to an order. Show a clear message and require correction of its catalog price before addition. Do not treat an unknown amount as free.
- Reject negative or fractional prices for new products and price edits. Missing/unknown currency also prevents a valid order addition until resolved; source anomalies must be reported for correction.
- Price and currency form one value and must be read/saved together. A changed currency label must never silently reinterpret a previously captured order amount.
- Exact numeric limits and import anomaly handling must be specified during schema design; detect overflow instead of silently wrapping or truncating totals.

## Order calculations and persistence

- Capture the selling amount and currency when the product is first added, together with product identity and quantity.
- The package represented by the product is the quantity unit; fractional-package sales remain outside scope.
- Calculate line amount as captured unit amount multiplied by quantity, using exact integer arithmetic.
- Sum lines separately by captured currency. Display explicit currency labels. Never calculate a grand total by adding USD and SYP amounts.
- No exchange-rate configuration, automatic conversion, or converted combined total is included.
- Quantity edits and line removal update the relevant currency subtotal.
- Repeated deliberate scans of an existing line preserve its captured amount and currency until the owner explicitly accepts a catalog price update.
- Treat a server change to amount or currency as a price change: preserve the captured pair, notify the owner, and provide the existing explicit update option. An accepted currency change moves the line's value to the corresponding subtotal atomically; it does not convert the old price.
- Do not accept an update to an invalid/missing price as a valid order price. Preserve the captured value and explain the problem.
- Persist captured amounts and currencies with quantities in the session snapshot. Restore without reassigning currencies from current catalog values.

Example acceptance case: two units at `5 USD` and three at `1000 SYP` produce `10 USD` and `3000 SYP`, never an unlabelled `3010`. Removing the USD line leaves only the SYP subtotal as a nonzero total.

## Catalog persistence

- Supabase is authoritative. New products and edits persist after closing the application; a source reimport must not overwrite later edits.
- Follow the confirmed server-save and concurrent-edit rules in `ARCHITECTURE.md`.
- Keep the full source CSV out of application assets and public repository content.

## Source mapping and database identity

- The complete corrected-source mapping and anomaly rules are defined in [SOURCE_MAPPING.md](SOURCE_MAPPING.md).
- `products.id` is a generated UUID independent of every source identifier and editable catalog field.
- Corrected-source rows preserve explicit source identifiers, source purchase amount, a versioned dataset key, and the complete original row payload.
- Canonical barcode fields are nullable text and deliberately non-unique.
- The schema stores a positive revision and advances it on accepted updates; SP-004 owns the atomic expected-revision mutation API and authorization.
- Zero selling amount is allowed only to represent a source-import anomaly. Ordinary/manual product rows require a positive amount.

Use `PRODUCT.md` for user-visible requirements, `ARCHITECTURE.md` for implementation boundaries, and `QUALITY.md` for verification gates.
