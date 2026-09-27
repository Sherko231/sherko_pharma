# Sherko Pharma — Data Rules

Status: SP-003 defines the versioned product schema and corrected-source mapping; SP-024 adds normalized manufacturer/dosage-form references and typed currency; SP-025 adds conservative derived composition normalization while preserving raw composition text. The hosted baseline through SP-024 is deployed and the approved corrected source was imported at 23,750 rows on 2026-09-25.

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

## Structured versus free-text product properties

SP-024 profiles the hosted 23,750-row catalog and structures only fields whose semantics are stable enough to normalize safely.

| Property | Storage decision | Reason |
| --- | --- | --- |
| Manufacturer / company | Reference table + product foreign key | Hundreds of reusable entities with spelling variants and future additions; a database enum would be too rigid |
| Dosage form | Reference table + product foreign key | Reusable category domain with spelling/spacing variants, but broad enough that new values must remain possible |
| Currency | PostgreSQL enum `app_private.catalog_currency` with `SYP` / `USD` | Small, explicitly finite supported domain |
| Arabic / English product name | Text | Product identity labels are open-ended |
| Composition / active ingredients | Raw text + private derived ingredient normalization | The exact catalog/source text remains unchanged. SP-025 conservatively derives ingredient identities and set keys, while ambiguous syntax is quarantined instead of guessed. |
| Strength | Raw text + private derived strength normalization | The exact catalog/source text remains unchanged. SP-026 parses only supported deterministic numeric/unit syntax, pairs it to trusted SP-025 ingredient components, and quarantines ambiguous combinations. |
| Package description | Text | Free descriptive packaging text with 2,280 distinct source values |
| Barcodes | Text | Exact identifiers; leading zeroes and non-digit characters must be preserved |
| Notes | Text | Intentionally free-form |
| Source-only provenance | Raw preserved fields / JSONB | Historical source fidelity takes priority over inferred semantics |

Manufacturer and dosage-form reference rows have stable numeric IDs, canonical display labels, normalized unique keys, and alias tables retaining every observed spelling. Existing product RPCs continue returning the canonical display strings for compatibility; products also store the corresponding foreign keys.

### Composition normalization (SP-025)

- `products.composition` remains the editable/raw display value and is never rewritten by the normalization layer.
- `app_private.catalog_ingredients` stores stable ingredient identities. Initial automatic identity resolution is lexical/deterministic only; medically similar names, salts, vitamin forms, extracts, or other semantic candidates are not fuzzy-merged.
- Ingredient alias keys are unique normalized lexical keys, while observed spellings are retained separately. The model can later hold explicitly reviewed semantic aliases without treating them as automatic text equivalence.
- `app_private.product_ingredients` stores product-to-ingredient candidates in source component order with the raw component text. SP-025 splits only on an explicit `+` separator.
- `app_private.product_composition_normalization` records an order-independent ingredient-set key plus `auto_verified`, `high_confidence`, `needs_review`, or `unresolved` status. Parenthesized/special-delimiter expressions, embedded strength units, duplicate components, and incomplete splits are not silently trusted.
- `high_confidence` is reserved for compositions that later resolve through explicitly verified semantic aliases. SP-025 seeds no semantic synonym mapping; current automatic backfill therefore uses lexical identities only.
- Every product receives a normalization summary, including blank/unresolved compositions. Existing product revision and `updated_at` values are not advanced by the structural backfill.
- A database trigger refreshes only the derived normalization rows after a future composition create/edit. Normal catalog revision/conflict behavior remains owned by the existing product update path.
- Ingredient-set equality in SP-025 means only “same conservatively normalized ingredient identities.” It is not pharmaceutical equivalence and must not by itself drive direct substitution. Strength, route/form compatibility, and release type belong to later tasks.

### Strength normalization (SP-026)

- `products.strength` remains the editable/raw display value and is never rewritten by the normalization layer.
- The live source contains presentation-style slash suffixes such as `500 MG/CTD TAB.` alongside quantitative concentrations such as `250 MG/5 ML.`; SP-026 treats these as different syntax classes.
- Supported numerator units are normalized deterministically: `G`, `MG`, and `MCG/UG` become exact `mg`; `IU`, generic `U`, `MEQ`, `MMOL`, and percent remain separate canonical unit domains. Numeric arithmetic uses PostgreSQL `numeric`, not floating point.
- Quantitative denominators support exact mass/volume normalization to `mg` or `ml`. For example, `250 MG/5 ML` gets comparison key `mg/ml:50`, while the raw 250 mg per 5 ml values remain stored separately.
- Recognized tablet/capsule/vial/ampoule/suppository and related presentation suffixes are excluded from numeric strength comparison; SP-027 remains responsible for dosage-form, route, and release compatibility.
- Explicit `+` strength components are positionally paired only when the trusted SP-025 ingredient count matches exactly. A shared final concentration denominator may apply across the explicit components, but that inference is capped at `high_confidence`.
- Mismatched counts, partial strings, missing units, unsupported shorthand, descriptive strength values, or products whose SP-025 composition is review/unresolved cannot receive a trusted ingredient-strength set key.
- `app_private.product_ingredient_strengths` stores fully trusted ingredient-strength links. `app_private.product_strength_normalization` stores the raw source snapshot, status/reason, parsing counts, and order-independent ingredient-strength set key.
- A strength-only product edit refreshes SP-026 directly. When composition and strength change together, SP-025 refreshes ingredient identities first and then SP-026 rebuilds the strength pairing. Structural backfill does not advance product revision or `updated_at`.
- SP-026 equality still does not mean direct pharmaceutical substitution. SP-027 must additionally evaluate dosage form, route, and release semantics before a strict alternative can exist.

New or edited manufacturer/dosage-form text is resolved atomically by the database trigger. A spelling-equivalent normalized value reuses the existing reference and returns its canonical display label. A genuinely new normalized value creates one new reference identity. Blank values remain nullable. Source text remains recoverable from `source_payload`.

## Selling price and currency

- Each product has one current selling amount and currency. Different products may use different currencies in the same order.
- Supported currencies are the typed database enum `app_private.catalog_currency`: Syrian pound (`SYP`) and US dollar (`USD`). RPCs continue exposing the labels as text for client compatibility.
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


## SP-004 server API boundary

- Normal client roles do not read or write `products` directly. Catalog operations use owner-authorized bounded database functions.
- Search covers Arabic name, English name and composition, treats caller text literally, and clamps results to a hard maximum of 50.
- Exact barcode lookup compares text across both barcode columns and returns each product identity once, preserving cross-product ambiguity.
- Client create/update inputs are limited to approved canonical editable fields; source provenance and revision are server-owned.
- Updates require the expected revision atomically. A stale revision is a conflict and cannot overwrite the newer row.
