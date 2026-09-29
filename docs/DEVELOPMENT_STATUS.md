# Sherko Pharma — Development Status

Updated: 2026-09-29
Task record: SP-033 / Issue #75 builds the pure Cart DDI analysis/batching engine from merged SP-031 ingredient inputs and SP-032 provider transport. SP-032 / Issue #74 / PR #82 is merged. OPS-001 / Issue #42 keeps hosted GitHub Actions and mandatory CI gates retired.
Status: SP-033 adds a typed ingredient RPC adapter plus deterministic ingredient deduplication/ownership mapping, complete <=10/>10 provider batching, product-pair aggregation, explicit provider-unresolved state, bounded one-hour in-memory batch caching, in-flight coalescing, local 60/minute throttling, one valid Retry-After retry, and a generic stale-generation guard. It is not wired into Riverpod Cart/scanner lifecycle state and adds no UI, production migration, or deployment. SP-014 remains deferred.

## Verified baseline

- The latest merged repository baseline before SP-033 is SP-032 merge `017f9a2c0cb3e958e2ad201cccb4277c0a482f04` from PR #82. Hosted Supabase remains deployed through SP-024 only; SP-025 through SP-028 and SP-031 migration 0013 are not applied by these repository tasks.
- SP-000 through SP-013, SP-015 through SP-032, CI-001, and OPS-001 are merged before this task; SP-014 remains deferred.
- Issue #29 is closed as completed and PR #30 is merged; post-merge CI run `36250531971` passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.
- No open Issue or PR existed immediately before SP-012 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

## SP-033 Cart DDI analysis/batching contract

- SP-033 is tracked by Issue #75 from SP-032 merge `017f9a2c0cb3e958e2ad201cccb4277c0a482f04`.
- `SupabaseDdiIngredientRepository` is the typed Flutter adapter for SP-031 `catalog_ddi_ingredients(uuid[])`; raw RPC response maps do not escape the data layer. It preserves `trusted|needs_review|unresolved|missing` coverage and exposes ingredient identities only for trusted rows.
- Analysis accepts product IDs only and chunks ingredient-resolution reads to the 50-ID SP-031 bound. Quantity, price/currency, barcode, account/session identity and raw composition are outside the engine input.
- Stable ingredient IDs deduplicate shared ingredients while retaining every owning product. Provider query strings use canonical ingredient names and are validated against the SP-032 80-character input bound.
- For <=10 unique ingredients the engine emits one provider batch. For >10 it partitions deterministic stable-ID order into groups <=5 and emits every pairwise group union. Each request remains <=10 and every unique ingredient pair co-occurs in at least one batch.
- Overlapping batches can repeat same-group pairs. Ingredient interactions and evidence are deduplicated before mapping to product pairs.
- Provider-resolved items are mapped back through the exact submitted query. Every query in each batch must appear once as resolved or provider-unresolved; unexpected/omitted/contradictory resolution fails explicitly instead of synthesizing `none`.
- Provider-unresolved ingredients retain suggestions without auto-selection and remain separate from SP-031 normalization review/unresolved/missing states.
- Same-product-only ingredient pairs do not create product-vs-product output. Shared ingredients map interactions to all distinct owning product combinations.
- Product-pair severity is `major > moderate > minor > unknown > none`; every unique causal ingredient interaction and its evidence/source/link data remains available under the aggregate.
- Provider data dates, disclaimer and attribution are retained as deduplicated notices for downstream UI.
- Successful batch results use a bounded in-memory cache only: one-hour TTL and 128 entries by default. Identical in-flight batches are coalesced. No DDI result/history is persisted.
- Provider attempts are serialized inside the engine and locally throttled to 60 per rolling minute by default. A 429 with a valid positive `Retry-After` retries once; a second 429 or absent/non-positive delay propagates. No other automatic retry is introduced.
- An optional `isCurrent` predicate is checked around asynchronous boundaries. When false, `DdiAnalysisSupersededException` stops later work and prevents stale result publication. SP-034 will wire this mechanism to real Cart/New Order/session/auth generations.
- Focused tests cover typed RPC mapping/isolation of untrusted identities, combination/shared ingredients, same-product exclusion, 11-ingredient complete pair coverage, duplicate suppression, severity aggregation including `unknown`, provider-unresolved separation, in-flight coalescing, cache reuse/bounds, Retry-After behavior, local throttling, stale work, and >50-product RPC chunking.
- No live Interaction Checker request, production Supabase call, backend migration, deployment, Riverpod Cart wiring or UI is part of SP-033.

## SP-032 Interaction Checker client contract

- SP-032 is tracked by Issue #74 from SP-031 merge `dbc0da03d4292c84255084beaf4f967ad2b898a1`.
- `http` 1.6.0 is declared as a direct runtime dependency; the same version was already locked transitively, so the lockfile version/checksum remain unchanged apart from direct-dependency classification.
- `InteractionCheckerClient` uses the versioned `/api/v1/checks` POST endpoint, an injectable base URI and injectable `http.Client`, with a configurable positive timeout defaulting to 10 seconds.
- Local requests are rejected before network use unless they contain 2–10 nonblank item strings of at most 80 characters. The client does not add authentication or Sherko Pharma/Supabase metadata.
- Typed models preserve resolved query/matchedOn values, unresolved suggestions, pair endpoints, the five pair severities, evidence/source metadata, data dates, disclaimer and attribution.
- Evidence severity is intentionally narrower than pair severity and accepts only the OpenAPI-documented `major|moderate|minor|none`; an `unknown` evidence value fails explicitly rather than being invented as valid.
- Additive optional response fields are ignored. Missing/malformed required success fields produce a malformed-response failure, and unsupported required enum values produce an explicit unsupported-response-value failure.
- HTTP 429 produces a rate-limit failure carrying a valid numeric `Retry-After` duration plus documented provider code/message when available. Other non-2xx responses produce typed API failures. Timeout and transport failure are distinct. No automatic retry is performed.
- The layer logs/persists neither medication queries nor complete provider payloads and preserves successful provider disclaimer/attribution for later UI use.
- Focused test `test/interaction_checker_client_test.dart` uses `package:http/testing.dart` only; it does not call the live provider. Coverage includes POST request shape, typed evidence/source parsing, all pair severities, unresolved suggestions, local bounds, 429/no retry, provider error metadata, malformed/missing fields, unsupported severities, timeout vs transport, and additive unknown fields.
- The provider API/OpenAPI/terms were re-checked on 2026-09-29. Current docs still state no key, 60 requests/minute/IP, 2–10 check items, one-hour cacheability, versioned additive fields and required attribution/disclaimer behavior. Current terms remain unsuitable for selling/presenting the output as a clinical decision-support product.
- No SP-031 RPC consumption, Cart aggregation/batching, scanner integration, severity UI, source navigation, backend/production migration, or external deployment is part of this task.

## SP-031 trusted DDI ingredient-input contract

- SP-031 is tracked by Issue #73 from SP-030 merge `50eda1567418b100f0561d604b40e85e2fa95d0a`.
- Migration `0013_ddi_ingredient_inputs_api.sql` adds `public.catalog_ddi_ingredients(uuid[])`; this task does not deploy it to the hosted environment.
- The RPC requires the existing owner authorization check. Anonymous callers have no EXECUTE privilege, authenticated non-owners are denied, and the owner still has no normal direct-table access to the private ingredient registry.
- Requests must contain explicit product UUIDs, reject null arrays/IDs, return no rows for an empty array, and are hard-limited to 50 input positions. Duplicate product IDs are collapsed to their first request position.
- Coverage is explicit: `trusted`, `needs_review`, `unresolved`, or `missing`. A trusted result requires an SP-025 `auto_verified` or `high_confidence` summary, non-null set key, full component resolution, and a complete product-ingredient link count.
- Trusted products return every component in deterministic component order with stable ingredient ID, canonical display name, and canonical normalized ingredient name.
- Review/unresolved/missing or structurally incomplete products return no ingredient identity fields, preventing downstream guessing from raw composition or brand text.
- The RPC does not expose raw composition components, alias spellings, unrestricted registry enumeration, prices, barcodes, revisions, notes, patient/account data, or external DDI results.
- Focused test `012_ddi_ingredient_inputs_api_test.sql` covers owner/non-owner privileges, private-registry isolation, auto-verified and high-confidence trusted inputs, multi-ingredient ordering, review/unresolved/missing states, duplicate IDs, empty/null inputs, null IDs, and the hard request cap.
- Local SQL execution was not available in the agent environment: there was no Supabase CLI, PostgreSQL client, or Docker, and the container could not resolve GitHub. The SQL regression was therefore added and separately reviewed but not executed in this session.

## SP-030 DDI product/safety contract

- SP-030 is tracked by Issue #72 from the merged SP-029 baseline `c8919074247b950005ac9835779b2f7afdd62094`.
- The future DDI surface is informational label-derived evidence over distinct products in the active Cart; quantity is not dose information and does not change pair identity.
- Product identity is bridged through the existing conservative SP-025 ingredient normalization layer. Syrian/local brand names, fuzzy guesses, `needs_review`, and `unresolved` mappings are never silently promoted into external drug identities.
- Provider severity is preserved as `major`, `moderate`, `minor`, `none`, or `unknown`. `none` is only an explicit source statement of no clinically significant interaction; `unknown` means neither available label mentions the other and is not proof of safety.
- Downstream result presentation must retain evidence/source context, source effective date when available, Interaction Checker attribution/backlink, and the provider-supplied disclaimer. No result is converted into prescribing, treatment, substitution, stop/start, dosage, or patient-specific advice.
- Provider/network failure, 429/rate limiting, malformed responses, unresolved ingredients, partial coverage, and stale results remain explicit and cannot be represented as no interaction.
- External DDI checking is non-destructive and transient: it cannot mutate catalog/order/session/draft/alternative state and does not create medication-history or interaction-history persistence. Session restoration rechecks the current Cart online.
- The third-party request carries only the ingredient queries necessary for the check. It must not carry account identity, patient identity, barcodes, prices, notes, Supabase credentials/tokens, or unrelated catalog data.
- The provider currently documents no API key, 60 requests/minute/IP, 2–10 inputs per `/checks`, one-hour cacheability, and `Retry-After` on 429. These provider-controlled facts must be re-checked in downstream implementation/release tasks.
- Interaction Checker's terms were re-checked on 2026-09-29 and are marked last updated September 2026. They describe the tool as informational, disclaim completeness/accuracy, require disclaimer/backlink with shown API output, and prohibit using the API to build or sell a clinical decision-support product or redistribute the dataset as a whole.
- Therefore SP-030 makes no commercial/public-release permission claim. Before such a release, obtain compatible provider permission or replace the DDI source/license.
- External references: https://interaction-checker.com/api, https://interaction-checker.com/api/v1/openapi.json, https://interaction-checker.com/terms.
- Planned implementation remains split across Issues #73–#79 (SP-031–SP-037); those Issues are not authorized to start merely because they exist.

## SP-029 alternatives-UI contract

- SP-029 is tracked by Issue #70 from SP-028 merge `24acccc4a892344bed605b1e93808b1c73803d08`.
- Flutter adds a typed `CatalogAlternative` relationship model and extends `CatalogRepository` with a bounded alternatives read. Raw RPC maps do not enter presentation code.
- The Supabase repository calls `catalog_alternatives`, clamps client requests to 25 per group, accepts only the three known relationship labels plus trusted `auto_verified`/`high_confidence` normalization states, and maps a missing target to the existing not-found error.
- Cart search rows expose a compact Alternatives action without replacing Open/Add behavior. Product Detail exposes the same action.
- Both entry points use one reusable modal sheet; no new primary destination or persistent alternatives state is added.
- The sheet presents fixed, separate descriptive sections for same ingredients/strength/form, different strength, and different form. It displays product/brand, company, price/currency, strength, and dosage form.
- A visible notice states that the groups are catalog-derived and do not establish clinical interchangeability or prescribing suitability.
- Add-to-cart first re-reads the candidate through `catalog_get`, then uses the existing `OrderController.addProduct`. Network failure, invalid current price, and arithmetic overflow leave the Cart unchanged and show explicit feedback.
- Repository/widget regressions cover typed RPC mapping, malformed metadata, limit clamping, loading/error/retry/empty states, grouped rendering, both entry points, and current-price revalidation before Add.
- No production schema migration is deployed by SP-029. The visible feature requires hosted migrations 0009–0012 before the SP-028 RPC exists in production.

## SP-028 alternatives-engine contract

- SP-028 is tracked by Issue #68 from SP-027 merge `d01fa988ea85bea5bdbd0f487e6cfce6042baaae`.
- `public.catalog_alternatives(uuid, integer)` is the only new client-facing API in this task. It follows the existing owner-gated SECURITY DEFINER pattern and keeps private normalization tables inaccessible to normal client roles.
- The target must be trusted through SP-025, SP-026, and SP-027. If the target cannot be classified safely, the function returns no relationship rows instead of weakening the model.
- `exact` means the same trusted non-null strict-equivalence key.
- `same_ingredients_different_strength` means the same trusted ingredient identities and same trusted form/route/release dimensions, but a different trusted ingredient-strength set.
- `same_ingredients_different_form` means the same trusted ingredient-strength set while the trusted form/route/release tuple differs.
- Candidates that differ in both strength and form are outside these three groups and are omitted. Groups are designed to be mutually exclusive.
- The target is excluded from its own results. Stable name/identity ordering is deterministic only and does not create a best/cheapest/preferred ranking.
- The API defaults to 10 results and clamps to a hard maximum of 25 rows per group.
- Returned `normalization_status` is derived-model confidence only, not a clinical recommendation or probability.
- Focused regression coverage exercises owner authorization, exact/strength/form grouping, group exclusivity, unresolved exclusion, target exclusion, deterministic ordering, not-found handling, and the hard result cap.
- SP-029 now provides the Product/Cart UI presentation and revalidated order-add interaction.
- No SP-025/SP-026/SP-027/SP-028 production migration is deployed by this repository task.

## SP-027 pharmaceutical-equivalence contract

- SP-027 is tracked by Issue #66 from SP-026 merge `d92a4f9edb6d91222663159654c96aa11627bc83`.
- Read-only hosted profiling found roughly 280 dosage-form references. A conservative prototype recognized trusted form/route semantics for 81 reference values covering 16,741 products, marked 11 injection-like forms / 1,445 products for review because the specific parenteral route is absent, and left 180 forms / 3,680 products unresolved; another 1,884 products have no dosage form.
- The source has no dedicated route/release columns. SP-027 therefore derives those dimensions only from sufficiently explicit dosage-form reference text and never guesses a missing parenteral route.
- A private dosage-form profile stores form class, route, release class, status, and reason. A private per-product equivalence summary combines that profile with SP-025/SP-026 states.
- Strict keys require trusted composition, trusted ingredient-strength pairing, and a complete trusted dosage-form profile. Immediate, extended, and delayed/enteric release classes remain distinct, as do clinically distinct routes/forms.
- Upstream `high_confidence` propagates; it is never upgraded to auto-verified. Review/unresolved products never receive a strict key.
- Composition edits refresh SP-025 → SP-026 → SP-027; strength-only edits refresh SP-026 → SP-027; dosage-form edits refresh SP-027 after SP-024 reference resolution.
- Structural backfill guards composition, strength, dosage form/reference, revision, and `updated_at` against mutation.
- SP-028 provides the bounded alternatives API/grouping; SP-029 provides the reusable Product/Cart alternatives UI.
- No SP-025/SP-026/SP-027 production migration is deployed by this repository task.

## SP-026 strength-normalization contract

- Read-only hosted profiling at task start found 19,084 rows with nonblank strength, 3,825 distinct strength strings, 4,042 rows containing `+`, and 14,810 rows containing `/`.
- Slash syntax is heterogeneous: source examples include presentation suffixes such as `500 MG/CTD TAB.` and `1 G/VIAL`, plus quantitative concentrations such as `250 MG/5 ML.` and `1 MG/ML.`.
- `products.strength` remains untouched raw/editable text. SP-026 adds only private derived summary/link rows.
- Supported deterministic units normalize exactly with PostgreSQL `numeric`: mass to `mg`, quantitative denominator mass/volume to `mg`/`ml`, while IU, generic U, mEq, mmol, and percent remain distinct unit domains.
- Trusted multi-ingredient pairing requires a trusted SP-025 composition plus an exact `+` component-count match. Even then, positional multi-ingredient mappings are capped at `high_confidence` because they depend on source ordering. The hosted source has 3,970 multi-ingredient rows with matching counts and 783 with mismatched counts before applying SP-025 trust filters.
- Recognized presentation suffixes are removed from numeric comparison only; they are not treated as route/release equivalence. A shared trailing quantitative denominator across multiple explicit strength components produces at most `high_confidence`.
- Mismatched, partial, unitless, unsupported, descriptive, or SP-025 review/unresolved cases never receive a trusted ingredient-strength set key.
- Ingredient-strength set keys are order-independent by normalized ingredient identity, so reversed ingredient order plus correspondingly reversed strength order can still compare equal.
- Composition+strength edits refresh SP-025 first and SP-026 second; strength-only edits refresh SP-026. Structural backfill guards raw composition/strength, revision, and `updated_at` from mutation.
- SP-027 provides the conservative dosage-form/route/release compatibility layer and strict pharmaceutical-equivalence key; SP-028/SP-029 provide the alternatives API and UI layers above it.

## SP-025 composition-normalization contract

- The exact `public.products.composition` value remains authoritative raw/display text; SP-025 does not rewrite it.
- A private ingredient registry stores deterministic lexical identities plus observed spellings. No fuzzy or automatic medical synonym merge is seeded.
- Product compositions are split only on explicit `+` separators. Ingredient links preserve component order and raw component labels.
- An order-independent ingredient-set key allows later comparison of conservatively parsed ingredient identities, but it intentionally excludes strength, dosage form, route and release semantics.
- Normalization status is one of `auto_verified`, `high_confidence`, `needs_review`, or `unresolved`. Parentheses/special delimiters, embedded strength units, duplicate components and incomplete splits are quarantined instead of guessed.
- `high_confidence` is reserved for future explicitly verified semantic aliases; SP-025's initial automatic population is lexical-only.
- The migration backfills one normalization summary for every product and guards that `composition`, `revision`, and `updated_at` are unchanged by the structural backfill.
- An after-insert/update trigger refreshes derived composition rows when composition changes through the existing catalog API. Existing revision/conflict authorization remains unchanged.
- SP-026 strength normalization and SP-027 pharmaceutical equivalence are separate derived layers above SP-025. SP-028 provides bounded relationship querying and SP-029 provides its visible Product/Cart presentation.

## SP-024 product reference-data contract

- Hosted profiling at task start: 23,750 products; 351 exact / 350 safe reference-key manufacturer values including one symbolic `-`; 280 exact / 272 normalized dosage-form values; 2,204 compositions; 3,825 strengths; 2,280 package descriptions.
- Manufacturer and dosage form are dynamic reference entities, not PostgreSQL enums. Each has a stable bigint ID, canonical label, normalized unique key and alias table.
- Canonical spelling is chosen from the most frequent observed source spelling for each safe normalized key; different normalized keys are never fuzzy-merged automatically.
- Products retain canonical manufacturer/dosage-form display strings for RPC/search compatibility and also store nullable FKs. A trigger keeps the pair consistent on insert/update.
- Existing source spellings remain recoverable through alias tables and the immutable source payload; no product rows are dropped.
- Currency is the finite `app_private.catalog_currency` enum with `SYP` and `USD`, while current RPCs continue returning text labels.
- Composition, strength, package description, names, notes and barcodes intentionally remain text. The dataset contains complex combinations/units/descriptions that are not safe to decompose automatically.
- The product form uses reference-aware autocomplete options for manufacturer and dosage form. Existing canonical values are suggested, while a new typed value is allowed and atomically normalized/created by the server.
- Reconciliation treats spelling-equivalent manufacturer/dosage-form values as the same saved reference so a lost response does not create a false conflict.
- Current hosted verification preserves 23,750 products with zero missing/dangling manufacturer or dosage-form FKs.

## SP-023 intelligent search contract

- Keep the existing `catalog_search(text, integer)` RPC signature, result shape, owner authorization and hard result bound.
- Normalize Unicode with NFKC; lowercase; remove common Arabic diacritics/tatweel; normalize common Arabic/Persian letter and digit variants; collapse punctuation and whitespace.
- Exact typed barcode ranks first but barcode matching remains exact text, preserving leading zeroes.
- Rank exact name above name prefix; then weighted multi-token prefix/full-text, composition, substring and typo similarity. Product names carry the highest relevance weight; composition is next; manufacturer/strength/dosage/package are secondary signals.
- Queries of one or two characters remain conservative; fuzzy expansion begins at three normalized characters with length-sensitive thresholds.
- Add `pg_trgm`, normalized stored search fields, weighted stored `tsvector`, GIN trigram/full-text indexes and name prefix indexes.
- Retrieve candidates through separate index-friendly branches before computing fuzzy/ranking scores.
- Hosted verification on 23,750 rows after `ANALYZE`: representative measured database execution was about 38 ms for a short prefix, 95 ms for `amoksiklaf`, 146 ms for `amoksiklav 1000`, 185 ms for Arabic `أموكسيكلاف 1000`, and 198 ms for `metfor 850` in the sampled runs.
- Flutter debounce is reduced from 300 ms to 180 ms; stale-response generation guards remain unchanged.
- No vector/semantic search is used for medication selection, and no client-side full catalog/cache is introduced.

## SP-022 professional Cart UX contract

- Search and Android Scan are one acquisition command surface. Opening one mode dismisses the competing mode so the operator is never managing two input surfaces.
- Manual search results render in a bounded elevated overlay anchored to search. The overlay does not change the cart summary/list layout or permanently consume cart height.
- Successful manual add/increment keeps the existing authoritative product revalidation, then clears the query and leaves search ready for the next product.
- Item count, separate SYP/USD totals and New Order stay visible above independently scrolling cart lines.
- Cart items use flat dense rows with subtle dividers, readable Arabic/English product identity, strong line totals, compact quantity controls and de-emphasized Remove.
- The scanner result/checking message is overlaid inside the camera surface to reduce vertical chrome; scan detection/feedback semantics are unchanged.
- Wide windows use a 420 px acquisition/supporting pane beside the persistent cart. Compact windows stack command/scanner above the cart.
- The application uses a restrained Material 3 blue-teal seed with a neutral light surface while retaining compact density and existing accessibility/touchability constraints.
- No Supabase/schema/API, scan algorithm, barcode identity, captured price/currency, draft, refresh or order-calculation changes belong to SP-022.

## SP-021 unified Cart contract

- Cart is the only visible primary application workspace after authentication; separate Catalog and Order navigation controls are removed.
- The same Cart page contains manual catalog search, Android Scan, current lines, quantity/remove controls, separate SYP/USD totals and New Order.
- Manual search keeps the existing server search and exact revalidation-before-add semantics. Product detail, product creation and product editing remain reachable as focused secondary routes.
- Phone layout stacks compact search/scanner/cart sections; wide desktop layout places compact acquisition controls beside the cart without creating another destination.
- Search result space is bounded so results do not replace the cart; result rows and cart rows use reduced padding/gaps/control chrome while preserving readable product identity and prices.
- Legacy version-1 session destination values remain parseable, but restoration normalizes the visible workspace to Cart and preserves the exact persisted order values.
- Permanent product UI rules now require comma thousands grouping for whole-unit monetary display/input and compact density throughout the application.
- No Supabase/schema/API, barcode lookup, captured price/currency, draft, refresh or order-calculation semantics change in SP-021.

## SP-020 amount-format and scanner-feedback contract

- Display whole-unit monetary amounts with comma thousands separators across catalog results, product detail, the selling-price form, order totals, unit prices, line totals, and price-change notices.
- Formatting is presentation/input normalization only: stored and calculated amounts remain exact integers in SYP or USD, with no decimals or conversion.
- The selling-price field accepts grouped text such as `200,000` and persists the integer value `200000`; persistent local drafts keep the price text ungrouped for schema/backward compatibility, and existing plain numeric drafts remain parseable.
- Disable Android scanner automatic zoom while retaining tap-to-focus, the compact scan window, one-RPC lookup, continuous scanning and repeat-presentation gating.
- Successful add/increment feedback uses a native Android `ToneGenerator` beep on the media stream plus Flutter light-impact haptic feedback. Both are best-effort and never block scanning.
- Error, ambiguous, unknown, invalid-price, overflow, stale/reset-discarded and held-frame duplicate outcomes produce no success beep/haptic.
- The Android scanner backend uses ML Kit, which recognizes barcodes regardless of orientation; no extra rotation transform or format restriction is added. A 180-degree upside-down package remains a real-device acceptance check.
- Real-device beep volume, haptic strength and rotated-package recognition remain owner verification after pull/merge.

## SP-019 scanner feedback contract

- Keep SP-018 compact layout and SP-017 continuous scanning, one-RPC lookup and repeat-frame protection unchanged.
- Scanner guide states: white while ready, amber while checking, green after a successful add/increment, and red for non-mutating scan failures.
- Success/error guide colors are transient and return to the idle white state after 650 ms.
- Play Flutter's platform `SystemSoundType.click` only after `added` or `incremented`; sound feedback is best-effort and never blocks scanning.
- Do not add an audio dependency or bundled audio asset for this task.
- Keep Android `autoZoom: true` and tap-to-focus unchanged.
- Real-device sound behavior and visual timing remain owner verification after pull/merge.

## SP-018 compact scanner UI contract

- Keep SP-017 continuous scanning, one-RPC lookup, repeat-frame protection and order semantics unchanged.
- Reduce the camera preview from the prior 160 px panel to a compact 112 px strip with minimal outer padding and no separate scanner title row.
- Keep the close action overlaid on the preview and the result/checking status to one compact line.
- Make the overlay explicitly fill the complete camera preview before painting the guide so its coordinate system matches the scan window.
- Use a smaller centered guide capped at 300 px wide and 58 px high; update the internal scan window on every actual geometry change instead of applying a threshold.
- Compact the mobile Order header into one title/totals row plus one side-by-side actions row, and reduce mobile order-row padding/control sizes so scanned items stay visible.
- Real-device visual alignment remains owner verification after pull/merge.

## SP-017 continuous scanner contract

- One Android Scan action opens a compact inline scanner on the Order page; successful scans do not navigate away or require reopening the camera.
- The camera overlay is visual only; the instructional tip text is removed.
- A unique barcode is resolved by one owner-authorized `catalog_lookup_barcode` call. The lookup already returns the current complete product snapshot needed for order capture, so the immediate second `catalog_get` round-trip is removed.
- The camera remains active while server checking runs. A presentation gate suppresses the same code while it remains visible and unlocks it after it has been absent long enough, allowing a deliberate later presentation to increment quantity.
- Order reset/session replacement advances an order mutation generation; a barcode lookup started against an older generation is discarded before it can mutate the new/restored order.
- Unknown, ambiguous, invalid-price, overflow, permission, network and camera states remain non-destructive.
- Real-device throughput, framing and repeat-scan behavior remain owner verification after pull/merge.

## SP-016 scanner refinement contract

- Keep the existing exact barcode identity, ambiguity, authoritative catalog re-read, order mutation, and deliberate-repeat behavior unchanged.
- Show a centered horizontal barcode guide and use the same rectangle as the actual scanner scan window.
- Keep throttled `DetectionSpeed.normal` behavior while reducing the camera-side detection timeout from 250 ms to 100 ms.
- Enable Android-supported auto zoom and tap-to-focus without restricting the accepted barcode formats.
- Pause frame analysis after the first accepted capture so retries can rearm the existing camera session quickly while repeated frames remain blocked.
- Real-device responsiveness and framing remain owner verification after pull/merge.

## SP-015 delivery contract

- Preserve the implemented SP-000 through SP-013 product behavior while preparing release-mode Android and Windows candidates.
- Android identity is `com.samo.sherkopharma`; release builds must not fall back to the Flutter debug key.
- Production signing material remains outside Git.
- Windows release packaging covers the complete runner bundle; no production code-signing claim is made without an external certificate.
- Hosted CI is retired. Owner-controlled local builds, packaging, checksums, signing, runtime configuration and testing follow `RELEASE.md` and `QUALITY.md`.
- The acceptance matrix in `DELIVERY_ACCEPTANCE.md` records deferred SP-014 and the remaining owner-only actions before public distribution.

## SP-013 contract

- Android camera scanning resolves complete barcode text through the existing bounded owner-authorized catalog API.
- Match either approved barcode field, preserve leading zeroes, deduplicate the same product identity, and reject ambiguous distinct-product matches.
- SP-013 originally re-read the resolved product with `catalog_get`; SP-017 supersedes that extra round-trip because `catalog_lookup_barcode` itself is owner-authorized and returns the complete current product snapshot used for order capture.
- Repeated frames from one physical presentation must not increment quantity; a deliberate later scan can increment the existing line.
- Unknown, ambiguous, invalid-price, permission, and camera interruption states are non-destructive and recoverable.
- No Windows reader integration, inventory, checkout/history, cloud order sync, full catalog cache, or production release work belongs to SP-013.

## Implementation state

- SP-022 refines that workspace into a POS-style interaction model: persistent cart context, transient search results, integrated search/scan acquisition, flat cart rows and adaptive supporting pane.
- SP-021 presents the customer workflow as one compact Cart workspace with embedded manual search and Android scanning; the previous visible Catalog/Order navigation is retired.
- Added an Android-only order Scan action backed by `mobile_scanner`, pinned to a reviewed upstream commit in the application lockfile.
- Added exact `catalog_lookup_barcode` repository access without direct product-table reads or a new backend migration.
- Barcode lookup preserves the scanned string, deduplicates results by product ID, and treats multiple distinct product matches as ambiguous.
- The scan controller is single-flight and delegates the server lookup snapshot to the existing order controller for price/currency/overflow rules; SP-017 removes the redundant immediate `catalog_get`.
- SP-017 keeps the camera in a compact inline Order-page panel for continuous scanning. The same visible barcode is suppressed until it leaves the frame long enough to count as a new presentation.
- Scanner lifecycle handling stops the camera while inactive and only resumes an uncommitted scan after the app returns active.
- Android camera permission is declared without making camera hardware a required installation feature.

## Verification policy

Requirement-derived tests remain in the repository and can be run locally when useful. The owner explicitly reported the real Android camera test as PASS on 2026-09-26. Historical CI evidence from earlier completed tasks remains part of Git history, but it is no longer a current merge or completion requirement.

Under OPS-001, the owner pulls/tests revisions locally and reports problems for bounded follow-up fixes. Future SP-014 work still requires fresh owner authorization and selected hardware/input-mode evidence.
