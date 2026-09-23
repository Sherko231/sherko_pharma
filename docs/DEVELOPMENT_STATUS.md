# Sherko Pharma — Development Status

Status: SP-000 documentation bootstrap is implemented by this change for Issue #1. Application features, CI, and backend setup remain unimplemented. The task record below distinguishes this change from the historical baseline.

## Verified pre-SP-000 baseline

| Item | Observed state |
| --- | --- |
| Repository | https://github.com/Sherko231/sherko_pharma |
| Visibility | Public |
| Default branch | `main` |
| Inspected commit | `2c5e0aa32a7b7ef246511cafff034adaf977d8b7` |
| Commit timestamp | `2026-09-22T21:15:18Z` |
| Application | Minimal `Hello World!` screen in `lib/main.dart` |
| Platform source trees | Android and Windows present |
| Package version | `0.1.0` |
| Declared Dart constraint | `^3.10.7`; not an exact Flutter SDK pin |
| Runtime dependencies | Flutter SDK only; no Riverpod or Supabase package yet |
| Analysis configuration | Includes `package:flutter_lints/flutter.yaml` |
| Tests | No tracked test files in the complete inspected Git tree |
| CI | No `.github/workflows` files in the inspected tree; workflow-runs API returned zero runs |
| Open Issues / PRs | Both API collections returned empty |
| Main protection | Branch API reports `protected: false`, required status checks off |
| Repository rulesets | Ruleset collection returned empty |
| GitHub native auto-merge | `allow_auto_merge: false` |
| Android namespace/application ID | `com.example.sherko_pharma` |
| Android release signing | Current Gradle configuration uses debug signing |
| Repository instructions/docs | No `AGENTS.md` or `docs/` tree; README contains only the project name and a generic Flutter description |

Snapshot evidence must be refreshed at task start. Do not treat the absence of open work at inspection time as a permanent state.

## Documentation delivered by SP-000

This change adds the following repository documentation:

- `AGENTS.md`: task execution, verification, merge, and stop rules.
- `docs/PRODUCT.md`: confirmed initial scope and acceptance criteria.
- `docs/ARCHITECTURE.md`: online Supabase/Flutter boundaries and Riverpod decision.
- `docs/QUALITY.md`: hosted CI policy and real-device acceptance exception.
- `docs/DATA_MODEL.md`: names, editable properties, alternative barcodes, integer SYP/USD pricing, and separate totals.
- `docs/UX_FLOWS.md`: new-order confirmation, edit navigation, local drafts, and session/account behavior.
- `docs/ROADMAP.md`: proposed bounded task sequence and dependencies.
- `docs/DEVELOPMENT_STATUS.md`: this baseline and handoff.

SP-000 also replaces the generic README with the project overview and document index. These documents define requirements; they do not claim the planned application features are implemented.

## Implemented versus planned

Implemented in the inspected repository: only the minimal application scaffold.

Not implemented in the application: owner sign-in, server catalog, controlled import, search, product editing, local drafts, customer orders, session restoration, separate currency totals, refresh/conflict handling, camera scanning, external-reader support, and CI. The workflow contract is delivered in SP-000; technical enforcement through checks and branch protection remains SP-001.

The owner has supplied and discussed corrected source data. No database import was executed by this review. No Supabase project, deployed schema, or production permissions were inspected; their external state is unknown.

## Task record and next step

- Task: SP-000, documentation bootstrap.
- Issue: [#1](https://github.com/Sherko231/sherko_pharma/issues/1).
- Branch: `docs/sp-000-project-contract`, based on the verified baseline above.
- Pull request: [#2](https://github.com/Sherko231/sherko_pharma/pull/2). Use its live state as the source of truth for merge completion.
- Delivered scope: root agent contract, seven documents under `docs/`, and README overview/index.
- Documentation verification: reviewed confirmed requirements and the full nine-file Markdown diff; all 12 repository-relative Markdown links resolve; 16 roadmap task IDs are unique with ordered dependencies; all 40 original files other than the intentionally updated README retain identical blob SHAs and modes. No source CSV/product records or credential material is included.
- Reviewed predecessor: `5abffe993979f8668c846b76dd34acf93e69cd2b`. The final revision also requires refreshed verification before merge; record its real merge SHA in the handoff rather than inventing a self-referential SHA here.
- Application tests/builds: not run; not required for this documentation-only task under `QUALITY.md`.
- Merge lifecycle: verify the real PR state and merge SHA before reporting completion; no future merge SHA is invented in this file.
- Next proposed task after merge: SP-001, reproducible hosted CI and merge gates. Wait for the owner to say "كمل".

## Verification limits

- The full recursive Git tree was returned with `truncated: false`; source/configuration files were read at the fixed inspected commit.
- This task uses authenticated GitHub API operations because the local execution environment is unavailable. No local checkout, working-directory status, or uncommitted local changes can be inspected; no such inspection is claimed.
- No Flutter commands, tests, emulator/device runs, or builds were executed. No result should be labelled passing on that basis.
- The direct workflow-list endpoint was unavailable through the connector; CI absence is supported by the inspected source tree and the separate successful workflow-runs query.
- SP-000 creates its task Issue, dedicated documentation branch, commits, and PR. It does not change application code, dependencies, CI, repository settings, or server resources.

## Remaining implementation decisions and blockers

- Windows reader model and protocol await purchase/selection; real-device acceptance is required for its integration.
- Select exact compatible Flutter/package versions and platform storage/scanner packages during the appropriate setup tasks.
- Complete source field mapping, anomaly policy, bounded API design, and detailed UI layout before implementing the affected behavior.
- Select/inspect the intended Supabase environment and establish owner authorization; do not assume another existing project is appropriate.
- Configure CI and effective branch protections before routine automatic code merges.
- Final app identity, release signing, and delivery configuration remain to be established.
- Keep the complete CSV and credentials out of the public repository; use synthetic fixtures.

## Update rules

For each reviewed task, record the real Issue/PR, relevant tested commit, checks that actually ran, manual device evidence where required, actual merge result, blockers, and next task. Update this file in the task PR. A PR's own eventual merge commit can be recorded in the handoff or next reviewed update; do not invent a future SHA or create a direct default-branch commit just to fill it in.

## Evidence entry points

- [Inspected commit](https://github.com/Sherko231/sherko_pharma/commit/2c5e0aa32a7b7ef246511cafff034adaf977d8b7)
- [Application source at baseline](https://github.com/Sherko231/sherko_pharma/blob/2c5e0aa32a7b7ef246511cafff034adaf977d8b7/lib/main.dart)
- [Package manifest at baseline](https://github.com/Sherko231/sherko_pharma/blob/2c5e0aa32a7b7ef246511cafff034adaf977d8b7/pubspec.yaml)
- [Android build configuration at baseline](https://github.com/Sherko231/sherko_pharma/blob/2c5e0aa32a7b7ef246511cafff034adaf977d8b7/android/app/build.gradle.kts)
