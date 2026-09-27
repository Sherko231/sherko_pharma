# Agent Working Agreement — Sherko Pharma

## Authority and language

Follow higher-priority instructions and the owner's explicit directions. Implement only an approved task; roadmap entries are not authorization. Never claim unavailable access, unexecuted checks, or unverified results.

Write code, tests and technical docs in English; report in Arabic. Preserve Arabic product data. The current product is defined in [PRODUCT.md](docs/PRODUCT.md).

## Start from live evidence

1. Read this file and applicable directory-specific instructions.
2. Read [README.md](README.md), then [PRODUCT.md](docs/PRODUCT.md).
3. Read [DEVELOPMENT_STATUS.md](docs/DEVELOPMENT_STATUS.md), the active approved Issue, and the relevant [ROADMAP.md](docs/ROADMAP.md) entry.
4. Read affected sections of [ARCHITECTURE.md](docs/ARCHITECTURE.md), [QUALITY.md](docs/QUALITY.md), feature specs and decision records.
5. Inspect the current branch/status/SHA, refreshed remote default branch, active Issue and related PRs. Preserve unrelated work.
6. Compare live code, Git history and documentation. Resolve or report material conflicts before changing the affected area.

Record important decisions and handoff evidence in the repository/Issue/PR rather than only in chat.

## One bounded task per cycle

- Use one approved Issue, one focused branch and one PR.
- Define the goal, constraints, non-goals and concrete acceptance examples before implementation.
- Do not push implementation directly to the configured default branch.
- Reuse existing patterns and avoid unrelated refactors, dependency upgrades or future features.
- Ask before changing agreed behavior, fundamental architecture, production data, access controls or paid services.
- Never commit credentials, privileged keys, the source CSV, production dumps or sensitive logs.

## Verification policy

GitHub Actions CI is intentionally not used for this repository. There is no automated required-status gate and no post-merge CI requirement.

[QUALITY.md](docs/QUALITY.md) lists local verification commands that remain available as optional tools. Run targeted local checks when they are useful or when the owner explicitly requests them, but an unrun local command is not by itself a merge blocker.

The owner may pull the merged revision and test it on the real Windows/Android environment. If the owner reports a problem, create a bounded fix task and reproduce it where practical. Hardware/device behavior is ultimately confirmed by the owner's real-device testing.

For reproducible bugs, add or use a focused regression test when practical. Tests should check observable behavior and meaningful failure paths, not merely reproduce implementation assumptions.

## Review

After implementation, perform a separate diff review against the Issue and current requirements. Record the reviewed revision, findings, resolutions and limitations in the PR. Label self-review honestly when no independent reviewer is available.

Protect catalog/session integrity, exact barcode identity, captured integer price/currency semantics, server-confirmed writes, conflict handling, account isolation and no automatic draft upload wherever the task touches them.

## Merge authorization

The task may be merged when:

1. The approved scope and acceptance criteria are satisfied.
2. The final diff has no known blocking conflict or unresolved review finding.
3. Any owner approval explicitly required for a destructive production action or fundamental security/access change has been obtained.
4. GitHub reports the PR as mergeable under the repository's effective settings.

Do not invent required checks or wait for GitHub Actions runs. Do not bypass an external repository protection that still exists; report that settings blocker accurately.

After merge, verify the remote merge result/SHA. There is no post-merge CI requirement.

## Handoff

Report what changed, any checks actually run, Issue/PR/commit and merge state, limitations, and the next proposed task. Stop after this task and wait for "كمل" or another explicit instruction.
