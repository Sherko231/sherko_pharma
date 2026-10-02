# Sherko Pharma — Architecture

Status: Maintained architecture boundary for the current repository state.
Updated: 2026-10-03

## System shape

Sherko Pharma is a Flutter client for Android and Windows backed by Supabase. The application is online-first for catalog operations and keeps only bounded account-scoped local state needed to resume the active workflow.

The primary runtime layers are:

1. **Presentation** — compact Cart, catalog search, scanner, product detail/edit and alternatives surfaces.
2. **Application/domain** — order state, catalog workflows, refresh/conflict handling, scientific/canonical derived models and validation.
3. **Data** — bounded Supabase repositories plus secure local session/draft stores.
4. **Backend** — versioned PostgreSQL schema, private derived normalization tables and owner-authorized RPC boundaries.

Do not bypass an existing layer merely to shorten an implementation. Client UI is not an authorization boundary.

## Runtime configuration

The Flutter client receives only:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Configuration fails closed when these values are missing or malformed. Never place a service-role/secret key, source catalog, privileged database credentials or production dump in the application or repository.

`AppRuntime` initializes secure authentication storage, the catalog repository, the account-scoped catalog draft store and the account-scoped application session store. Runtime initialization failure produces an explicit blocked/failure state instead of silently falling back to another environment.

## Authentication and authorization

Supabase email/password authentication gates protected application content. The initial product uses the owner's pre-provisioned account and has no in-app registration.

Authorization is enforced by the database/RPC boundary, not by hiding controls. Normal client roles must not receive direct access to private normalization/curation tables or privileged mutation paths.

Signed-out state must not expose retained order or draft content. Account-scoped local data may be restored only after successful authentication as the matching account.

## Catalog boundary

Supabase is authoritative for catalog products. The client does not bundle or replicate the full source catalog.

Catalog reads/writes use bounded repository/RPC methods. Product updates use optimistic revision checks. A stale expected revision is a conflict and must be surfaced for explicit owner resolution; do not silently overwrite a newer server row.

Create/edit success is shown only after server confirmation. Uncertain write outcomes are reconciled before retrying or claiming success. No offline pending-write queue exists in the current scope.

The private source CSV and generated import payloads stay outside application assets and public source control. Controlled import remains a separate owner-operated workflow.

## Product identity and barcode rules

Product UUID is the stable product identity. `barcode` and `barcode2` are exact text identifiers for the same product/package and may contain leading zeros or non-digit characters.

Barcode lookup checks both fields, deduplicates by product identity and never silently chooses between distinct matching products. Unknown codes leave the Cart unchanged. Android camera scanning may remain open for repeated acquisition, but each unique accepted scan must resolve through the authoritative catalog boundary.

## Cart and monetary state

The Cart is the single primary workspace after authentication. Search/scanning acquire products; the order controller owns selected lines, quantities and captured monetary values.

Each order line captures an exact integer selling amount and its currency together when first added. Supported currencies are SYP and USD. Totals are calculated separately by currency; there is no exchange-rate conversion or mixed-currency grand total.

A later server price/currency change does not silently mutate an existing line. The scoped refresh path reports the new pair and only an explicit owner action adopts it.

`New Order` clears the active order only after required confirmation. It creates no checkout, stock movement or historical sale.

## Local persistence

Local persistence is deliberately bounded:

- authentication session through platform secure storage;
- active order/application session scoped to the authenticated account;
- unfinished catalog-edit draft scoped to the authenticated account.

Restoration must never upload a draft automatically. Only explicit Save may create a server mutation. Confirmed Save or explicit Discard removes the corresponding draft. Device-local session data is not a full offline catalog and is not cross-device synchronization.

## Search and refresh

Manual catalog search is server-backed and ranked. It supports Unicode/Arabic normalization, multi-token prefix matching, exact barcode/name priority and typo-tolerant matching within bounded server limits.

Search results are transient UI state. Product detail and alternatives use current authoritative product data. Scoped refresh revalidates only relevant displayed/selected products rather than downloading the whole catalog.

## Derived composition, strength and alternatives

Authoritative catalog text remains in `products.composition` and `products.strength`. Derived layers must not rewrite these fields unless the owner explicitly edits the product through the normal catalog workflow.

The private derived pipeline is layered:

1. SP-025 lexical ingredient normalization preserves observed source spelling and component provenance.
2. SP-026 derives deterministic ingredient-strength structures only where syntax is safe.
3. SP-027 derives conservative pharmaceutical-equivalence keys only when ingredient-strength, dosage-form, route and release dimensions are complete.
4. SP-028 exposes bounded relationship groups through an owner-only alternatives RPC.
5. SP-029 presents those groups without claiming clinical interchangeability or prescribing suitability.
6. SP-038–SP-044 maintain a separate reviewed scientific canonicalization layer with deterministic cleanup, reviewed aliases, embedded-strength parsing, complex-structure parsing and versioned product canonicalization.

Fuzzy similarity, string cleanup or deterministic parsing may generate review candidates but cannot become scientific truth automatically. Accepted scientific identities/aliases require reviewed provenance. Ambiguity stays explicit.

Scientific identity is separate from pharmaceutical equivalence. A shared ingredient identity does not by itself establish substitution, dosing, treatment suitability or bioequivalence.

## Private scientific data

Scientific identity, alias, mapping, parsing and product-canonicalization tables live in `app_private`, with direct normal-client privileges revoked. Public/client access is added only through an explicitly authorized bounded API.

The production scientific backfill is versioned and designed to preserve authoritative catalog text, product/commercial identity, revisions and earlier derived lexical/equivalence state. Future production-wide derived-state changes require an explicit bounded task and fresh approval where the repository contract requires it.

## UI boundaries

Compact density is the default. Cart totals/New Order remain visible while lines scroll. Repeated rows are flat and separated by subtle dividers rather than oversized cards. Search results are transient foreground context. Wide layouts may use a supporting acquisition pane without changing the primary Cart workflow.

Product detail/edit are focused routes. Alternatives use a modal/bottom-sheet surface and re-read the selected candidate before Add-to-cart.

## Error handling

Connection failure is distinct from an empty result. Invalid prices, barcode ambiguity, revision conflicts, local persistence failures and arithmetic overflow must remain explicit and non-destructive.

Late asynchronous responses must not mutate a newer order/session generation after the relevant product/order context has changed.

## Verification and release boundary

Hosted GitHub Actions CI is intentionally not required. `docs/QUALITY.md` defines optional local verification and owner pull-and-test behavior.

Production credentials, destructive data operations, authorization changes and release signing remain separate owner-controlled concerns. Repository completion does not imply that an external production mutation or public artifact distribution has occurred.
