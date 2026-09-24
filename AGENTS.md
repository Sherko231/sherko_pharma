# Agent Working Agreement — Sherko Pharma

## Authority and language

Follow higher-priority instructions and the owner's explicit directions. Implement only an approved task; roadmap entries are not authorization. Never claim unavailable access, unexecuted checks, or unverified results.

Write code, tests and technical docs in English; report in Arabic. Preserve Arabic product data. The current product is defined in [PRODUCT.md](docs/PRODUCT.md); do not infer requirements from older chat proposals.

## Start from live evidence

1. Read this file and applicable directory-specific instructions.
2. Read [README.md](README.md), then [PRODUCT.md](docs/PRODUCT.md).
3. Read [DEVELOPMENT_STATUS.md](docs/DEVELOPMENT_STATUS.md), the active approved Issue, and the relevant [ROADMAP.md](docs/ROADMAP.md) entry.
4. Read affected sections of [ARCHITECTURE.md](docs/ARCHITECTURE.md), [QUALITY.md](docs/QUALITY.md), feature specs and decision records. Avoid loading unrelated detail.
5. Inspect the checkout branch, status, SHA, refreshed remote default branch, active Issue and related open PRs. Preserve unrelated/uncommitted work.
6. Compare live evidence with documentation. Resolve or report material conflicts before implementing the affected area. Report missing access or required prerequisites; do not invent them.

Start each bounded task from these repository records, even in a fresh conversation. Record decisions and handoff evidence in the repository/Issue/PR, not only in chat.

## One bounded task per cycle

- Use the task template: goal, context, constraints, non-goals, concrete acceptance examples and applicable verification gates. For complex work, write a short plan in the Issue/PR.
- Define expected results from requirements before implementation. Resolve behavioral/data ambiguities with the owner; make routine reversible implementation decisions autonomously.
- Use a dedicated branch and PR. Never push implementation directly to the configured default branch.
- Reuse existing patterns. Do not bundle unrelated refactors, dependency upgrades or future features. Record unrelated findings separately; explain blockers before expanding scope.
- Ask before changing agreed behavior or fundamental architecture, or introducing paid services. Do not re-request existing authorization.
- Add dependencies only for a concrete need, verify pinned-toolchain/platform compatibility and record material tradeoffs. Use the [decision template](docs/decisions/TEMPLATE.md) for significant choices, not routine edits.

## Verification and separate review

[QUALITY.md](docs/QUALITY.md) owns commands, mandatory gates, test strategy and exceptions. Run targeted checks during development, then the complete applicable gates on the current revision before merge. Never weaken assertions, analysis or gates just to obtain a pass.

For reproducible bugs, demonstrate the regression test failing for the original defect before applying the fix, then passing afterward. For high-risk new logic, establish requirement-derived cases before implementation. Tests must check observable behavior, relevant failures and persistence, not simply reproduce the code's own assumptions.

After implementation, perform a separate review pass against the Issue, complete diff and test evidence. Record reviewed SHA, reviewer/session, findings and resolutions in the PR. Prefer a separate reviewer context when available; explicitly label self-review if that is the available mechanism. A self-review is not an independent approval. An unavailable external reviewer must be disclosed, not fabricated.

## Code Review Rules

- Protect catalog/session integrity: no silent overwrite, unconfirmed-save success, restored-draft upload or cross-account session exposure. Check relevant failure and retry paths against the owning specs.
- Verify exact barcode identity and captured integer price/currency semantics; expected tests must come from requirements. Mocks alone cannot establish real server authorization or durability.
- Inspect changes to tests, workflows and permissions as carefully as application code. Flag weakened gates or newly exposed production data.
- Keep Flutter UI code conventionally readable, including multiline widget trees when that improves clarity. This repository does not enforce `dart format` in CI; review formatting only when it materially harms readability or consistency.

## Data and access boundaries

Never commit credentials, privileged keys, the source CSV, production dumps or sensitive request payloads, including in logs and artifacts. Use synthetic fixtures and isolated test environments. Do not perform destructive production operations incidentally. Product and architecture docs own online-only catalog access, owner authorization and deferred features.

## Merge authorization

Automatic merge of the current task remains authorized only when:

1. Approved scope/acceptance criteria are satisfied with no unresolved conflicts or blocking findings.
2. All applicable QUALITY.md gates pass for the latest relevant revision, including required owner acceptance for hardware or sensitive changes.
3. GitHub reports merge eligibility and effective repository protections/required checks are satisfied.
4. The separate review pass and accurate evidence are recorded. Material later changes receive renewed affected checks/review.

Never bypass protections, approvals or access controls. Missing, failed, cancelled or unjustifiably skipped gates are blockers. Report unavailable enforcement explicitly; do not claim routine automatic code merges are protected before repository setup is verified.

After merge, verify the remote result and required post-merge CI. Report pending/failed states honestly and fix in-scope failures where possible. Update docs in reviewed PRs; record the eventual merge SHA in the handoff or next reviewed status update rather than inventing a self-referential SHA.

## Handoff and maintenance

Report what changed, actual checks and limitations, Issue/PR/commit and merge state, and the next proposed task. Stop after this task; wait for "كمل" or another explicit instruction.

Keep instructions concise and give each fact one owning document. Link to detailed rules instead of copying them. Add a specific rule or regression test after an observed recurring failure. Do not accumulate speculative bureaucracy or treat more instructions as proof of accuracy.
