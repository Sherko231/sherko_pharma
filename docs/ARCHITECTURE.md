# Sherko Pharma — Architecture

Updated: 2026-09-29
Status: Product boundaries are agreed; SP-036 is merged. SP-037 hardens the complete DDI flow with exact provider pair-set/summary validation, Cart-adjacent provider disclaimer/backlink, stricter HTTP(S)-only link launching, synthetic cross-layer acceptance coverage, and explicit deployment/licensing gates. No production migration or external deployment is introduced. Windows external-reader integration remains deferred. See `DEVELOPMENT_STATUS.md`.

## Current decision

Build an online Flutter application for Android and Windows, backed by Supabase. The owner signs in with email and password. The catalog is centrally stored and edited; the application stores only a small current-session snapshot locally.

This replaces the earlier offline-first proposal. Do not introduce Drift, a complete local SQLite catalog, catalog encryption infrastructure, or an offline write queue in this version. Offline support can be evaluated as a later architecture change.

`PRODUCT.md` defines user behavior. `AGENTS.md` defines the implementation workflow. This document defines boundaries and a proposed implementation structure, not completion claims.

## Composition normalization boundary

SP-025 adds a private derived normalization layer beside the authoritative `products.composition` text. It creates reusable ingredient identities, lexical aliases, product-component links, an order-independent ingredient-set key, and explicit normalization confidence/review status. The layer is refreshed by database trigger when composition changes, but it does not rewrite the product text or advance product revisions during structural backfill.

This boundary is deliberately conservative. Automatic parsing recognizes only explicit `+` composition separation and deterministic lexical normalization. Ambiguous syntax and semantic synonym candidates remain reviewable/unresolved. Strength pairing, route/release equivalence, direct-alternative classification, and alternatives API/UI are implemented as separate downstream layers so medication substitution is never inferred from composition text alone.

## Strength normalization boundary

SP-026 extends the SP-025 derived pharmaceutical model without changing the authoritative `products.strength` text. It parses supported numeric/unit expressions into exact canonical measures, links them to trusted ingredient components only when component counts and syntax align, and creates an order-independent ingredient-strength set key for later equivalence work.

Slash syntax is context-sensitive: quantitative forms such as `250 MG/5 ML` are normalized as concentrations, while recognized presentation suffixes such as `500 MG/CTD TAB` or `1 G/VIAL` are excluded from numeric comparison and left for the dosage-form/release model. Every multi-ingredient positional mapping is capped at high confidence because it depends on source ordering; shared trailing concentration denominators across explicit `+` components are high-confidence derivations as well. Unsupported shorthand, partial combinations, unitless values, and untrusted SP-025 compositions remain review/unresolved.

Composition edits own dependency sequencing: the existing SP-025 composition trigger refreshes ingredient links and then SP-026 strength links. A separate strength-update trigger handles strength-only edits and deliberately skips combined composition+strength updates. Neither path changes the existing catalog revision/conflict rules beyond the normal product update itself.

## Pharmaceutical equivalence boundary

SP-027 adds one more private derived layer above SP-024 dosage-form references and SP-026 ingredient-strength normalization. It does not expose alternatives to the client. A product receives a strict pharmaceutical-equivalence key only when its composition/strength normalization is trusted and its dosage form can be conservatively classified into a compatible form class, route, and release class.

Dosage-form classification is intentionally asymmetric. Explicit ophthalmic, otic, nasal, vaginal, rectal, inhalation, sublingual, modified-release, enteric/delayed-release, and other recognized forms can carry trusted route/release semantics. Common plain forms such as ordinary tablets, capsules, syrups, creams, gels, ointments, and suppositories may be high-confidence when the route is conventional but not explicitly written. Injection-like records remain non-strict when the source does not identify the specific parenteral route; generic or mixed-route labels remain review/unresolved.

Strict equivalence therefore means equality of the SP-026 order-independent ingredient-strength set plus the reviewed dosage-form class, route class, and release class. Immediate-, extended-, and delayed-release products never share a strict key merely because ingredient and strength match. Likewise, ophthalmic, otic, nasal, vaginal, rectal, oral, inhaled, and other distinct routes remain separate. Upstream high-confidence state propagates and is never upgraded to auto-verified.

Dependency sequencing remains explicit. Composition edits refresh SP-025, then SP-026, then SP-027. Strength-only edits refresh SP-026 and then SP-027. Dosage-form edits refresh SP-027 only after SP-024 reference resolution. Structural backfill changes no authoritative composition, strength, dosage-form text/reference, revision, or updated-at values.

## Alternatives query boundary

SP-028 exposes the private SP-025/SP-026/SP-027 derived model through one bounded owner-authorized RPC, `public.catalog_alternatives`. It remains a query layer only: it does not modify normalization state, raw catalog data, product revisions, prices, barcodes, orders, sessions, or client-side persistence.

The API returns three mutually exclusive relationship groups. `exact` requires the same trusted non-null SP-027 strict equivalence key. `same_ingredients_different_strength` requires the same trusted ingredient set and the same trusted form/route/release dimensions while the ingredient-strength set differs. `same_ingredients_different_form` requires the same trusted ingredient-strength set while at least one trusted form/route/release dimension differs. A candidate that changes both strength and form is intentionally omitted rather than forced into either comparison group.

The target itself must be trusted across SP-025 through SP-027 before the relationship engine returns any rows. Review/unresolved target or candidate normalization is never promoted into `exact`, and unknown relationships remain absent instead of guessed. Returned `normalization_status` is derivation confidence only; it is not a clinical recommendation, bioequivalence rating, or therapeutic-interchangeability claim.

The RPC reuses the existing catalog product fields, preserves exact barcode and integer price/currency semantics, requires `app_private.require_owner()`, and clamps each relationship group to a hard maximum of 25 rows. Ordering is deterministic by stable product identity/name fields and is not a price/manufacturer/preference ranking. SP-029 consumes this boundary in the Product/Cart UI while preserving the separation between the three relationship groups.

## Alternatives presentation boundary

SP-029 is a presentation/repository extension over the SP-028 query boundary. `CatalogRepository.alternatives` maps the bounded RPC into typed relationship-group results; widgets do not consume raw RPC maps or private database structures.

The Cart search result row and Product Detail both open the same reusable alternatives bottom sheet. No new primary navigation destination or persisted alternatives state is introduced. The sheet renders the three server relationship groups separately and uses descriptive matching labels rather than asserting clinical interchangeability. A visible notice states that the grouping is catalog-derived and does not establish prescribing suitability.

Candidate rows show the product/brand identity, manufacturer/company, current returned selling price/currency, strength, and dosage form. Add-to-cart does not trust the alternatives response as the final price snapshot: it re-reads the exact candidate identity through `catalog_get` immediately before calling the existing `OrderController.addProduct`, preserving current integer price/currency, revision, invalid-price, quantity, and overflow semantics.

Alternatives remain in-memory transient UI data. A failed relationship query or candidate revalidation leaves the Cart unchanged and exposes retry/error feedback. The client asks for at most 10 candidates per group in the sheet, while the repository still clamps any caller request to the SP-028 server maximum of 25.

## External DDI evidence boundary (SP-030)

SP-030 establishes a future informational DDI boundary around Interaction Checker; it does not implement that boundary. The external source is versioned at `https://interaction-checker.com/api/v1` and currently documents a no-key REST API, a 60 requests/minute/IP limit, 2–10 inputs per `/checks` request, one-hour cacheability, and `Retry-After` on rate limiting. These are provider-controlled constraints and must be re-checked before downstream implementation or release.

The repository-owned catalog remains the identity source. A Cart product is first resolved through the existing private SP-025 ingredient normalization model. Only trusted ingredient identities may become external DDI queries. Raw Syrian brand names, fuzzy guesses, `needs_review`, and `unresolved` normalization are not promoted into clinical identities. SP-031 exposes this bridge through one bounded owner-authorized product-to-ingredient read rather than exposing the private ingredient registry or reparsing composition in Flutter.

The external service is an evidence source, not an authority over Cart state. Downstream controllers may derive transient product-pair interaction state from ingredient-level results, but they must not mutate products, product revisions, barcodes, order lines, quantities, captured integer prices/currencies, totals, edit drafts, alternatives, or session ownership. Quantity is deliberately outside the DDI identity model because the provider result is not a dose- or patient-specific assessment.

Severity remains provider/label semantics:
- `major`: boxed-warning/contraindication/avoid wording.
- `moderate`: monitoring, dose-adjustment, or dose-spacing wording.
- `minor`: a label mention without an avoid/change instruction.
- `none`: an explicit source statement of no clinically significant interaction, not a universal safety assertion.
- `unknown`: neither available label mentions the other item, which is incomplete evidence rather than a safe result.

Ingredient-level evidence must be traceable back to the affected Cart product pair. For combination products, every trusted ingredient participates in cross-product checking; same-product-only ingredient pairs do not create Cart product-vs-product warnings. Downstream batching must preserve complete pair coverage despite the provider's 10-input request cap and must deduplicate evidence deterministically.

DDI state is transient and online-derived. It must not be written into the existing local order/session snapshot or become medication-history storage. A restored Cart is rechecked online. Bounded in-memory caching/coalescing may be introduced later only to respect provider limits and prevent duplicate work; stale responses must be generation-guarded so a removed product, New Order, session replacement, or sign-out cannot receive an obsolete warning.

The outbound request boundary is privacy-sensitive even though it carries no Sherko Pharma credential: the external provider receives the ingredient queries being checked and its terms say requests are logged briefly for operation/abuse prevention. Downstream code must not send account identifiers, patient identity, barcodes, prices, notes, Supabase tokens, or unrelated catalog fields, and must avoid logging complete medication/provider payloads locally.

Any presented result must keep the provider disclaimer and backlink/attribution, plus source/effective-date context when available. Provider failure, unresolved ingredients, rate limiting, malformed responses, and `unknown` evidence are distinct from `none`; no failure path may synthesize a "safe" or "no interaction" result.

Interaction Checker's September 2026 terms describe the service as informational, disclaim completeness/accuracy, allow the public API under the same terms, and prohibit using it to build or sell a clinical decision-support product or redistributing the dataset as a whole. This architecture therefore makes no commercial/public-release permission claim. Any release that exposes this DDI feature outside the current owner-development context requires a fresh terms review and compatible permission, or a replacement data source/license.

Authoritative external references for the boundary:
- https://interaction-checker.com/api
- https://interaction-checker.com/api/v1/openapi.json
- https://interaction-checker.com/terms

## Trusted DDI ingredient-input query boundary (SP-031)

SP-031 adds `public.catalog_ddi_ingredients(uuid[])` as the only client-facing server operation in this task. The RPC accepts explicit product UUIDs only, requires `app_private.require_owner()`, rejects null IDs, returns no rows for an empty request, and hard-limits each call to 50 requested product IDs. Duplicate IDs are deduplicated by their first request position so downstream result mapping is deterministic.

The RPC exposes product-scoped DDI input coverage rather than the private ingredient registry. For each requested product it returns explicit `trusted`, `needs_review`, `unresolved`, or `missing` coverage plus the underlying SP-025 normalization status/counts. A product is `trusted` only when its SP-025 status is `auto_verified` or `high_confidence`, it has a non-null ingredient-set key, every parsed component resolved, and the complete expected set of product-ingredient links exists.

Only trusted products expose ingredient identity fields. Their rows include component order, stable private ingredient ID, canonical ingredient display name, and canonical normalized ingredient name. `needs_review`, `unresolved`, structurally incomplete, and missing products return an explicit coverage row with null ingredient identity fields. This prevents downstream code from turning review-only raw composition text or Syrian brand labels into guessed external drug queries.

The operation does not return raw composition components, alias spellings, the full ingredient registry, prices, barcodes, notes, revisions, patient/account data, or any external-provider result. Normal authenticated clients retain no direct access to `app_private.catalog_ingredients`, `app_private.product_ingredients`, or `app_private.product_composition_normalization`. The hard request bound and required product IDs prevent the RPC from becoming an unrestricted registry-enumeration endpoint.

SP-031 is a read-only repository boundary. It does not modify products or normalization state and therefore does not change catalog revision, barcode identity, alternatives, order quantity, captured integer price/currency, totals, session persistence, or draft behavior. Migration 0013 depends on the repository SP-025 normalization migration and is not deployed to the hosted project by this task.

## Interaction Checker client boundary (SP-032)

SP-032 implements a typed, injectable client for the versioned `https://interaction-checker.com/api/v1/checks` POST endpoint. The base URI is centralized/injectable and the client accepts an injected `package:http` `Client`, allowing deterministic fixture tests without live provider calls. `http` 1.6.0 is declared directly while preserving the version already present in the lockfile.

The request surface is deliberately narrow: 2–10 nonblank item strings, each no more than 80 characters, serialized only as `{"items":[...]}`. The client adds no API key, Supabase token, account identifier, barcode, price, note, patient information, or other catalog metadata. Input whitespace is trimmed before the request; higher-level ingredient selection/deduplication/batching remains outside this task.

Successful responses are parsed into typed resolved items, unresolved items and suggestions, substance identities, pair severities, evidence, evidence sections/match kinds, source metadata/effective dates, summary counts, provider data dates, disclaimer, and attribution. Pair severity supports exactly `major|moderate|minor|none|unknown`. Evidence severity intentionally supports only `major|moderate|minor|none`, matching the current OpenAPI contract; `unknown` evidence is not invented. Required malformed fields and unsupported required enum values fail visibly, while additive unknown optional fields are ignored.

The HTTP boundary has a configurable positive timeout (10 seconds by default) and deterministic failure classes for local request validation, timeout, transport failure, HTTP 429, other non-2xx provider errors, malformed success payloads, and unsupported response values. A numeric `Retry-After` header is exposed as a duration when valid. Provider error code/message are retained when the error body matches the documented shape. The client never automatically retries; batching, coalescing, rate scheduling, caching, and stale-generation handling belong to SP-033/SP-034.

The client owns and closes only an internally-created HTTP client. An injected client remains caller-owned. No provider response or medication list is logged or persisted by this layer, and successful disclaimer/attribution values are preserved for later UI presentation.

The provider contract was re-checked on 2026-09-29 against:
- https://interaction-checker.com/api
- https://interaction-checker.com/api/v1/openapi.json
- https://interaction-checker.com/terms

## DDI integration hardening and acceptance boundary (SP-037)

SP-037 treats the provider's successful `/checks` response as an integrity boundary rather than trusting HTTP 2xx alone. After every submitted query is accounted for as resolved or unresolved, the engine derives the exact set of unordered pairs that must exist among resolved provider substances and requires the returned pair multiset to match exactly. A missing pair, duplicate pair substituted for another pair, unexpected pair, or contradictory reported summary count fails as `DdiAnalysisMappingException`; incomplete success output is never converted into `none` or a partial ready result.

The existing SP-033 cross-batch algorithm remains unchanged: trusted ingredients are stable-ID deduplicated, groups of at most five are pairwise-unioned to keep every provider request at ten or fewer items, and overlapping evidence is deduplicated before product aggregation. The stronger per-batch response check therefore composes with the existing >10-item completeness proof instead of replacing it.

SP-037 also keeps the provider's legal/source notice adjacent to Cart-level ready output. `DdiCartPresentation` retains deduplicated disclaimer/attribution metadata, and the Cart summary renders the provider-supplied disclaimer plus backlink whenever that HTTP(S) URL is available. The SP-036 detail sheet continues to show the richer notice/data-date view. External links share one injectable launcher; both the widget boundary and production launcher reject non-HTTP(S) URIs.

The synthetic acceptance regression crosses the real client application layers without live services: barcode/order input, a fake trusted ingredient repository, the real SP-033 engine, a fake provider, SP-034 lifecycle, SP-035 Cart visualization, and SP-036 detail presentation. It verifies that provider queries contain only canonical ingredient names, same-product-only ingredient interactions do not become product-pair warnings, combination-product causal pairs remain separate, attribution/disclaimer stay visible, and quantity-only changes do not cause another provider request.

Repository acceptance is not production activation. The hosted environment is still documented as deployed through SP-024 only; SP-025–SP-028 and SP-031 migration 0013 remain undeployed by SP-037. No live Interaction Checker request, production Supabase write/migration, release artifact, or owner Android/Windows DDI acceptance is claimed. Current September 2026 provider terms still require attribution/disclaimer and do not authorize building/selling the output as a clinical decision-support product; a compatible permission/license/source is a separate public/commercial release gate.

## DDI evidence/detail presentation (SP-036)

SP-036 opens details only from a severity badge backed by the current SP-035 ready analysis. The sheet receives an immutable presentation snapshot built from that analysis plus the current Cart display names; opening, scrolling, linking, or dismissing the sheet does not change Cart/order/DDI state and does not trigger another provider request.

The detail mapper filters every current product-pair result involving the selected row product and orders those pairs by the existing severity rank. It preserves every SP-033 causal `DdiIngredientInteraction` rather than flattening combination-product causes. Each ingredient pair keeps its provider severity label, evidence entries, matched term/kind, source metadata, interaction URL and provider detail page.

Evidence is rendered entry-by-entry with the provider section label and evidence text plus source name/type/effective date. Evidence-free `unknown` and `none` states remain explicit and do not synthesize explanation text. Product names come from the current Order lines; provider evidence is not used to rename local products.

Provider notices from overlapping SP-033 batches are deduplicated by data dates + disclaimer + attribution metadata before rendering. The sheet keeps the provider-supplied disclaimer and attribution/backlink alongside the displayed output and may show label-export/generated dates. SP-036 does not write provider output to session/order persistence.

External source, provider and interaction-detail links are restricted to `http`/`https`. `url_launcher` 6.3.2 is promoted from the existing lockfile's transitive dependency to a direct pinned dependency and opens links in the platform browser. Link opening is hidden behind `DdiExternalLinkLauncher` so tests never open the real browser; launch failure leaves the sheet open and surfaces non-destructive feedback.

The provider API/terms were re-checked on 2026-09-29 during SP-036 and again during SP-037. The API still calls for a link back wherever results are shown and keeping the disclaimer with displayed output. Current September 2026 terms still prohibit presenting or selling the output as a clinical decision-support product, so repository completion does not authorize public/commercial DDI release.

## Cart DDI severity presentation (SP-035)

SP-035 keeps provider/domain meaning separate from widget styling through a pure `DdiCartPresentation` mapper. The mapper counts product-pair severities once per pair, derives each product row's highest active severity, retains the number of product pairs affecting that row, and independently tracks incomplete coverage from local normalization gaps, provider-unresolved ingredients, or the absence of an explicit pair result.

The Cart watches SP-034 `DdiCartState`. Only the current `ready` analysis is mapped into row visuals; `loading`, `error`, `unavailable`, or `idle` never reuse a prior ready presentation. With two or more distinct products, one compact DDI status strip sits below the existing item/total summary. Loading says interaction checking is in progress; failure leaves the Cart usable and exposes the existing SP-034 Retry action; unavailable never masquerades as no interaction.

Ready rows preserve the existing flat order layout, price, quantity, remove and price-change controls. `major` uses error/red emphasis, `moderate` orange, `minor` amber, while `unknown` and `none` use neutral styling. Color is never the only signal: every known row severity has an icon/text badge. `none` is labeled "No interaction found" rather than "safe"; `unknown` remains a question state. Local untrusted normalization is labeled "Unchecked", provider resolution gaps remain explicit, and a missing explicit pair result is treated as incomplete rather than synthesized as `none`.

The Cart summary counts product-pair results separately for `major|moderate|minor|unknown|none` and adds a separate incomplete-product count. This summary is informational only and does not alter ordering, totals, scanning, product addition, substitution, dosing or treatment behavior. SP-036 remains responsible for evidence text, source links, attribution/disclaimer rendering and the reusable interaction detail sheet.

## Cart DDI lifecycle wiring (SP-034)

SP-034 keeps DDI lifecycle state separate from `OrderState`, session persistence, captured price/currency, catalog refresh, and scanner state. `DdiCartController` observes only three identity boundaries: authenticated owner, restored-session readiness/owner, and the ordered distinct Cart product-ID set. Quantity, price, revision, and display-name updates therefore do not invalidate or restart DDI analysis.

The production runtime injects `SupabaseDdiIngredientRepository` from the same authenticated Supabase client already used by the catalog. The Interaction Checker client and SP-033 analysis engine are created through Riverpod providers so tests can replace the complete analysis gateway without networking. A runtime that intentionally omits the ingredient repository produces an explicit `unavailable` DDI state only when at least two products would require analysis.

The active Cart shell creates a listener for the DDI controller but renders no SP-035 visuals yet. Once the authenticated same-owner session is ready, fewer than two distinct products produce `idle`; two or more produce `loading` and a 120 ms debounce. Rapid additions inside that window replace the pending generation so only the latest product set starts analysis. Existing scanner/search/Alternatives add paths remain unchanged and never await DDI work.

Every relevant owner/session/product-set change increments the DDI generation and cancels a pending debounce. The controller passes SP-033 an `isCurrent` predicate tied to that generation, authenticated owner, ready session, and exact current product IDs. New Order/empty Cart, removal, sign-out, account replacement, or a newer distinct product set therefore invalidates older work. A late completion is ignored and cannot restore a result for obsolete Cart contents.

A successful analysis becomes `ready` only for the exact current generation. Failures produce retryable `error` state with a typed failure category; rate-limit failures also retain `Retry-After` when available. The Cart/order remains unchanged on every DDI failure. `retry()` reruns only when the same owner/session/product set is still current. Superseded work is discarded without surfacing an error.

DDI results are never written into `AppSessionSnapshot`. Same-owner Cart restoration therefore starts a new controller analysis after session restoration rather than restoring a prior warning/result. SP-033 may still satisfy identical provider batches from its bounded one-hour in-memory cache inside the current process; no medication or interaction history is persisted.

## Cart DDI analysis and batching engine (SP-033)

SP-033 joins the SP-031 trusted ingredient-input boundary to the SP-032 provider client without observing or mutating Riverpod Cart state. `SupabaseDdiIngredientRepository` maps `catalog_ddi_ingredients(uuid[])` rows into typed product coverage and canonical ingredient identities; raw RPC maps stay inside the data adapter. The analysis engine accepts only product IDs, so quantity, price, barcode, product display name, account/session identity, and raw composition never become provider inputs.

Product IDs are deduplicated and resolved through SP-031 in chunks of at most 50. Only `trusted` product coverage contributes ingredients. Ingredient identity is deduplicated by stable SP-025 ingredient ID while retaining every owning product ID. Canonical ingredient display names are the provider query strings; review/unresolved/missing product coverage stays explicit and is never converted into a guessed query.

Interaction Checker accepts at most ten items per check. For up to ten unique ingredients, SP-033 emits one batch. Above ten, ingredients are ordered deterministically by stable ID, partitioned into groups of at most five, and every pairwise union of groups is checked. Because each union contains at most ten items, every unique ingredient pair appears together in at least one request. Same-group pairs can appear in multiple unions, so ingredient interactions and evidence are deduplicated before product aggregation.

Provider resolution is tracked separately from SP-031 normalization. Every submitted query must appear exactly once in that batch as resolved or provider-unresolved; an omitted/unexpected query or inconsistent resolution across overlapping batches is treated as a mapping failure, not as `none`. Provider suggestions are retained without automatic selection.

Provider pair endpoints are mapped through the resolved batch items back to stable local ingredient identities, then to all cross-product owners. If fewer than two distinct trusted Cart products are represented in the deduplicated ingredient graph, the engine makes no provider request. Ingredient pairs that exist only within one product never create a product-vs-product warning. A product pair retains every unique causal ingredient pair and aggregates severity using `major > moderate > minor > unknown > none`; therefore incomplete `unknown` evidence outranks an explicit `none` but never outranks a documented minor/moderate/major result.

The engine preserves provider evidence, source metadata, interaction/detail links, data dates, disclaimer, and attribution for downstream presentation. It does not persist DDI state. Successful provider batches use a bounded in-memory LRU-style cache (128 entries by default) with a one-hour TTL matching the provider's documented cacheability, and identical in-flight batches are coalesced.

Provider calls are serialized inside one engine instance and self-throttled to at most 60 attempts per rolling minute by default. A 429 with a valid positive `Retry-After` delays and retries that batch once; a second 429 or missing/non-positive retry delay propagates. The engine does not retry other failures. This local limiter reduces application-originated pressure but cannot guarantee the provider's IP-wide quota when other processes share the same public IP.

SP-033 accepts an optional `isCurrent` predicate and checks it before/after ingredient-resolution work and provider-batch awaits. If the owning Cart/session generation becomes stale, it throws `DdiAnalysisSupersededException` and stops scheduling later batches. An already completed provider response may remain in the bounded ingredient-set cache because it is not Cart-specific, but stale analysis is never returned to the caller. SP-034 owns wiring this predicate to actual Cart/New Order/sign-out/session generations and owns deciding when analysis runs.

No production migration or deployment occurs in SP-033. The hosted environment still requires the repository SP-025–SP-028 and SP-031 migration chain before this analysis path can function against production data.

## Components

| Component | Responsibility | Decision status |
| --- | --- | --- |
| Flutter client | English UI with readable Arabic data; Android and Windows | Confirmed |
| Supabase Postgres | Authoritative products, prices, product revisions | SP-003 schema defined; deployment deferred |
| Supabase Auth and server authorization | Owner-only email/password access; no app registration; auth events gate protected UI | SP-004 server boundary + SP-006 client boundary implemented; hosted acceptance pending |
| Riverpod controllers/providers | Screen state, dependency injection, loading/error handling | Confirmed by owner; compatible package version to select during setup |
| Repository interfaces | Isolate catalog access, account access, and session storage from widgets | Proposed implementation baseline |
| Auth session storage | Persist the Supabase auth session in platform secure storage, not ordinary preferences | SP-006 uses `flutter_secure_storage` 11.2.0 on Android/Windows |
| Local app session store | Save the active cart/order snapshot and active unsaved edit draft without copying the catalog; retain the legacy destination field only for v1 compatibility | SP-009 keeps product drafts account-scoped; SP-011 adds a separate versioned account-scoped snapshot in the same secure key-value boundary; SP-021 always restores the visible workspace to Cart |
| Android camera adapter | Produce deliberate barcode scan events | Confirmed; package to verify |
| Windows reader adapter | Produce scan events from the owner's external reader | Deferred future task; re-authorize after hardware/input mode selection |
| External DDI provider | Return informational label-derived interaction evidence for trusted ingredient queries | SP-032 implements the typed HTTP client; SP-033 implements batching/aggregation; SP-034 wires Cart lifecycle; SP-035 renders severity/coverage; SP-036 renders evidence/source/attribution details |

Package versions are pinned in `pubspec.yaml`/`pubspec.lock` after compatibility verification against Flutter 3.38.7 / Dart 3.10.7. SP-006 uses `supabase_flutter` 2.17.2 and `flutter_secure_storage` 11.2.0; Android minimum SDK is 23 because of the secure-storage requirement.

## Code boundaries

Organize code by feature: authentication, catalog, order, and scanning. Keep application bootstrap and shared UI separate from feature behavior. Each feature separates widgets from controllers and data access as needed; do not generate empty layers just to match a folder diagram.

- Widgets render state and dispatch user actions. They do not issue database queries.
- SP-022 keeps the Cart as the persistent primary pane. The catalog search panel is a presentation adapter over the existing search/repository controllers: its result overlay changes layout behavior only, not query or authorization semantics. Wide windows use a supporting acquisition pane; compact windows stack acquisition controls above the same cart.
- Controllers manage user actions and state transitions.
- Repositories expose typed operations and hide Supabase or local storage details.
- Domain models and the order calculator are independently testable Dart code.
- Platform scanner adapters emit the same barcode event type to the order workflow. On Android, SP-020 keeps barcode detection in `mobile_scanner`/ML Kit, disables auto zoom, and uses one narrow Flutter `MethodChannel` to request a best-effort native `ToneGenerator` success beep; light haptic feedback remains in Flutter.
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
- Selling amount is whole-unit `bigint` paired with the typed `app_private.catalog_currency` enum (`SYP` / `USD`); zero is representable only for a source-import anomaly. RPCs cast the enum label back to text so existing Flutter/domain payloads stay compatible. SP-020 formats amounts with comma thousands separators at the UI/input boundary only; parsing strips those separators before producing the same integer domain value.
- SP-024 normalizes manufacturer and dosage form as private reference tables plus nullable product foreign keys. Canonical display strings remain on `products` as trigger-maintained compatibility/search caches, while alias tables preserve observed spellings. The product form loads owner-authorized reference options for autocomplete but can still submit a genuinely new label; the database atomically creates or reuses the normalized reference.
- Each accepted database update increments `revision` exactly once. SP-004 must combine this with an atomic expected-revision predicate before exposing mutations.

## Catalog reads and automatic refresh

- Supabase is the source of truth. SP-023 keeps manual search server-side and bounded, but replaces literal table scans with normalized indexed lexical retrieval: stored normalized search fields, a weighted `simple` full-text document with GIN, `pg_trgm` fuzzy/substring retrieval with GIN, and name-prefix indexes. Ranking favors exact barcode/name, name prefix, weighted multi-token prefix, composition, substring, then typo similarity. Arabic normalization removes common marks/tatweel, unifies common alef/ya variants and Arabic/Persian digits, while Unicode NFKC and punctuation/whitespace normalization apply across languages.
- Use exact text matching across both `barcode` and `barcode2`, returning distinct products by identity. Either field identifies the same package; cross-product collisions require user selection regardless of which field matched. Exclude empty identifiers. The owner-authorized barcode RPC returns the complete current product snapshot needed by the order flow; SP-017 uses that snapshot directly instead of adding a redundant immediate `catalog_get` round-trip. See `DATA_MODEL.md`.
- Distinguish loading, no match, ambiguous match, connection failure, and authorization failure.
- Ignore responses for superseded searches so slow requests cannot replace newer results. The Flutter search debounce is 180 ms after SP-023; request-generation guards still discard stale responses.
- SP-012 refreshes only relevant visible/session data: the active nonblank search, currently loaded detail, and products already present in the active order. It refreshes on application resume and uses a bounded two-minute poll only while the protected app is active; it does not subscribe to or replicate the full table.
- Refresh continues through the existing bounded `catalog_search` / `catalog_get` repository operations. A failed refresh preserves last-known visible data and exposes a stale/retry state; a later successful bounded read is the recovery signal, so no separate connectivity dependency is required.
- Before adding a product from search to a new order line, re-read that exact identity with `catalog_get`; if the read fails, leave the order unchanged rather than capturing a potentially stale price.
- Re-read authoritative values after resume/recovery; a transient notification alone is not durable evidence that the displayed state is current.

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
- Adding quantity to an existing line uses the line's captured amount and currency. SP-012 re-reads active order identities and records a server amount/currency change as a per-line notice without silently changing totals; accepting a valid new pair is explicit and atomic.
- New customer orders use current server prices. Revalidate saved order products/prices on resume before claiming the data is current.
- Use exact integer monetary arithmetic in whole currency units for both SYP and USD. Aggregate separately by captured currency; do not implement exchange rates or a converted/combined grand total. Validate prices and currency before addition, and detect overflow. See `DATA_MODEL.md`.
- Preserve the existing order during network failures. New server-dependent catalog lookup and mutation operations cannot succeed offline.
- Do not add sales history, inventory deduction, payment processing, or fractional-package conversion.

## Session persistence

- Persist the order snapshot, including quantities, captured prices, and captured currencies, on state changes rather than relying solely on a shutdown callback. SP-021 has one visible Cart workspace; the existing destination field/provider is retained only for version-1 session compatibility, and legacy Catalog/Order destinations normalize to Cart on restore.
- Persist active edit input with the owner identity, product identity, and original server revision. Restoring a draft must not silently adopt a newer revision or replace user input. Preserve atomic/versioned writes and report local persistence errors.
- Keep draft persistence separate from server mutations: startup/reconnect cannot enqueue or submit writes. Only explicit Save triggers validation and revision-checked persistence. Reconcile ambiguous prior save outcomes before retrying; prevent stale asynchronous draft writes from resurrecting discarded or successfully saved input.
- Write snapshots atomically and include a schema version. Corrupt snapshots must cause an explicit recoverable error, not silent loss represented as a successful restore.
- A confirmed New Order reset must persist the empty active order without history. Invalidate pending scan/lookup responses belonging to the previous order so they cannot populate the new one. Report snapshot-write failures explicitly.
- Associate saved sessions with the authenticated owner. Sign-out retains persisted order/draft state but clears protected visible/in-memory presentation state. Restore only after successful authentication as the same owner; never expose it to another or signed-out account. Preserve active draft input before hiding the form, and prevent late asynchronous responses from repopulating signed-out UI.
- Persist only what restoration needs. In-memory search results are not a reason to create a persistent catalog cache.
- Search text, exact scroll position, and filter restoration are not acceptance requirements. Restore the order into Cart and retain draft restoration under `UX_FLOWS.md`.
- This small local snapshot still contains some product names/prices. Online-only does not mean zero local data.

## Platform input

- Android: a compact scanner panel can remain open inside the Cart workspace for continuous multi-item scanning. Permission-denied and unavailable-camera states remain explicit. A presentation gate suppresses a barcode while it remains visible and unlocks it after an observed absence window so a later presentation can be deliberate.
- Windows external barcode reader: deferred from the current initial delivery. When the owner re-authorizes it later, first identify the reader model, connection/input protocol, terminator, and any driver/SDK requirements. Keyboard-emulation readers and serial/vendor-specific readers need different adapters; do not claim universal compatibility without evidence.
- Preserve barcode text, including leading zeros. Do not silently normalize codes into different identifiers.

## Remaining design decisions

- For any future Windows reader task, confirm the hardware/input mode before implementation; Android camera compatibility is already established for the merged SP-013 baseline.
- SP-004 remains the owner-only bounded catalog RPC boundary; SP-012 does not add direct-table reads, full-table subscriptions, or a local catalog replica.
- Session, sign-out, reset-order, refresh, price-change, and unsaved-edit behavior is specified across `PRODUCT.md`, `DATA_MODEL.md`, and `UX_FLOWS.md`.
- Hosted CI is retired by OPS-001. Keep local verification helpers available, and use owner real-device testing for scanner/hardware behavior as described in `QUALITY.md`.

## Official references used in the proposal

- [Flutter architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
- [Supabase Flutter quickstart and supported platforms](https://supabase.com/docs/guides/getting-started/quickstarts/flutter)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase API key boundaries](https://supabase.com/docs/guides/getting-started/api-keys)
- [Riverpod](https://riverpod.dev/)

References support technology capabilities and general practices. The product scope and user-visible behavior come from the owner's decisions in `PRODUCT.md`.
