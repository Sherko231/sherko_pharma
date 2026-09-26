# ADR-002: Release identity and external signing boundary

Status: Accepted
Date: 2026-09-26
Task: Issue #38 / SP-015; Android identity amended by Issue #40 / REL-001 before public distribution.

## Context

The Flutter scaffold still used the placeholder Android identity `com.example.sherko_pharma` and signed release builds with the debug key. The Windows executable metadata also retained scaffold values. SP-015 requires a stable delivery identity and a release process that can be verified in public CI without committing private signing material.

## Options and tradeoffs

1. Keep the placeholder identity and debug signing.
   - Lowest implementation effort.
   - Not suitable as a delivery identity and makes a release-looking APK use a development key.
2. Commit or centrally store a real production signing key for CI.
   - Allows CI to create production-signed artifacts.
   - Expands secret exposure and recovery risk and is unnecessary because this repository does not publish releases automatically.
3. Use a product-specific identity, require external production signing, and exercise release mode in CI with disposable synthetic signing.
   - Keeps production keys owner-controlled and out of Git.
   - CI still verifies release Gradle configuration instead of only debug builds.
   - CI artifacts are not production-distributable, which must be stated explicitly.

## Decision and consequences

Choose option 3. Before public distribution, the owner amended the product-specific Android identity in Issue #40 / REL-001.

- Android application ID/namespace is `com.samo.sherkopharma`.
- Android release builds fail rather than falling back to the debug key when signing configuration is missing.
- `android/key.properties` and keystores remain ignored and private.
- Hosted CI creates a one-day synthetic keystore on the disposable runner and uses it only for the release-build gate.
- Windows executable/window metadata use `Sherko Pharma`. The repository does not embed a Windows production code-signing certificate.
- CI does not upload release artifacts. `RELEASE.md` defines owner-controlled packaging, signing, checksums, and runtime configuration.
- Public store/package-name availability has not been established by repository tests. Confirm it before the first public submission, because changing the Android application ID after distribution represents a different application identity.

Revisit this decision only when the owner chooses a concrete public distribution channel or a secure signing service whose operational/security tradeoffs justify changing the owner-controlled boundary.

## References

- [Product requirements](../PRODUCT.md)
- [Quality gates](../QUALITY.md)
- [Delivery procedure](../RELEASE.md)
- [Flutter Android deployment](https://docs.flutter.dev/deployment/android)
- [Flutter Windows deployment](https://docs.flutter.dev/deployment/windows)
