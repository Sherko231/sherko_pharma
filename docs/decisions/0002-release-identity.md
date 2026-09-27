# ADR-002: Release identity and external signing boundary

Status: Accepted; CI portion superseded by OPS-001 / Issue #42
Date: 2026-09-26
Task: Issue #38 / SP-015; Android identity amended by Issue #40 / REL-001 before public distribution.

## Context

The Flutter scaffold used a placeholder Android identity and debug release signing. SP-015 established a stable delivery identity and an external production-signing boundary.

## Decision and consequences

- Android application ID/namespace is `com.samo.sherkopharma`.
- Android release builds fail rather than falling back to the debug key when signing configuration is missing.
- `android/key.properties` and keystores remain ignored and private.
- Production Android signing is performed locally with the owner's external release/upload key.
- Windows executable/window metadata use `Sherko Pharma`; no production Windows code-signing certificate is embedded in the repository.
- Hosted CI and synthetic CI signing are retired by OPS-001.
- Release builds, packaging, runtime configuration and checksums are owner-controlled as described in [RELEASE.md](../RELEASE.md).
- Confirm public store/package-name availability before first submission because changing the Android application ID after distribution creates a different application identity.

## References

- [Product requirements](../PRODUCT.md)
- [Local verification policy](../QUALITY.md)
- [Delivery procedure](../RELEASE.md)
- [Flutter Android deployment](https://docs.flutter.dev/deployment/android)
- [Flutter Windows deployment](https://docs.flutter.dev/deployment/windows)
