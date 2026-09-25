# Sherko Pharma — Architecture

Updated: 2026-09-23
Status: Product boundaries are agreed; the hosted schema, owner-only catalog API, authentication boundary, controlled 23,750-row source import, search/detail, and create/edit flows are in place. SP-009 local draft persistence is active; later product features remain pending. See `DEVELOPMENT_STATUS.md`.

## Current decision

Build an online Flutter application for Android and Windows, backed by Supabase. The owner signs in with email and password. The catalog is centrally stored and edited; the application stores only a small current-session snapshot locally.

This replaces the earlier offline-first proposal. Do not introduce Drift, a complete local SQLite catalog, catalog encryption infrastructure, or an offline write queue in this version. Offline support can be evaluated as a later architecture change.

`PRODUCT.md` defines user behavior. `AGENTS.md` defines the implementation workflow. This document defines boundaries and a proposed implementation structure, not completion claims.

## Components

| Component | Responsibility | Decision status |
| --- | --- | --- |
| Flutter client | English UI with readable Arabic data; Android and Windows | Confirmed |
| Supabase Postgres | Authoritative products, prices, product revisions | SP-003 schema defined; deployment deferred |
| Supabase Auth and server authorization | Owner-only email/password access; no app registration; auth events gate protected UI | SP-004 server boundary + SP-006 client boundary implemented; hosted acceptance pending |
| Riverpod controllers/providers | Screen state, dependency injection, loading/error handling | Confirmed by owner; compatible package version to select during setup |
| Repository interfaces | Isolate catalog access, account access, and session storage from widgets | Proposed implementation baseline |
| Auth session storage | Persist the Supabase auth session in platform secure storage, not ordinary preferences | SP-006 uses `flutter_secure_storage` 11.2.0 on Android/Windows |
| Local app session store | Save current screen, order snapshot, and active unsaved edit draft without copying the catalog | SP-009 uses the existing secure key-value store for account-scoped product drafts; broader page/order session persistence remains SP-011 |
| Android camera adapter | Produce deliberate barcode scan events | Confirmed; package to verify |
| Windows reader adapter | Produce scan events from the owner's external reader | Confirmed; hardware/input mode to verify |

Package versions are pinned in `pubspec.yaml`/`pubspec.lock` after compatibility verification against Flutter 3.38.7 / Dart 3.10.7. SP-006 uses `supabase_flutter` 2.17.2 and `flutter_secure_storage` 11.2.0; Android minimum SDK is 23 because of the secure-storage requirement.

## Code boundaries

Organize code by feature: authentication, catalog, order, and scanning. Keep application bootstrap and shared UI separate from feature behavior. Each feature separates widgets from controllers and data access as needed; do not generate empty layers just to match a folder diagram.

- Widgets render state and dispatch user actions. They do not issue database queries.
- Controllers manage user actions and state transitions.
- Repositories expose typed operations and hide Supabase or local storage details.
- Domain models and the order calculator are independently testable Dart code.
- Platform scanner adapters emit the same barcode event type to the order workflow.
- Do not build the future administration application, a general plugin framework, or a multi-tenant system now.

## Server access and catalog confidentiality

- Provision the owner's account outside the application. Disable public signup server-side as well as omitting its UI.
- Restrict access to the specific authorized owner, not merely to any authenticated account. Enforce permissions on the server.
- Use narrowly granted operations and RLS. SP-004 exposes owner-only bounded database functions to the authenticated role while revoking normal client direct access to `products`; an environment-provisioned owner UUID is checked server-side. Never embed a secret/service-role key, database password, owner UUID, or the owner's credentials in the app or repository.
- Use authenticated bounded search, lookup, and mutation operations. Do not offer client-side bulk export or fetch the complete catalog on startup.
- If preventing easy API enumeration is a security objective, constrain direct table access too: a UI page limit alone is not a server-enforced limit. Resolve the choice of bounded database functions or an API gateway during backend design, with permission and abuse-limit tests before distribution.
- Do not add the full source CSV as an application asset, a public repository file, or an unrestricted build artifact. Keep the initial import a controlled administration operation.
- Search and lookup responses include only fields needed by the current feature. SP-006 persists only Supabase's session blob through platform secure storage and lets the Supabase client own refresh/token rotation. App code does not persist the password or manually duplicate refresh-token logic.
- SP-007 injects a catalog repository backed by the same authenticated Supabase client. It calls only the bounded `catalog_search` / `catalog_get` RPCs, keeps responses in memory, and uses request-generation guards so stale asynchronous results cannot replace newer search/detail state. Search/detail do not query `products` directly or create a local full-catalog cache.
- SP-008 extends that repository with owner-authorized mutation RPCs. Create uses a client-generated random UUID with additive `catalog_create_idempotent` semantics so a lost response can be reconciled without duplicate creation. Update sends the observed revision atomically. Any uncertain mutation result is reconciled through `catalog_get` before retry, and a newer/different row enters explicit conflict resolution rather than last-writer-wins.
- Avoid product dumps, credentials, and full request payloads in logs.
- Online-only access reduces copies of the catalog on devices; it does not guarantee that an authorized reader cannot collect results over time.

## Product storage identity and revisions

- `products.id` is a generated UUID independent of source identifiers, names, barcodes and prices.
- Corrected-source provenance uses a versioned dataset key, explicit source identifiers and a complete raw JSONB row. See [SOURCE_MAPPING.md](SOURCE_MAPPING.md).
- Barcode columns are nullable text with non-unique indexes. Duplicated identifiers across distinct products remain valid stored state and later lookup ambiguity.
- Selling amount is whole-unit `bigint` paired with explicit `SYP` or `USD`; zero is representable only for a source-import anomaly.
- Each accepted database update increments `revision` exactly once. SP-004 must combine this with an atomic expected-revision predicate before exposing mutations.

## Catalog reads and automatic refresh

- Supabase is the source of truth. Search by Arabic name, English name, and composition on the server with bounded results and appropriate indexes.
- Use exact text matching across both `barcode` and `barcode2`, returning distinct products by identity. Either field identifies the same package; cross-product collisions require user selection regardless of which field matched. Exclude empty identifiers. See `DATA_MODEL.md`.
- Distinguish loading, no match, ambiguous match, connection failure, and authorization failure.
- Ignore responses for superseded searches so slow requests cannot replace newer results.
- Automatically refresh relevant visible data on successful mutations, reconnect, and application resume. While connected, choose a scoped invalidation/subscription or bounded polling policy in implementation; do not replicate the full table.
- Re-read authoritative values after reconnect; a transient notification alone is not durable evidence that the displayed state is current.

## Catalog mutations and concurrency

- Edits and product creation require a working authenticated server connection.
- Show saved/success only after the server confirms the operation. Retain unsaved form input on failure for explicit retry; do not turn it into an automatic offline queue.
- Guard app/back navigation from changed edit forms with the Save / Discard Changes / Stay flow in `UX_FLOWS.md`. Persist the active unsaved draft locally across restarts. Restore without submitting; failed or unresolved saves retain the draft. Clear it only after confirmed save or explicit discard.
- Use atomic revision checks for edits: submit the revision read by the user, and reject the write if the stored revision changed.
- On conflict, display the current server value and the attempted change for the owner to choose. Recheck the revision when applying a choice. Do not silently use last-writer-wins.
- A timed-out request can have succeeded on the server. Reconcile uncertain outcomes and use stable operation identifiers where required to prevent duplicated product creation on retries.
- Successful changes are available to the owner's other devices through automatic refresh. The customer order/session itself does not need cloud synchronization in this version.

## Order model and price updates

- Keep one line per selected product with product identity, minimum display information, quantity, captured integer selling amount and currency, and the observed product revision where useful.
- Adding quantity to an existing line uses the line's captured amount and currency. A server amount or currency change shows a notification and an explicit update option without silently changing totals; accept a valid new pair atomically.
- New customer orders use current server prices. Revalidate saved order products/prices on resume before claiming the data is current.
- Use exact integer monetary arithmetic in whole currency units for both SYP and USD. Aggregate separately by captured currency; do not implement exchange rates or a converted/combined grand total. Validate prices and currency before addition, and detect overflow. See `DATA_MODEL.md`.
- Preserve the existing order during network failures. New server-dependent catalog lookup and mutation operations cannot succeed offline.
- Do not add sales history, inventory deduction, payment processing, or fractional-package conversion.

## Session persistence

- Persist the active page/location and order snapshot, including quantities, captured prices, and captured currencies, on state changes rather than relying solely on a shutdown callback.
- Persist active edit input with the owner identity, product identity, and original server revision. Restoring a draft must not silently adopt a newer revision or replace user input. Preserve atomic/versioned writes and report local persistence errors.
- Keep draft persistence separate from server mutations: startup/reconnect cannot enqueue or submit writes. Only explicit Save triggers validation and revision-checked persistence. Reconcile ambiguous prior save outcomes before retrying; prevent stale asynchronous draft writes from resurrecting discarded or successfully saved input.
- Write snapshots atomically and include a schema version. Corrupt snapshots must cause an explicit recoverable error, not silent loss represented as a successful restore.
- A confirmed New Order reset must persist the empty active order without history. Invalidate pending scan/lookup responses belonging to the previous order so they cannot populate the new one. Report snapshot-write failures explicitly.
- Associate saved sessions with the authenticated owner. Sign-out retains persisted order/draft state but clears protected visible/in-memory presentation state. Restore only after successful authentication as the same owner; never expose it to another or signed-out account. Preserve active draft input before hiding the form, and prevent late asynchronous responses from repopulating signed-out UI.
- Persist only what restoration needs. In-memory search results are not a reason to create a persistent catalog cache.
- Search text, exact scroll position, and filter restoration are not initial acceptance requirements. Retain active screen/order/draft restoration under `UX_FLOWS.md`.
- This small local snapshot still contains some product names/prices. Online-only does not mean zero local data.

## Platform input

- Android: camera scanning with permission-denied and unavailable-camera states. Prevent repeated camera frames from increasing quantity without another deliberate scan.
- Windows: external barcode reader. The owner has not purchased a reader yet; hardware compatibility remains pending until selection. Determine its model and protocol then. Keyboard-emulation readers and serial/vendor-specific readers need different adapters; do not claim universal compatibility without evidence.
- Preserve barcode text, including leading zeros. Do not silently normalize codes into different identifiers.

## Remaining design decisions

- Refresh the inspected repository baseline, verify an executable toolchain, and select compatible packages for session storage, credentials, and camera scanning.
- Automatic-refresh mechanism remains to be chosen. SP-004 defines owner-only bounded catalog RPCs with server-enforced limits and denies normal client direct-table access.
- Confirm reader hardware. Session, sign-out, reset-order, and unsaved-edit navigation behavior is specified in `UX_FLOWS.md`.
- Implement the agreed CI and hardware acceptance gates in `QUALITY.md` before enabling task auto-merge.

## Official references used in the proposal

- [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
- [Supabase Flutter quickstart and supported platforms](https://supabase.com/docs/guides/getting-started/quickstarts/flutter)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase API key boundaries](https://supabase.com/docs/guides/getting-started/api-keys)
- [Riverpod](https://riverpod.dev/)

References support technology capabilities and general practices. The product scope and user-visible behavior come from the owner's decisions in `PRODUCT.md`.
