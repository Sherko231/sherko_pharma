# Sherko Pharma — Quality and Merge Gates

Status: Agreed verification policy. CI workflows, runnable project commands, and repository protections have not yet been configured or verified.

## Purpose

Define the evidence required before merging a bounded task. `AGENTS.md` owns task execution and authorization; `PRODUCT.md` owns behavior; `ARCHITECTURE.md` owns technical boundaries.

Passing checks provide evidence for the behavior they exercise. They do not establish universal correctness or replace required device testing.

## Execution environment

- Run CI on GitHub-hosted runners. Do not depend on the owner's computer or configure a self-hosted runner without a later explicit decision.
- Build Android and Windows on appropriate hosted environments. Pin the project's toolchain and use reproducible dependency resolution; select concrete versions during repository setup.
- Monitor CI usage. Do not enable paid usage or bypass quality gates to save minutes without the owner's decision.
- Cancel superseded runs where safe and avoid redundant jobs. A cancelled run does not count as passing validation for the current revision.
- Keep test data synthetic and environments isolated. Automated tests must not modify the live catalog or use the owner's production credentials.

## Required pre-merge gates

| Change | Required evidence |
| --- | --- |
| Application code, dependencies, assets affecting builds, or platform configuration | Formatting check, static analysis, established automated regression suite, meaningful tests for changed behavior, successful Android build, successful Windows build, and diff review |
| Backend schema, authorization, or API behavior | Relevant isolated database/API tests, permission tests, migration validation, affected application checks, and diff review |
| Camera scanning or external-reader behavior, including scanner dependency/input-adapter changes | Applicable automated gates plus explicit owner acceptance after testing the affected behavior on the actual device |
| Documentation only | Diff review, requirement consistency, and applicable documentation/link checks; application builds and tests are not required when executable behavior is unaffected |
| CI or verification configuration | Review the gate changes and demonstrate affected workflows on the PR; do not classify workflow scripts as documentation |

Apply the union of relevant rows for mixed changes. Explain the selected gates in the PR. Do not classify behavior changes as documentation to obtain exemptions.

Define exact commands, workflow names, runner/toolchain versions, and required status checks during the initial CI task. Keep commands in the repository and its setup documentation synchronized. A missing required workflow is a blocker, not a passing result. No fixed coverage percentage has been agreed; prioritize assertions that detect meaningful regressions.

## Behavior to protect as features are implemented

Add tests with the implementing task rather than creating empty passing tests in advance. Include the relevant failure paths, using expected results derived from requirements.

- Barcode identifiers: preserve leading zeros and complete text; match either `barcode` or `barcode2`; deduplicate matches within one product; ignore empty identifiers; detect ambiguity across distinct products in either field without preferring the primary field. Never silently choose among multiple products.
- Scanning and orders: deliberate repeat scans increase the correct line quantity; repeated camera frames do not count as deliberate scans; quantity edits, removal, and exact totals behave correctly.
- Prices: an open order retains its captured amount and currency when either changes on the server; the owner can explicitly accept a valid pair; a new order uses current prices.
- Currency totals: mixed SYP/USD orders produce separate integer totals, without conversion or addition across currencies. Cover quantity changes, removal, accepted currency changes, and restoration of captured currencies after restart.
- Product validation: missing/zero selling prices block order addition; reject negative/fractional input and missing/unsupported currencies. Accept Arabic-only or English-only names; reject both names empty or whitespace-only on creation/edit. New products require a positive integer price with currency, while barcodes remain optional.
- Catalog editing: verify persistence of every approved editable field under the confirmed-save/conflict rules and ensure editing selected fields preserves unrelated stored properties.
- Server writes: show success only after confirmed persistence; failures retain unsaved form input without adding an offline mutation queue; uncertain retries do not create duplicate products.
- Concurrent edits: reject stale revisions atomically and let the owner choose how to resolve the conflict; do not overwrite a newer change silently.
- Sessions: restore the active order and relevant location after restart; preserve quantities and captured prices; handle malformed snapshots and interrupted writes explicitly.
- Sign-out: retain the order/draft locally, hide protected content immediately, and restore only for the same authenticated account. Verify account isolation, no automatic draft upload, and late responses not revealing data after sign-out. Exact search/scroll/filter restoration is not a required gate.
- New order: cancelling confirmation preserves all lines/totals; confirming clears and persists the empty active order without history. Cover persistence failure and late lookup responses from the previous order.
- Unsaved edits: navigation offers Save / Discard Changes / Stay; discard does not revert prior confirmed server values, stay retains input, and save leaves the screen only after confirmed success. Failure or conflict must retain input and expose the problem.
- Draft restoration: terminate/reopen after persisting an unfinished edit and recover its input for the same owner. Startup/reconnect/restore must make no catalog mutations; explicit Save must validate against the original revision. Cover server changes while closed, failed local writes, uncertain prior save outcomes, and clearing after confirmed save/discard without stale-write resurrection.
- Connectivity: distinguish network errors from empty results, preserve the current order, and refresh relevant data on reconnection without copying the full catalog locally.
- Authorization: verify server denial for anonymous and unauthorized accounts as well as authorized owner access; hiding buttons is insufficient evidence.
- Data import: validate the agreed CSV mapping, assign SYP explicitly to the initial source's selling prices without conversion, preserve both barcode fields and source identifiers, report invalid rows, and prevent accidental replacement of later owner edits.
- UI: exercise important loading, empty, error, and success states at representative phone and desktop sizes; Arabic product text must remain readable in the English UI.

Use unit tests for independent logic, widget tests for relevant UI state and actions, and integration tests for boundaries whose correctness cannot be demonstrated in isolation. Mocked repositories alone cannot prove actual server authorization or persistence.

## Hardware acceptance exception

The owner has explicitly approved this exception to automatic merge:

1. Complete the implementation, automated checks, and diff review first.
2. Provide a runnable candidate for the affected platform, identify the exact tested revision, and supply a short device checklist with expected outcomes.
3. Wait for the owner's actual device test and explicit acceptance before merging a PR that changes camera or external-reader behavior.
4. If a later change affects the manually tested behavior, repeat the affected test. Explain unrelated changes when prior device evidence remains applicable.

For Android, cover scan recognition, deliberate repeated scans, camera permissions, and relevant interruption/resume behavior. For Windows, record the selected reader model, connection/input mode, and barcode terminator configuration where applicable; test complete scans, repeats, focus handling, and relevant reconnection behavior.

The owner has not purchased the Windows reader. Hardware compatibility remains unverified until selection and testing. Such PRs remain unmerged while required hardware acceptance is unavailable; the agent may continue only within its current approved scope and must report the blocker. Independent non-hardware tasks can be selected by the owner.

A screenshot, simulated barcode input, successful build, or emulator test does not substitute for the required physical-device acceptance. Do not request manual hardware testing for unrelated changes.

## Review, automatic merge, and completion

- Review the full diff for correctness, requirements, accidental data loss, sensitive data, scope, and missing verification.
- Automatic merge remains authorized when all applicable gates pass for the latest relevant revision, required manual acceptance is recorded, there are no blocking review findings, and repository protections permit the merge.
- Never weaken checks, remove assertions, or treat skipped/failing jobs as successful to obtain a merge. Investigate flaky failures and record any concrete resolution.
- Before merging, verify checks and acceptance against the current PR state. Resolve new conflicts and rerun affected checks after material changes.
- Verify the actual merge and any required post-merge workflows. Report a post-merge failure or pending state accurately; fix failures within the approved task when possible.
- Report in Arabic what changed, what was verified, actual merge status, and limitations. Stop after the task and wait for "كمل".

## Setup work still required

- Inspect the actual Flutter project and select compatible pinned tooling.
- Implement hosted CI and document runnable commands and required check names.
- Verify repository protections and merge capabilities without bypassing any access control.
- Establish isolated backend tests and synthetic fixtures as backend work begins.
- Decide test-build artifact handling and retention without enabling paid services implicitly.

This file records the agreed policy. It does not claim that workflows exist, checks have passed, or any repository changes have been merged.
