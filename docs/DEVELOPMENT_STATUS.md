# Sherko Pharma — Development Status

Updated: 2026-09-27
Task record: SP-026 / Issue #64 adds conservative ingredient-strength normalization on top of SP-025 without rewriting raw strength text. SP-025 / Issue #62 remains the ingredient-identity baseline. OPS-001 / Issue #42 retires hosted GitHub Actions and mandatory CI gates.
Status: SP-026 derives exact canonical strength measures and trusted ingredient-strength pairs only when syntax/component alignment is deterministic, distinguishes quantitative concentration denominators from recognized presentation suffixes, and quarantines ambiguous or incomplete source values. Backend authorization, raw composition/strength, barcode identity, captured-price and order semantics remain unchanged. SP-014 remains deferred. Current verification policy is owner-local after pull; hosted CI is retired.

## Verified baseline

- The latest merged repository baseline before SP-026 is SP-025 merge `20782ce64cc72535502d9987a7ef636c9c8df2a9` from PR #63. Hosted Supabase remains deployed only through the earlier schema baseline; SP-025 and SP-026 migrations are not applied by these repository tasks.
- SP-000 through SP-013, SP-015 through SP-024, CI-001, and OPS-001 are merged; SP-014 remains deferred.
- Issue #29 is closed as completed and PR #30 is merged; post-merge CI run `36250531971` passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.
- No open Issue or PR existed immediately before SP-012 was authorized.
- The dedicated Sherko Pharma Supabase project is active on the Free plan.
- Hosted migrations `sp003_product_schema`, `sp004_owner_catalog_api`, and `sp008_idempotent_catalog_create` are deployed.
- The approved corrected source catalog was imported and verified at exactly 23,750 imported rows, 23,750 distinct source IDs, and zero remaining manual rows.
- Import anomaly counts remain consistent with the approved source: 423 zero-price rows, 8,260 blank primary barcodes, and 22,495 blank secondary barcodes.

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
- SP-027 remains responsible for dosage-form/route/release compatibility and strict pharmaceutical equivalence. SP-028/SP-029 remain alternatives API/UI tasks.

## SP-025 composition-normalization contract

- The exact `public.products.composition` value remains authoritative raw/display text; SP-025 does not rewrite it.
- A private ingredient registry stores deterministic lexical identities plus observed spellings. No fuzzy or automatic medical synonym merge is seeded.
- Product compositions are split only on explicit `+` separators. Ingredient links preserve component order and raw component labels.
- An order-independent ingredient-set key allows later comparison of conservatively parsed ingredient identities, but it intentionally excludes strength, dosage form, route and release semantics.
- Normalization status is one of `auto_verified`, `high_confidence`, `needs_review`, or `unresolved`. Parentheses/special delimiters, embedded strength units, duplicate components and incomplete splits are quarantined instead of guessed.
- `high_confidence` is reserved for future explicitly verified semantic aliases; SP-025's initial automatic population is lexical-only.
- The migration backfills one normalization summary for every product and guards that `composition`, `revision`, and `updated_at` are unchanged by the structural backfill.
- An after-insert/update trigger refreshes derived composition rows when composition changes through the existing catalog API. Existing revision/conflict authorization remains unchanged.
- SP-026 strength normalization, SP-027 pharmaceutical equivalence, SP-028 alternatives querying and SP-029 alternatives UI remain separate future tasks.

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
