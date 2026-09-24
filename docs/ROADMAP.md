# Sherko Pharma — Implementation Roadmap

Status: SP-000 through SP-004 and CI-001 are merged. The owner authorized SP-005 on 2026-09-24; implementation is tracked in Issue #13. Later feature tasks still require normal one-task-at-a-time authorization.

Repository: https://github.com/Sherko231/sherko_pharma
Inspected baseline: `main` at `2c5e0aa32a7b7ef246511cafff034adaf977d8b7`.

## Starting point

The repository contains a minimal Flutter Hello World application and Android/Windows platform scaffolds. It has no application features, tracked tests, agent documentation, or GitHub Actions workflows at the inspected revision. No open Issues or PRs were returned during inspection.

`pubspec.yaml` declares Dart `^3.10.7`, Flutter as its only runtime dependency, and version `0.1.0`. This is not an exact Flutter SDK pin. Riverpod, Supabase integration, and all agreed product features remain to be implemented.

Read `DEVELOPMENT_STATUS.md` for evidence and limitations. Refresh live state before starting; do not assume this baseline is still current.

## Execution contract

- Task IDs below are planning identifiers, not GitHub Issue numbers. SP-000 is tracked in [Issue #1](https://github.com/Sherko231/sherko_pharma/issues/1); SP-001 is tracked in [Issue #3](https://github.com/Sherko231/sherko_pharma/issues/3); later feature tasks do not yet have Issues.
- Work on one owner-approved, bounded Issue at a time, with explicit acceptance criteria, a dedicated branch, and a PR.
- Split a task into smaller Issues if its implementation cannot remain focused. Preserve the dependency order; a roadmap is not authorization to start every task.
- Apply `QUALITY.md` gates to the current revision. Camera/reader behavior changes require the owner's real-device acceptance before merge.
- After the current task is merged and its required follow-up checks are verified, report in Arabic and wait for "كمل".
- Keep the source CSV and credentials out of this public repository, commits, test fixtures, logs, and downloadable build artifacts. Use synthetic test data. Do not alter repository visibility as an incidental setup step.

## Phase 0 — Establish the project contract and checks

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-000 | Land the agreed documentation | Current state review | Root `AGENTS.md`; seven specifications/status/plan files under `docs/`; README index; consistent scope and relative links; reviewed docs-only PR |
| SP-001 | Establish reproducible hosted CI and merge gates | SP-000 | Compatible exact Flutter/toolchain choices documented; formatting and analysis checks; meaningful application-launch smoke test; Android and Windows builds on GitHub-hosted runners; current PR checks pass; required check names and commands documented; task/PR templates and separate review evidence; requirement-derived tests; branch protection/external-review integration configured or their specific setup blockers reported |
| SP-002 | Establish the minimal application structure | SP-001 | Riverpod wired into feature-level controllers/repositories; responsive navigation shell and explicit loading/error boundaries; no speculative empty layers or unapproved features |

SP-000 is a documentation-only bootstrap task: it uses the lighter documentation gates already agreed in `QUALITY.md`, not nonexistent application workflows. SP-001 must demonstrate its own workflows on its PR. Do not enable routine unattended code merges before the required checks and repository protections are established.

The repository's native GitHub auto-merge flag is currently off. This is distinct from the owner's authorization for an agent to merge after verifying all gates; either implementation must obey protections and the same acceptance policy. Do not bypass a required gate to get the bootstrap merged.

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
| SP-014 | Add Windows external-reader integration | SP-010, SP-011, SP-012 plus selected hardware | Reader model/input protocol confirmed; complete barcode text and repeat-scan behavior preserved; focus, terminator, and reconnect behavior verified where applicable; owner test on the actual reader before merge |

The owner has not purchased the Windows reader. Do not assume USB keyboard emulation, universal Bluetooth support, or verified compatibility. Leave the hardware task blocked until the device is selected. Android and unrelated tasks need not wait for purchasing that reader.

## Phase 4 — Initial delivery

| ID | Task | Depends on | Completion evidence |
| --- | --- | --- | --- |
| SP-015 | Verify the complete initial scope and prepare delivery | All required feature tasks, including hardware acceptance | Product acceptance checklist passes with recorded evidence; target device builds tested; backend provisioning/import steps verified for the selected environment; unresolved issues reported; README setup and recovery instructions accurate; release identity/signing and artifact handling established before calling a build production-ready |

The current Android application ID/namespace is `com.example.sherko_pharma`, and its release build is configured to use debug signing. Decide and configure final app identity and release signing before commercial distribution; a successful current build is not evidence of production release readiness.

## Explicitly deferred

Inventory, completed-sale history, fractional-package selling, fractional currency amounts, exchange rates/conversion, full Arabic UI localization, user-facing backup/export, a separate administration application, licensing, offline catalog operation, and queued offline catalog writes remain outside this plan.

## Current task and next handoff

SP-000 merged via PR #2 at `5d1d9b94c1faa31bcc7667f44c4ee60bb6dc399b`. SP-001 merged via PR #4 at `05f2da264ba881648dbdf5eb560948a16ca150b7` with protected-main CI verified before and after merge.

SP-004 merged via PR #12 at `7b3c0b0e8870a4ddd8bb4a5f107b3e491ed315b4`; its post-merge CI passed. SP-005 is the active approved task in [Issue #13](https://github.com/Sherko231/sherko_pharma/issues/13): build the fingerprinted dry-run/import workflow, prove idempotent reruns on isolated data, and keep the real source undeployed until a dedicated environment is explicitly targeted. See [development status](DEVELOPMENT_STATUS.md) for live evidence.
