# Agent Working Agreement — Sherko Pharma

## Purpose and authority

This file governs coding-agent work in the `sherko_pharma` repository. The current assistant is ChatGPT; access to repository editing, command execution, and GitHub operations depends on the active environment. Never claim access or actions that were not available or performed.

Follow applicable higher-priority instructions and the owner's explicit directions. Implement the agreed product scope in `docs/PRODUCT.md`. A future roadmap idea is not authorization to implement it.

Write code, identifiers, tests, and technical documentation in English. Report progress, findings, questions, and completion to the owner in Arabic. Preserve Arabic product data and support its readable display.

## Start each task from live evidence

1. Read this file and any applicable directory-specific agent instructions.
2. Read `README.md` for setup and commands, then `docs/PRODUCT.md` for product scope.
3. Read `docs/DEVELOPMENT_STATUS.md` and the active approved task/Issue. Consult `docs/ROADMAP.md` for sequence and dependencies.
4. Read relevant sections of `docs/ARCHITECTURE.md`, `docs/QUALITY.md`, feature specifications, and decision records before changing the affected area.
5. Inspect the working directory, current branch, uncommitted changes, and commit SHA. Refresh and inspect the remote default branch, active Issue, and related open pull requests when access is available.
6. Compare documentation with the actual code and GitHub state. Resolve or report material conflicts before implementing the affected part. Do not silently choose between conflicting requirements.

Some referenced documents may not exist during initial setup. Report missing prerequisites and do not invent their contents. Missing optional documentation need not stop unrelated work; missing requirements or verification gates needed for the current task must be resolved before declaring completion.

Use the configured remote default branch; do not assume its name. Preserve unrelated work and never overwrite uncommitted changes to make a task easier.

## One bounded task per cycle

- Work on one approved, bounded task/Issue at a time.
- Confirm its goal, scope, acceptance criteria, and relevant constraints before implementation. For complex work, form a short implementation plan.
- Use a dedicated branch and a pull request. Do not commit or push implementation changes directly to the default branch.
- Inspect existing code and reuse established patterns before introducing new components.
- Keep changes within scope. Do not combine unrelated refactoring, dependency upgrades, or future features with the task.
- Record unrelated problems in separate Issues when authorized repository access is available; otherwise include a separate backlog entry in the report. Do not fix them as hidden scope additions.
- If an unrelated problem blocks the active task, explain the blocker and proposed resolution before expanding scope.

## Autonomous decisions and questions

Proceed autonomously with routine implementation details, reversible fixes, and verification within the approved task.

Ask the owner before changing agreed product behavior, changing the fundamental architecture, or introducing a paid service. Ask about unresolved ambiguity that materially changes user behavior or data semantics. Do not repeatedly request approval for decisions the owner has already authorized.

Use dependencies only for a clear need, check compatibility with the project's pinned toolchain and target platforms, and document meaningful tradeoffs. Do not add speculative abstractions for unapproved future features.

## Product constraints to preserve

`docs/PRODUCT.md` owns product requirements. In particular, protect server-persisted catalog edits and saved customer sessions. Do not reimport source data over user changes. Treat barcodes as identifiers, not numeric quantities. Never invent missing product data or silently select a product for an ambiguous barcode.

The current scope is an online Supabase catalog and order calculator on Android and Windows, with owner-only email/password access and server-enforced permissions. Do not ship a full local catalog or add offline catalog-write queues. Preserve captured prices in open orders and require explicit acceptance of price updates. A separate administration app, offline operation, licensing, and other deferred features require a later approved task.

## Verification and review

- Use the runnable commands and mandatory gates defined in `docs/QUALITY.md` and the repository's CI configuration.
- Run CI on GitHub-hosted runners. Programming changes require formatting, analysis, relevant automated verification, and successful Android and Windows builds as defined in `docs/QUALITY.md`; documentation-only changes use the documented lighter gates.
- Changes to camera scanning or external barcode-reader behavior require the owner's explicit acceptance after an actual device test before merge. Prepare the tested candidate and checklist first; simulated input and successful builds do not replace hardware acceptance.
- Verify relevant behavior, failure cases, persistence, and platform-specific changes. Add or adjust meaningful tests when needed; tests must check requirements, not merely repeat implementation details.
- Do not delete or weaken tests, disable analysis rules, suppress failures, or modify gates solely to obtain a passing result.
- Review the complete diff before merging for correctness, unintended changes, data loss, scope violations, and missing verification.
- A successful build alone does not prove functional correctness. A CI check that is pending, cancelled, skipped without an applicable documented exemption, or failing does not satisfy a mandatory gate.
- Report exactly what ran, what passed, what failed, and what could not be tested. Never report planned commands as executed or old results as validation of new changes.
- Do not commit credentials or expose secrets in logs or reports. Do not perform destructive production-data operations as an incidental development step.

## Automatic merge authorization

The owner authorizes automatic merging of the current task's pull request without another permission request when all of the following are true:

1. The change satisfies the approved scope and acceptance criteria.
2. Required tests and all other mandatory quality gates have passed for the latest relevant revision; a subsequent change requires renewed affected verification.
3. Diff review has no unresolved blocking findings or material requirement conflicts.
4. GitHub reports the pull request as mergeable and all applicable repository requirements are satisfied.
5. Any required owner hardware acceptance under `docs/QUALITY.md` is recorded for the affected behavior and remains applicable to the latest revision.

Do not bypass branch protections, required reviews, checks, or higher-priority access controls. If a required gate or capability is unavailable, report the exact blocker instead of claiming completion or treating the gate as passed.

After merging, confirm the actual remote result, record the PR and merged commit, and check any required post-merge workflow. Do not call a required pending workflow successful. Update affected documentation as part of the task's normal reviewed changes; do not use documentation updates as a reason for direct default-branch pushes.

## Handoff and stop

At the end of the current task, provide a concise Arabic report containing:

- What changed and the resulting user-visible behavior.
- Verification results and any material limitations or remaining manual checks.
- Issue, pull request, and commit references when available, plus the actual merge/CI state.
- Any separate problems discovered and the next suggested approved task.

After completing and merging the current task, stop and wait for the owner to say "كمل" or give another instruction. Do not start the next roadmap task automatically. If blocked, report the blocker and the specific decision or access needed.

## Maintaining these instructions

Keep this file concise and operational. Put detailed architecture, quality commands, feature specifications, and progress in their owning documents. Update rules when an observed recurring failure justifies a concrete rule; avoid duplicating requirements or accumulating generic instructions.
