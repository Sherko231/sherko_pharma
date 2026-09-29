# Sherko Pharma — Quality and Local Verification

Status: Automated GitHub Actions CI is retired by OPS-001 / Issue #42. The owner chose local, pull-and-test verification instead of hosted CI gates.

## Current policy

- No GitHub Actions workflow is required for pull requests, pushes or post-merge verification.
- No hosted CI status is a merge prerequisite.
- Local verification commands remain available as optional engineering tools.
- The owner may pull the merged revision, run the app on the real target machine/device and report any problem for a follow-up fix.
- A successful build or test only proves the behavior it exercises; it is not universal correctness evidence.
- Never use production credentials, privileged keys, the private source CSV or destructive production operations merely to test a change.

## Optional local commands

Use these when useful for the task or when the owner asks for them. They are not automatic merge gates.

| Command | Purpose |
| --- | --- |
| `python tool/verify.py docs` | Check repository-relative Markdown links |
| `python -m unittest discover -s tool -p 'test_*.py' -v` | Run verification/import helper tests |
| `python tool/verify.py quick` | Check the pinned Flutter setup, analyze and run Flutter tests |
| `python tool/verify.py quick --test test/app_smoke_test.dart` | Focused Flutter feedback |
| `python tool/verify.py android` | Build Android release locally; requires Android tooling and external release signing configuration |
| `python tool/verify.py windows` | Build Windows release locally |
| `python tool/catalog_import.py dry-run --source <private-csv>` | Validate the approved private catalog source without writing to the database |

The repository keeps tests and verification helpers because they are useful for diagnosis and release preparation. Their existence does not create a mandatory CI policy.

## Requirement-derived testing

When adding or fixing important behavior, prefer focused tests derived from the product requirement. Relevant areas include barcode identity, order totals, captured price/currency behavior, product validation, confirmed server writes, conflict handling, account isolation, draft restoration and authorization boundaries.

Do not weaken assertions merely to make a failure disappear. If the owner reports a real-device problem, reproduce it where practical and add a regression test when that test can meaningfully cover the defect.

## DDI acceptance verification

SP-037 adds synthetic cross-layer acceptance without production credentials or live third-party traffic. The regression exercises scanner/order input, trusted ingredient mapping, the real batching/aggregation engine, lifecycle state, Cart severity presentation and evidence detail rendering using fake repository/provider/link boundaries.

Focused tests across SP-032–SP-037 cover provider parsing/failures, exact resolved-pair integrity, all severity states, unresolved/partial coverage, >10 ingredient batching, rate limiting/cache/coalescing, rapid changes/stale generations, session restoration/non-persistence, Cart presentation, evidence/source links and link failure.

These automated/synthetic checks do not replace owner testing of the actual configured Android/Windows client. In particular, a DDI-enabled release candidate still needs real-device confirmation of Cart layout, browser-link launching and intended runtime/backend configuration. Do not claim that check has passed until the owner performs it.

## Real-device testing

Camera scanning, external readers, platform-specific authentication/session behavior and other hardware-dependent behavior are best checked by the owner on the actual device. These checks may happen after merge under the owner's chosen workflow. A reported failure becomes a new bounded fix task.

## Production-sensitive actions

Deleting or irreversibly transforming production data, broadening catalog access, weakening authorization, or exposing privileged credentials still requires explicit owner approval for that concrete production action. This safeguard is independent of CI and remains in effect.

## Review and completion

- Review the final diff against the approved Issue.
- Record known limitations and any checks that were actually run.
- Merge when the scope is satisfied and GitHub permits the PR.
- Verify the remote merge result/SHA.
- Do not require or claim post-merge CI.
