# ADR-001: Reproducible verification before feature development

Status: Accepted implementation baseline for SP-001; execution/settings evidence remains in DEVELOPMENT_STATUS.md and the PR.
Date: 2026-09-24
Task: [Issue #3](https://github.com/Sherko231/sherko_pharma/issues/3)

## Context

The Flutter scaffold declares Dart ^3.10.7, has a committed lockfile and Android/Windows targets, but has no tests or CI. The owner authorized workflow hardening before feature work, GitHub-hosted runners and automatic merge after applicable gates, with specific owner-acceptance exceptions.

## Options and decision

- Pin Flutter 3.38.7, a compatible stable baseline for the existing scaffold, instead of combining CI bootstrap with a broad SDK upgrade. Its Git tag resolves to `3b62efc2a3da49882f43c372e0bc53daef7295a6`. `.flutter-version` is the version source used by CI and verification. Revisit via a scoped upgrade with both platform checks.
- Keep existing Gradle/AGP/Kotlin pins; select Temurin 17.0.18+8 for Android CI and Python 3.12.9 for the shared dependency-free scripts. These are exact SDK/JDK/interpreter choices; hosted OS images still receive upstream changes.
- Use one Python entry point across Windows/Linux. Separate PowerShell and Bash implementations would duplicate gate logic; a Dart-only command would require Flutter setup even for documentation changes.
- Keep a narrow docs-only exemption and a single aggregate `Required verification` status. All unknown changes receive full verification. Do not rely on path-skipped entire workflows, which can leave required checks absent.
- Cache SDK/dependency downloads, cancel superseded PRs and run fast checks before builds. This adds one lightweight aggregation job but reduces repeated expensive work after obvious failures.
- Pin third-party Actions by full commit SHA, give CI read-only contents permission and remove persisted checkout credentials. Do not run untrusted PR code through `pull_request_target` or pass production secrets.

## Consequences and limits

CI validates compilation and exercised behavior, not full correctness. Review the workflow itself to avoid accepting weakened checks. Keep significant behavior examples in the task contract and derive tests from them. A separate self-review pass is explicitly disclosed when an independent reviewer is unavailable.

Branch protection and Codex review are external settings; files cannot activate them. Their observed status must be read back. No automatic artifacts, paid services, production access, source-data import or release distribution is included. Android verification creates a debug APK; Windows uses a release build without claiming release readiness.

## References

- [Flutter archive](https://docs.flutter.dev/install/archive)
- [Flutter testing](https://docs.flutter.dev/testing/overview)
- [Flutter setup Action](https://github.com/subosito/flutter-action)
- [Java setup Action](https://github.com/actions/setup-java)
- [GitHub branch protections](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [Codex best practices](https://learn.chatgpt.com/guides/best-practices)
