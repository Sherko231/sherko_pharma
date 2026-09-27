# Sherko Pharma — Data Rules

Status: SP-003 defines the versioned product schema and corrected-source mapping; SP-024 adds normalized manufacturer/dosage-form references and typed currency; SP-025/SP-026 add conservative derived composition and strength normalization; SP-027 adds a private strict pharmaceutical-equivalence model; SP-028 exposes bounded owner-only relationship groups without changing authoritative raw catalog fields. The hosted baseline through SP-024 is deployed and the approved corrected source was imported at 23,750 rows on 2026-09-25.

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
- Explicit `+` strength components are positionally paired only when the trusted SP-025 ingredient count matches exactly. Any multi-ingredient positional pairing is capped at `high_confidence`, because it relies on source ordering; a shared final concentration denominator remains `high_confidence` as well.
- Mismatched counts, partial strings, missing units, unsupported shorthand, descriptive strength values, or products whose SP-025 composition is review/unresolved cannot receive a trusted ingredient-strength set key.
- `app_private.product_ingredient_strengths` stores fully trusted ingredient-strength links. `app_private.product_strength_normalization` stores the raw source snapshot, status/reason, parsing counts, and order-independent ingredient-strength set key.
- A strength-only product edit refreshes SP-026 directly. When composition and strength change together, SP-025 refreshes ingredient identities first and then SP-026 rebuilds the strength pairing. Structural backfill does not advance product revision or `updated_at`.
- SP-026 equality still does not mean direct pharmaceutical substitution. SP-027 must additionally evaluate dosage form, route, and release semantics before a strict alternative can exist.

### Pharmaceutical equivalence (SP-027)

- SP-027 is derived/private metadata only. It does not rewrite `products.composition`, `products.strength`, `products.dosage_form`, `dosage_form_id`, source provenance, price/currency, barcode identity, or revision state.
- `app_private.catalog_dosage_form_equivalence_profiles` classifies each SP-024 dosage-form reference into a form-class key, route class, release class, confidence/status, and reason. Unknown, mixed-route, or insufficiently specific labels remain review/unresolved.
- The route model distinguishes oral, sublingual, oromucosal, ophthalmic, otic, nasal, cutaneous, vaginal, rectal, inhalation, and an explicitly non-strict `parenteral_unspecified` state. Injection-like records do not become strict alternatives unless a future task provides a sufficiently specific route.
- Release classification distinguishes immediate, extended, delayed/enteric, and not-applicable semantics. Matching ingredients/strengths cannot collapse these release classes.
- `app_private.product_pharmaceutical_equivalence` stores upstream composition/strength states, dosage-form classification, and a nullable strict equivalence key.
- A strict key exists only when composition, strength, and dosage-form profiles are all trusted and complete. The key combines the SP-026 order-independent ingredient-strength set with form class, route, and release class.
- `high_confidence` propagates from any trusted upstream dimension; SP-027 never silently upgrades it to `auto_verified`.
- Products with unresolved/review composition or strength, missing dosage form, unknown/mixed form semantics, or unspecified parenteral route never receive a strict key.
- Future composition changes refresh SP-025 → SP-026 → SP-027; strength-only changes refresh SP-026 → SP-027; dosage-form changes refresh SP-027 after SP-024 reference resolution.
- SP-027 still does not expose alternatives. Query grouping belongs to SP-028 and UI presentation belongs to SP-029.

### Alternatives query groups (SP-028)

- `public.catalog_alternatives(target_product_id, requested_limit_per_group)` is an owner-only read API over the private derived normalization tables. It does not grant direct access to those tables.
- The target must have trusted SP-025 composition, trusted SP-026 ingredient-strength mapping, and trusted SP-027 pharmaceutical equivalence before any relationship row is returned. Existing targets with incomplete/review/unresolved normalization return an empty result instead of guessed alternatives.
- `exact` requires the same non-null trusted SP-027 `strict_equivalence_key` and excludes the target itself.
- `same_ingredients_different_strength` requires the same trusted SP-025 ingredient-set key, different trusted SP-026 ingredient-strength set keys, and equal trusted SP-027 form class, route, and release class.
- `same_ingredients_different_form` requires the same trusted ingredient set and the same trusted SP-026 ingredient-strength set key, while at least one trusted SP-027 form class, route, or release dimension differs.
- These groups are mutually exclusive. A candidate that differs in both strength and form/route/release is omitted rather than ambiguously categorized.
- Returned `normalization_status` propagates the trusted auto/high-confidence normalization state. It is not a medical probability, clinical suitability score, bioequivalence claim, or recommendation.
- Results include the existing catalog product fields needed by SP-029. Price/currency values remain the current catalog values; the API does not alter captured order prices.
- Result ordering is deterministic only. It does not rank by price, manufacturer, or inferred preference.
- The requested limit defaults to 10 and is clamped to 1–25 rows per group on the server.
- Missing target identity raises not-found. No therapeutic alternatives, synonym/salt/base inference, or candidates with unresolved strict normalization are introduced by this layer.

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
