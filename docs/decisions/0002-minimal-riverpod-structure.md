# ADR-002: Minimal Riverpod application structure

Status: Accepted implementation baseline for SP-002
Date: 2026-09-24
Task: [Issue #5](https://github.com/Sherko231/sherko_pharma/issues/5)

## Context

SP-002 needs a real application bootstrap and responsive shell before product features are implemented. The architecture selects Riverpod for state/dependency management and explicitly rejects empty layers created only to match a folder diagram.

The repository is pinned to Flutter 3.38.7 with Dart 3.10.7. The current flutter_riverpod 3.4.x line requires Dart 3.12, while flutter_riverpod 3.3.2 supports this project's SDK baseline.

The owner also directed this repository to stop enforcing `dart format` because compact automatic rewrites can reduce readability in Flutter widget trees.

## Decision and consequences

- Pin `flutter_riverpod 3.3.2` and keep Flutter/Dart unchanged in this task.
- Wrap the application in `ProviderScope`.
- Store shell navigation selection in a Riverpod `Notifier` controller.
- Use a bottom `NavigationBar` on narrow layouts and a `NavigationRail` on wider layouts.
- Provide a reusable `AsyncValue` presentation boundary with explicit loading, data and error states.
- Show only honest Catalog/Order workspace placeholders. Do not add Supabase, persistence, calculations, scanner behavior or synthetic product data.
- Do not create repository interfaces until a concrete feature requires I/O. This follows the existing architecture rule against speculative empty layers.
- Keep lockfile enforcement, static analysis, full tests and both platform builds in CI. Remove only automatic Dart formatting enforcement; readability remains a review concern.

This establishes boundaries without pretending future features exist. Feature-specific repositories/controllers are introduced by the tasks that own their real behavior and data contracts.

## References

- [Architecture](../ARCHITECTURE.md)
- [Quality gates](../QUALITY.md)
- [Roadmap](../ROADMAP.md)
- [flutter_riverpod versions](https://pub.dev/packages/flutter_riverpod/versions)
