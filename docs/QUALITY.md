# Sherko Pharma — Quality and Merge Gates

Status: SP-001 supplies executable hosted CI and shared commands. Read DEVELOPMENT_STATUS.md and the live PR for observed results and outstanding settings; configuration in Git does not itself enable branch protection or external code review.

## Purpose

Define the evidence required before merging a bounded task. `AGENTS.md` owns task execution and authorization; `PRODUCT.md` owns behavior; `ARCHITECTURE.md` owns technical boundaries.

Passing checks provide evidence for the behavior they exercise. They do not establish universal correctness or replace required device testing.

## Execution environment

- Run CI on GitHub-hosted runners. Do not depend on the owner's computer or configure a self-hosted runner without a later explicit decision.
- Use the pinned setup and commands below. Keep the application lockfile committed and review toolchain/dependency changes explicitly.
- Monitor CI usage. Do not enable paid usage or bypass quality gates to save minutes without the owner's decision.
- Cancel superseded runs where safe and avoid redundant jobs. A cancelled run does not count as passing validation for the current revision.
- Keep test data synthetic and environments isolated. Automated tests must not modify the live catalog or use the owner's production credentials.

## Required pre-merge gates

| Change | Required evidence |
| --- | --- |
| Application code, dependencies, assets affecting builds, or platform configuration | Static analysis, established automated regression suite, meaningful tests for changed behavior, successful Android build, successful Windows build, and diff review |
| Backend schema, authorization, or API behavior | Relevant isolated database/API tests, permission tests, migration validation, affected application checks, and diff review |
| Camera scanning or external-reader behavior, including scanner dependency/input-adapter changes | Applicable automated gates plus explicit owner acceptance after testing the affected behavior on the actual device |
| Documentation only | Diff review, requirement consistency, and applicable documentation/link checks; application builds and tests are not required when executable behavior is unaffected |
| CI or verification configuration | Review the gate changes and demonstrate affected workflows on the PR; do not classify workflow scripts as documentation |

Apply the union of relevant rows for mixed changes. Explain the selected gates in the PR. Do not classify behavior changes as documentation to obtain exemptions.

Use the exact commands and required check below; keep setup and CI synchronized. A missing required workflow is a blocker, not a passing result. No fixed coverage percentage has been agreed; prioritize assertions that detect meaningful regressions.

## Executable checks and feedback loop

Use Python 3.11+ locally (`python` on Windows, `python3` where required). CI pins Python 3.12.9. Install the exact Flutter SDK in `.flutter-version` and put its `bin` directory on PATH. Android CI uses Temurin 17.0.18+8 and the repository's existing Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 pins. Flutter supplies its matching Dart and Android SDK/NDK defaults. Runner images are `ubuntu-24.04` and `windows-2022`; hosted image contents receive upstream updates and are not bit-for-bit pinned.

| Command | Purpose |
| --- | --- |
| `python tool/verify.py docs` | Check repository-relative inline Markdown file links; semantic consistency remains a review responsibility |
| `python -m unittest discover -s tool -p 'test_*.py' -v` | Ensure scope classification and aggregation reject missing/failing gates |
| `python tool/verify.py quick` | Verify exact Flutter, enforce unchanged lockfile, analyze and run the full Flutter test suite; it intentionally does not enforce `dart format` |
| `python tool/verify.py quick --test test/app_smoke_test.dart` | Targeted development feedback; never a replacement for the full pre-merge suite |
| `python tool/verify.py android` | Enforce dependencies and build a debug APK; requires Android SDK/JDK |
| `python tool/verify.py windows` | Enforce dependencies and build Windows release binaries; requires Windows and Visual Studio C++ desktop tooling |

Every subprocess failure makes the command fail. Resolve dependencies explicitly outside verification when intentionally updating `pubspec.lock`; review the resulting diff. Do not make CI run `pub upgrade` or silently regenerate an incompatible lockfile.

`.github/workflows/ci.yml` runs on PRs to `main`, pushes to `main`, and manual dispatch. Fast quality checks precede the two platform builds. Flutter/Gradle caches reduce repeated downloads. Only superseded PR runs are cancelled; a main push is always fully verified. No paid runner or external review service is enabled by this configuration.

PRs changing only `README.md`, `AGENTS.md`, `.github/pull_request_template.md`, or Markdown under `docs/` use documentation checks and verification-tool tests. All unknown paths, workflows, tool scripts, package files, platform changes and mixed changes use full gates. There is no workflow-wide path filter that leaves a required status permanently pending. Deleted/renamed code is not exempt merely because the destination looks like documentation.

The single required status is **`Required verification`**, produced by the CI workflow. It runs even after dependency failures and checks exact job results. On full runs, `Quality`, `Android build` and `Windows build` must all succeed. Only the documented docs classification permits skipped platform builds. Tests cover the aggregator's failure/cancellation/missing-result paths. Human/AI diff review and device acceptance are additional gates, not proven by this status.

Builds are verification candidates, not commercial releases. Android currently uses debug signing; no artifacts are automatically published or retained by this task. Artifact distribution/retention and release signing are decided with the delivery task.

## Requirement-derived testing

Put concrete inputs/actions and expected results in the Issue before coding. For a reproducible bug, run a test that fails for the defect first, then pass it with the fix; if reproduction is unavailable, state that limitation. For important new calculation, persistence or permission logic, define examples independently of the implementation. Use many focused unit/widget tests and enough integration tests for real boundaries; avoid a blanket coverage percentage or tests for every trivial documentation edit.

Use synthetic data, including leading-zero barcodes, two alternative codes for one item, mixed currencies, conflicting revisions and interruption cases as their features land. Do not add fake passing tests for unimplemented features. The initial launch test is a small example of real executable evidence, not a catalog or hardware acceptance test.

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

## Sensitive-change acceptance exception

The owner approved this exception on 2026-09-24. Before merging changes that delete/irreversibly transform production data, broaden catalog access or weaken authorization, or reduce required tests/analysis/merge protections:

1. Finish the in-scope implementation, applicable checks and separate review first.
2. Present the exact revision, consequences, recovery plan where relevant, and why the change is needed.
3. Obtain the owner's explicit acceptance of that concrete result. Initial task authorization alone is not acceptance of a subsequently weakened safeguard.

Routine stronger checks, additive tests and non-destructive isolated fixtures do not require this exception. Changing a test expectation to match an explicitly approved product requirement must be explained and reviewed; deleting assertions to hide a defect is forbidden. This is an agent/review policy, not an automated semantic risk detector. It does not authorize executing destructive production operations.

## Review, automatic merge, and completion

- Perform the separate review pass defined in AGENTS.md. Record the reviewed SHA, acceptance coverage, findings and resolutions, reviewer/session and any independence limitation in the PR template. Recheck affected areas after subsequent edits.
- Automatic merge remains authorized when all applicable gates pass for the latest relevant revision, required manual acceptance is recorded, there are no blocking review findings, and repository protections permit the merge.
- Never weaken checks, remove assertions, or treat skipped/failing jobs as successful to obtain a merge. Investigate flaky failures and record any concrete resolution.
- Before merging, verify checks and acceptance against the current PR state. Resolve new conflicts and rerun affected checks after material changes.
- Verify the actual merge and any required post-merge workflows. Report a post-merge failure or pending state accurately; fix failures within the approved task when possible.
- Report in Arabic what changed, what was verified, actual merge status, and limitations. Stop after the task and wait for "كمل".

## Repository settings and external review

After CI has reported its check, configure `main` branch protection (or an equivalent active ruleset): require a PR, require `Required verification` from GitHub Actions, require the branch to be up to date, resolve review conversations, block force pushes/deletions, and apply checks without administrator bypass. Do not require an ordinary approving review until an eligible separate reviewer is available: a PR author cannot approve their own PR. Verify effective settings by readback and record their actual state in DEVELOPMENT_STATUS.md. Native GitHub auto-merge is optional; agent-controlled merge must obey the same gates.

Full check success is not enough if the PR weakens the workflow that defines that check. Review the entire gate/test/configuration diff, and apply the sensitive-change exception. Repository rules and review policy complement each other.

For an additional Codex review pass, connect this repository to Codex cloud and enable Code review / Automatic reviews in Codex settings when available under the owner's existing access. Confirm a review on the actual PR; do not equate an enabled toggle, emoji, pending request or silence with a completed review. Ensure new material revisions are reviewed again. AGENTS.md owns the domain-specific review rules. Do not introduce paid usage or request new broad account access silently.

External integration status must be recorded separately from the mandatory separate review pass. A disclosed self-review is the fallback when external review is unavailable; it is not an independent GitHub approval. Account setup requiring the owner remains an explicit handoff, not a fabricated success.

Backend isolation/permission tests must be established with backend tasks. Camera/reader acceptance and production release configuration remain deferred to their implementing tasks.
