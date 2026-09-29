# Sherko Pharma — Implementation Roadmap

Status: SP-000 through SP-013 and CI-001 are merged. The owner retired hosted CI in OPS-001 / Issue #42; CI-001 remains historical only. The owner deferred SP-014 on 2026-09-26 for later re-authorization. SP-015 completed the initial-delivery roadmap; SP-016 through SP-037 are merged. Follow-up Issues #88, #92 and #94 fixed owner-reported DDI compile/layout/provider-query regressions. Issue #96 is the current owner-authorized row-presentation and 18-component coverage regression task.

Repository: https://github.com/Sherko231/sherko_pharma
Current inspected baseline for Issue #96: `main` at `e556f20ce5b2d213b152fe97e0218e50e5a226e0` after merged Issue #94 / PR #95.

## Starting point

The repository contains a minimal Flutter Hello World application and Android/Windows platform scaffolds. It has no application features, tracked tests, agent documentation, or GitHub Actions workflows at the inspected revision. No open Issues or PRs were returned during inspection.

`pubspec.yaml` declares Dart `^3.10.7`, Flutter as its only runtime dependency, and version `0.1.0`. This is not an exact Flutter SDK pin. Riverpod, Supabase integration, and all agreed product features remain to be implemented.

Read `DEVELOPMENT_STATUS.md` for evidence and limitations. Refresh live state before starting; do not assume this baseline is still current.

## Execution contract

- Task IDs below are planning identifiers mapped to GitHub Issues where noted. A roadmap entry or downstream Issue is not authorization to begin it; use the owner's current explicit instruction and the active approved Issue.
- Work on one owner-approved, bounded Issue at a time, with explicit acceptance criteria, a dedicated branch, and a PR.
- Split a task into smaller Issues if its implementation cannot remain focused. Preserve the dependency order; a roadmap is not authorization to start every task.
- `QUALITY.md` lists optional local verification only; hosted CI is retired and is not a merge requirement.
- The owner may pull/test the merged revision on real hardware and report failures for a follow-up bounded task.
- After the current task is merged and the remote result is confirmed, report in Arabic and wait for "كمل".
- Keep the source CSV and credentials out of this public repository, commits, test fixtures, logs, and downloadable build artifacts. Use synthetic test data. Do not alter repository visibility as an incidental setup step.

## Phase 0 — Establish the project contract and checks

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-000 | Land the agreed documentation | Current state review | Root `AGENTS.md`; seven specifications/status/plan files under `docs/`; README index; consistent scope and relative links; reviewed docs-only PR |
| SP-001 | Establish reproducible hosted CI and merge gates | SP-000 | Compatible exact Flutter/toolchain choices documented; formatting and analysis checks; meaningful application-launch smoke test; Android and Windows builds on GitHub-hosted runners; current PR checks pass; required check names and commands documented; task/PR templates and separate review evidence; requirement-derived tests; branch protection/external-review integration configured or their specific setup blockers reported |
| SP-002 | Establish the minimal application structure | SP-001 | Riverpod wired into feature-level controllers/repositories; responsive navigation shell and explicit loading/error boundaries; no speculative empty layers or unapproved features |

SP-000/SP-001 describe the historical bootstrap. Their hosted-CI policy was superseded by OPS-001 / Issue #42. Current work does not require GitHub Actions or a required status check. Existing external repository protections must still be respected until the owner changes them in GitHub settings.

## Phase 1 — Establish the data and authorized server operations

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-003 | Complete source mapping and versioned schema | SP-001 | Reviewed mapping for every source column; stable product identity; original source preserved; two alternative barcode identifiers; explicit SYP initial import mapping; integer SYP/USD prices; revision-based concurrency; synthetic migration/constraint tests; decisions for source anomalies recorded |
| SP-004 | Implement owner authorization and bounded catalog API | SP-003 | Isolated backend tests prove anonymous/other-account denial and owner access; public signup disabled; read/search/mutation surfaces scoped; exact cross-field barcode lookup with distinct product results; version-checked writes; direct table access cannot bypass chosen API limits; no client admin keys |
| SP-005 | Build controlled CSV import | SP-003, SP-004 | Dry-run validation and row accounting; both barcodes preserved as text; all initial selling prices labelled SYP; invalid rows reported rather than silently dropped; repeat execution cannot overwrite later edits; tested on isolated data before an explicitly targeted initial deployment |
| SP-006 | Implement email/password sign-in and token handling | SP-002, SP-004 | Owner can sign in on Android and Windows; no registration UI; credentials/tokens handled with compatible platform storage; expired/signed-out state blocks protected UI and requests; sign-out does not act as a catalog save |

Select a dedicated Supabase environment and obtain only the configuration/access needed for its approved task. Existing project state, account provisioning, and deployed permissions have not been inspected. Resolve fundamental API design or paid-service choices with the owner before adopting them.

SP-003 must examine the actual corrected CSV during implementation; the roadmap does not invent mappings or silently assign meanings to source flags. An unresolved source-data rule can block import without blocking independently testable application work.

## Phase 2 — Catalog and manual order calculation

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-007 | Implement catalog search and product detail | SP-006, SP-004 | Server search by Arabic/English name and composition; bounded results; clear empty/error/loading states; older responses cannot replace newer searches; Arabic data readable on phone and desktop; detail layout reviewed against the approved fields |
| SP-008 | Implement product create/edit forms | SP-007 | All approved fields editable; one Arabic or English name sufficient; barcodes optional; valid whole-unit selling amount/currency required; server-confirmed saves; unsaved-navigation choices; clear conflict resolution; unrelated stored properties preserved |
| SP-009 | Implement persistent edit drafts | SP-008 | Unfinished input restored with original revision for the same account; no writes on startup/reconnect; explicit save/discard lifecycle; failed and uncertain saves retain recoverable input; local write failures reported |
| SP-010 | Implement manual customer-order calculator | SP-007 | Add from search; quantities/removal; one line per product; captured selling amount and currency; separate SYP/USD totals using exact arithmetic; invalid selling prices block addition; New Order confirmation; no sales history, stock, or currency conversion |
| SP-011 | Implement order/session persistence and account isolation | SP-009, SP-010 | Current page and order restored after restart; sign-out retains local order/draft while hiding them; only same-account sign-in restores them; confirmed reset stays cleared; late responses do not repopulate cleared/signed-out state; search/scroll restoration not required |
| SP-012 | Implement scoped automatic refresh and price-change handling | SP-008, SP-010, SP-011 | Relevant data refreshes while connected and after resume/reconnect; no full catalog replication; open/resumed orders preserve captured amount/currency until explicit update; edits from another device trigger refresh/conflict behavior; new orders use current server values |

After these tasks, an internal candidate can support catalog management and manual order calculation. It is not the full scanner-enabled release. No production source-data import or external release is implied by this milestone.

## Phase 3 — Barcode input on the target devices

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-013 | Add Android camera scanning | SP-010, SP-011, SP-012 | Real-camera scans resolve either barcode field; repeated frames do not increment quantity accidentally; deliberate repeat scans do; unknown/ambiguous/invalid-price cases follow the agreed rules; permission and interruption handling; owner device acceptance before merge |
| SP-014 | Add Windows external-reader integration (deferred) | Owner re-authorization; SP-010, SP-011, SP-012 plus selected hardware | Reader model/input protocol confirmed; complete barcode text and repeat-scan behavior preserved; focus, terminator, and reconnect behavior verified where applicable; owner test on the actual reader before merge |

The owner deferred SP-014 on 2026-09-26 and closed its current Issue as not planned for now. Do not assume USB keyboard emulation, universal Bluetooth support, or verified compatibility. Recreate/re-authorize the hardware task only when the owner wants to resume it and the device/input mode can be identified. SP-014 is not a prerequisite for SP-015.

## Phase 4 — Initial delivery

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-015 | Verify the current initial-delivery scope and prepare delivery | SP-013 and all non-deferred initial-delivery tasks; SP-014 is not required | Product acceptance checklist passes with recorded evidence for the current initial-delivery scope; Android and Windows application builds are tested as applicable; backend provisioning/import steps verified for the selected environment; unresolved issues and deferred SP-014 are reported; README setup and recovery instructions accurate; release identity/signing and artifact handling established before calling a build production-ready |

SP-015 replaced the placeholder Android identity and removed debug-key fallback from release builds. Before public distribution, REL-001 / Issue #40 amended the Android application ID/namespace to `com.samo.sherkopharma`. Production Android signing remains external to Git. Hosted CI is retired; release builds and packaging are owner-controlled and described in `RELEASE.md`.

## Phase 5 — Owner-authorized post-delivery refinements

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-016 | Improve Android barcode scan responsiveness and framing | SP-013 | Visible centered barcode guide matches the effective scan window; normal detection uses a 100 ms timeout; Android auto zoom and tap-to-focus are enabled; repeated-frame protection and authoritative server verification remain unchanged; owner checks responsiveness/framing on the real Android device |
| SP-017 | Optimize continuous Android barcode scanning | SP-016 | Compact inline Order-page scanner; no instructional tip; one owner-authorized barcode lookup per unique scan instead of lookup plus immediate detail read; camera remains open across distinct scans; same held presentation cannot repeatedly increment; owner checks real-device throughput and repeat behavior |
| SP-018 | Compact and recenter inline Android scanner UI | SP-017 | Overlay fills preview coordinates; centered smaller barcode guide; 112 px preview with minimal scanner chrome; compact phone Order header; scan behavior unchanged; owner checks real-device alignment |
| SP-019 | Add scanner visual feedback and success sound | SP-018 | White/amber/green/red guide states; dependency-free platform click only on successful add/increment; transient feedback returns to idle; lookup/order/repeat behavior unchanged; owner checks Android sound/visual feedback |
| SP-020 | Format amounts and refine Android scanner feedback | SP-019 | Shared comma-grouped whole-amount display/input normalization; Android auto zoom disabled; native beep plus light haptic only after successful add/increment; orientation-independent ML Kit scanning retained; owner checks sound/haptic and upside-down package scanning |
| SP-021 | Merge catalog search and order into compact Cart workspace | SP-020 | One visible Cart workspace; no Catalog/Order nav; embedded authoritative manual search plus Android Scan; bounded compact search results; responsive phone/desktop layout; legacy session destinations normalize to Cart; permanent compact-density/amount-format rules documented |
| SP-022 | Redesign Cart UX/UI as a professional POS workspace | SP-021 | Unified search/scan command surface; transient anchored search results; persistent item-count/SYP/USD summary; flat dense cart list; compact scanner status overlay; 420 px wide-window acquisition pane; research-backed POS/adaptive interaction rules documented |
| SP-023 | Add fast intelligent fuzzy catalog search | SP-022 | Unicode/Arabic normalization; weighted multi-token prefix/FTS + trigram typo matching; exact barcode/name priority; indexed candidate retrieval; hosted ranking/performance verification on the 23,750-row catalog; faster client debounce |
| SP-024 | Normalize product reference data and typed currency | SP-023 | Manufacturer/dosage-form reference tables + aliases/FKs; canonical server resolution; typed SYP/USD database enum; reference-aware form autocomplete; complex composition/strength/package fields deliberately remain text after data profiling |

SP-016 is tracked by Issue #44, SP-017 by Issue #46, SP-018 by Issue #48, SP-019 by Issue #50, SP-020 by Issue #52, SP-021 by Issue #54, SP-022 by Issue #56, SP-023 by Issue #58 and SP-024 by Issue #60; all are explicitly authorized by the owner. Neither reopens deferred SP-014 or authorizes unrelated roadmap work.

## Phase 6 — Conservative pharmaceutical normalization and alternatives

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-025 | Normalize composition into conservative ingredient identities | SP-024 | Raw composition remains unchanged; private ingredient registry + lexical aliases/spellings; product ingredient links; order-independent ingredient-set key; explicit auto/high-confidence/review/unresolved status; synchronization on future composition edits; focused regression coverage |
| SP-026 | Normalize ingredient strengths | SP-025 | Parse supported strength/unit expressions and pair each strength with the correct ingredient only when deterministic; preserve raw strength text; quarantine ambiguous combinations instead of guessing |
| SP-027 | Model pharmaceutical equivalence | SP-024, SP-025, SP-026 | Build a strict equivalence key from reviewed ingredient identities + paired strengths + compatible dosage form/route + release type; unverified/missing dimensions cannot be labeled strict alternatives |
| SP-028 | Add alternatives engine | SP-027 | Owner-authorized bounded API returns exact alternatives separately from same-ingredients/different-strength and same-ingredients/different-form groups; excludes unresolved normalization from strict substitution results |
| SP-029 | Add alternatives UI | SP-028 | Product/Cart UI exposes clearly separated alternative groups with brand/company/price/strength/form and order-add action without implying equivalence beyond the server classification |

SP-025 is merged via Issue #62 / PR #63, SP-026 via Issue #64 / PR #65, SP-027 via Issue #66 / PR #67, SP-028 via Issue #68 / PR #69, and SP-029 via Issue #70 / PR #71 at merge `c8919074247b950005ac9835779b2f7afdd62094`. None of these repository tasks deploys migrations 0009–0012 to production or authorizes broader medical synonym/therapeutic-equivalence curation.

## Phase 7 — Informational drug-interaction evidence

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-030 | Define the Interaction Checker DDI product and safety contract | SP-029 | Product/architecture/UX contract defines trusted-ingredient identity, severity semantics, transient/non-destructive behavior, privacy boundary, attribution/disclaimer/source requirements, provider limits, and release/licensing constraint without implementation |
| SP-031 | Expose trusted product ingredient inputs for DDI analysis | SP-030 | Bounded owner-authorized product-to-ingredient query exposes only trusted SP-025 identities/coverage state; private registry remains inaccessible; unresolved mappings are explicit |
| SP-032 | Add a typed Interaction Checker REST client | SP-030 | Injectable typed API client handles documented result/evidence/source fields, `major|moderate|minor|none|unknown`, unresolved items, timeout/error/malformed/429 states, and provider attribution/disclaimer without secrets |
| SP-033 | Build the Cart DDI analysis and batching engine | SP-031, SP-032 | Trusted ingredient queries aggregate back to product pairs; same-product-only pairs are excluded; >10 unique ingredients receive complete pair coverage; rate/coalescing/cache/stale-generation behavior is tested |
| SP-034 | Wire automatic DDI analysis into the Cart and scanner lifecycle | SP-033 | Distinct product-set changes trigger non-blocking analysis; quantity-only changes do not; failures do not break scanning/order; stale responses cannot repaint removed/reset/signed-out state |
| SP-035 | Visualize DDI severity directly in the Cart | SP-034 | Affected rows and Cart summary communicate severity with color plus accessible icon/text; `unknown`/partial/failure states never appear safe; order semantics remain unchanged |
| SP-036 | Add interaction detail sheet with evidence, sources, and attribution | SP-035 | Reusable detail surface shows product pair, causal ingredient pairs, evidence/source/effective date/link, attribution and disclaimer without treatment recommendations |
| SP-037 | Harden and accept the full Interaction Checker DDI integration | SP-030–SP-036 | End-to-end regression/real-device acceptance covers combinations, >10 ingredients, rapid scans, failure/rate-limit/stale/session cases and documents the current provider/release constraints |

SP-030 merged through Issue #72 / PR #80 at `50eda1567418b100f0561d604b40e85e2fa95d0a`. SP-031 merged through Issue #73 / PR #81 at `dbc0da03d4292c84255084beaf4f967ad2b898a1`. SP-032 merged through Issue #74 / PR #82 at `017f9a2c0cb3e958e2ad201cccb4277c0a482f04`. SP-033 merged through Issue #75 / PR #83 at `43d81ea419e0faaa66ac8d451779d31716920a4e`. SP-034 merged through Issue #76 / PR #84 at `285287ac2c0eb80396fd0cc5746210b8d648d9cd`. SP-035 merged through Issue #77 / PR #85 at `fa55cda1de0021676eb3864f135b052606727af5`. SP-036 merged through Issue #78 / PR #86 at `0358df317aab246dcd5d3d8a8c9b7cf5aa17a68f`. SP-037 merged through Issue #79 / PR #87 at `805a96202960d92219bcb3926c42e50c6f523f1a`. Follow-up Issue #88 / PR #89 fixed the reported Cart widget-list compile error at merge `a86ea668a0e8bcf85d80e83f72beec3b6c2a17d6`. Interaction Checker is an external provider: its API/terms must be re-checked before release. The September 2026 terms prohibit using the service to build or sell a clinical decision-support product, so no commercial/public DDI release is authorized without compatible permission or a replacement source/license.

## Explicitly deferred

SP-014 Windows external-reader integration is deferred from the current initial delivery but remains planned for later owner re-authorization. Patient-specific DDI risk scoring, treatment recommendations, automatic dose changes, interaction-driven substitution, and persistent medication/interaction history are outside SP-030–SP-037. Inventory, completed-sale history, fractional-package selling, fractional currency amounts, exchange rates/conversion, full Arabic UI localization, user-facing backup/export, a separate administration application, licensing, offline catalog operation, and queued offline catalog writes remain outside the current initial-delivery plan.

## Current task and next handoff

SP-000 merged via PR #2 at `5d1d9b94c1faa31bcc7667f44c4ee60bb6dc399b`. SP-001 merged via PR #4 at `05f2da264ba881648dbdf5eb560948a16ca150b7` with protected-main CI verified before and after merge.

SP-007 merged via PR #18 at `efd87540435624dcd8af52495f6675a1ff2cdb1f`. SP-008 merged via PR #20 at `e5fc0e9860628190e1cf0e78bcc8b67a62cea8b4`. SP-009 merged via PR #22 at `41bcc69edae80a8e8337d6920231e504d81a9e1a`. SP-010 merged via PR #24 at `7f9d6282a16fb30e4c61e3baf7300550c3b6f0e5` with post-merge CI verified. SP-011 merged via PR #26 at `594ad8b3958f64fa274c2debdf542364e589f6aa`; post-merge CI run `36150363815` passed. SP-012 merged via PR #28 at `334d61444f56d193897e713a6bd2b44deff7d975`; post-merge CI run `36235010740` passed. SP-013 merged via PR #30 at `2f00898ff7cdeb5060c215c6997c62fe5791bd26`; post-merge CI run `36250531971` passed after the owner accepted the real Android camera behavior on 2026-09-26. The owner deferred SP-014 on 2026-09-26; it does not block SP-015. SP-015 was tracked by Issue #38 as the final initial-delivery task. SP-016 through SP-029 are merged, with SP-029 merged through PR #71 at `c8919074247b950005ac9835779b2f7afdd62094`. SP-030 through SP-037 are merged, with SP-037 merged through PR #87 at `805a96202960d92219bcb3926c42e50c6f523f1a`. Follow-up compile fix Issue #88 / PR #89 is merged at `a86ea668a0e8bcf85d80e83f72beec3b6c2a17d6`. No next repository feature task is currently authorized. Production migration/deployment or a public/commercial DDI release remains a separate owner/release decision and is not authorized by completion of the roadmap task. See [development status](DEVELOPMENT_STATUS.md) and [delivery acceptance](DELIVERY_ACCEPTANCE.md) for evidence.
