# Sherko Pharma — Development Status

Updated: 2026-09-24
Active task: [SP-002 / Issue #5](https://github.com/Sherko231/sherko_pharma/issues/5).
Branch: `feat/sp-002-app-structure`.
Status: Implementation is reviewable on PR #6. Full hosted CI passed on head `d85063c896466a1976a0475aaeb46a87c6cde0d2` in run 36011707744; this status update requires a fresh final-revision CI run before merge.

## Verified current baseline

- Default branch: `main` at `05f2da264ba881648dbdf5eb560948a16ca150b7` when SP-002 started.
- SP-000 merged through PR #2.
- SP-001 merged through PR #4; Issue #3 closed as completed.
- SP-001 pre-merge run 36008400613 and post-merge run 36009167245 both passed Change scope, Quality, Android build, Windows build and Required verification.
- `main` protection remains provided by active repository ruleset `Protect main` (ID 23941205): pull requests, up-to-date required check `Required verification`, resolved review conversations, deletion/non-fast-forward protection and no bypass actors.
- No open Issues or PRs existed immediately before Issue #5 was created.
- No Supabase deployment, source catalog import, production credentials or scanner hardware is part of this task.

## SP-002 scope and implementation

- Add Riverpod at the application root and use a Riverpod controller for shell navigation.
- Add a responsive shell: compact `NavigationBar` on narrow layouts and `NavigationRail` on wider layouts.
- Add an explicit reusable `AsyncValue` loading/error/data presentation boundary for future feature controllers.
- Keep Catalog and Order as honest workspace placeholders only; no server calls, persistence, calculations or scanner behavior are implemented.
- Do not create empty repository/service layers before a concrete I/O feature needs them; `ARCHITECTURE.md` explicitly forbids speculative layers.
- Use `flutter_riverpod 3.3.2`. Current Flutter 3.38.7 supplies Dart 3.10.7; Riverpod 3.4.x requires Dart 3.12, so upgrading the SDK only to use the newest Riverpod line is outside this task.
- The dependency lockfile was resolved by a temporary GitHub-hosted Flutter workflow on the task branch, committed for review, and the temporary workflow was removed before the task PR.
- Per the owner's explicit instruction, `python tool/verify.py quick` no longer invokes or enforces `dart format`. Exact SDK/lockfile verification, static analysis, full Flutter tests, Android build, Windows build and fail-closed Required verification remain mandatory.

## Verification expectations

- ProviderScope/bootstrap wiring is covered by widget tests.
- Phone and desktop layouts must render without framework exceptions and choose the expected navigation component.
- Navigation selection must be Riverpod-owned rather than widget-local state.
- Loading, data and error presentation states must be exercised.
- Verification-tool tests must prove the quick path keeps analysis/tests while not invoking `dart format`.
- Because application dependencies and CI verification configuration changed, the final PR requires the full hosted gate set and a complete gate/configuration diff review.
- No physical-device acceptance is required because camera/reader behavior is unchanged.

## Verification evidence

- Pull request: [#6](https://github.com/Sherko231/sherko_pharma/pull/6).
- Hosted run [36011707744](https://github.com/Sherko231/sherko_pharma/actions/runs/36011707744) passed on `d85063c896466a1976a0475aaeb46a87c6cde0d2`: Change scope, Quality, Android build, Windows build and Required verification all succeeded.
- Quality passed the documentation checks, verification-tool regressions, exact Flutter/lockfile enforcement, static analysis and the full Flutter widget regression suite.
- Android debug and Windows release builds both succeeded.
- The temporary lock-resolution workflow has no net diff in PR #6; it was removed before the PR was opened.
- Final review and merge evidence remain pending until the latest revision, including this status update, is reverified.

## Handoff

SP-002 is not complete until its latest reviewed PR revision passes the applicable hosted gates, GitHub reports merge eligibility under the active ruleset, the separate review pass is recorded, the PR is merged, and post-merge CI succeeds on `main`.

After SP-002, stop for owner continuation. Backend schema, authorization, source import, authentication, catalog behavior, orders, persistence and scanning remain future bounded tasks.

## Updating this record

Keep factual state here; requirements live in PRODUCT.md, architecture in ARCHITECTURE.md, executable checks/acceptance in QUALITY.md, and task execution in AGENTS.md. Record exact Issue/PR/run references, relevant reviewed revision and remaining blockers. Put eventual merge evidence in a reviewed task update or PR handoff rather than making a direct default-branch bookkeeping commit.
