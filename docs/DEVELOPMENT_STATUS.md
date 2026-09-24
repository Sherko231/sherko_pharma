# Sherko Pharma — Development Status

Updated: 2026-09-24
Active task: [SP-001 / Issue #3](https://github.com/Sherko231/sherko_pharma/issues/3).
Status: Workflow and CI implementation prepared; hosted checks and external settings verification remain pending. Do not interpret file presence as a passing check or active repository protection.

## Verified starting state

- Default branch: `main`, inspected at `5d1d9b94c1faa31bcc7667f44c4ee60bb6dc399b`.
- SP-000: merged through [PR #2](https://github.com/Sherko231/sherko_pharma/pull/2); Issue #1 closed.
- Clean local checkout created and inspected; no existing open Issues/PRs before Issue #3.
- Application: minimal `Hello World!` scaffold, Flutter SDK runtime dependency only, version 0.1.0, Dart constraint ^3.10.7.
- No existing tests/workflows at task start. Branch API reports `protected: false`; ruleset collection empty.
- Windows reader remains unselected. No Supabase deployment, real catalog import or credentials were accessed.

## SP-001 implementation

Branch: `chore/sp-001-workflow-ci`. Pull request: [#4](https://github.com/Sherko231/sherko_pharma/pull/4).

- Exact Flutter pin; shared verification entry point and tested fail-closed CI aggregation.
- Hosted format/analyze/test and Android/Windows builds, documentation-only classification, caches and superseded-PR cancellation.
- Launch smoke checks at phone and desktop sizes; application behavior remains the scaffold.
- Bounded task and PR templates, concise agent contract, requirement-derived test policy, separate review pass, significant-decision template.
- Owner-approved sensitive-change acceptance exception, complementing the existing physical-scanner acceptance exception.
- No application feature dependency or source dataset added. No artifact publication or paid service enabled.

## Verification evidence and limitations

- Local Python verification-tool tests pass (five cases including bootstrap output and failure/cancellation/skip/missing-result subcases); relative Markdown file link check and diff whitespace check pass at the recorded implementation stage. Refresh evidence on the final revision.
- Local Flutter bootstrap was attempted but automatic approval review rejected continued execution after detecting an unexpected cloud metadata endpoint request. Do not retry or claim local Flutter tests passed. Hosted CI is the intended verification path.
- First hosted run [35967940301](https://github.com/Sherko231/sherko_pharma/actions/runs/35967940301) rejected the original scaffold formatting; the aggregate correctly failed and platform builds were skipped. This revision normalizes only `lib/main.dart` formatting and updates newly introduced Actions to current Node 24-compatible versions. Application behavior and lockfile remain unchanged. Latest full checks are pending; consult PR #4 for final revision evidence.
- Second run [35968398556](https://github.com/Sherko231/sherko_pharma/actions/runs/35968398556), head `551c1f4ea0a2d0d2b1d50e957d857b194aa65f3e`: formatting, analysis, both Flutter smoke cases, Python gate tests and Android build passed. Windows failed before building because first-run Flutter bootstrap text polluted machine JSON. Added a regression that reproduced this failure before the fix, then passed after explicitly completing bootstrap before reading machine JSON. Latest hosted verification remains required.
- Separate full-diff review: self-review pass performed; no independent reviewer is claimed. Recheck subsequent fixes and final evidence before merge.
- GitHub connector supports repository file/PR operations but exposes no settings mutation for protection or Codex review. Browser inspection of repository settings shows a signed-out session. External settings remain unconfigured/unverified; owner account access is needed after the concrete PR is ready.
- Main protection is not yet active. Routine unattended code merges remain blocked until effective protection is verified. Native auto-merge being disabled is separate from agent merge authorization.
- No emulator/device tests, scanner acceptance, backend tests or commercial-release verification are claimed.

## Handoff and remaining work

Finish hosted CI on the latest PR revision, review the complete diff, and activate/verify `main` protection using the exact settings in QUALITY.md. Check Codex cloud review availability and enable it if available without new paid access; otherwise preserve the disclosed separate-review fallback.

After SP-001 is verified and merged, the next proposed task is SP-002 (minimal Riverpod structure). Stop for owner continuation. Catalog, authentication, data import, editing, orders, session storage and scanning remain unimplemented.

Other known future decisions: schema/source mapping, isolated Supabase environment, Windows reader, final application identity and commercial signing. The Android ID remains `com.example.sherko_pharma` and current signing is for development.

## Updating this record

Keep factual state here; requirements live in PRODUCT.md, architecture in ARCHITECTURE.md, executable checks/acceptance in QUALITY.md, and task execution in AGENTS.md. Record exact Issue/PR/run references, relevant reviewed revision and remaining blockers. Put the eventual merge SHA in the handoff or next reviewed update, never a direct default-branch commit merely to fill in this file.
