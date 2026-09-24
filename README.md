# Sherko Pharma

Flutter project for an online pharmacy product catalog and customer-order calculator on Android and Windows.

## Current state

SP-000 established the product contract and SP-001 established protected hosted CI. SP-002 introduces the minimal Riverpod application shell and responsive navigation structure; catalog, order, authentication, Supabase, persistence and scanner features remain unimplemented. See [development status](docs/DEVELOPMENT_STATUS.md) for the live task state.

## Setup and verification

1. Install the exact stable Flutter version from `.flutter-version` (currently 3.38.7) using the [official archive](https://docs.flutter.dev/install/archive), and add its `bin` directory to PATH. This is a compatible baseline, not a claim to be the newest release.
2. Install Python 3.11+ (CI uses 3.12.9). For Android, install Android SDK tooling and Temurin JDK 17; CI uses 17.0.18+8. For Windows, use Windows with Visual Studio 2022 and Desktop development with C++.
3. Run `flutter doctor -v` to inspect your target-platform prerequisites.
4. From the repository root, run `python tool/verify.py quick` (`python3` where required). This enforces the pinned SDK and committed lockfile, then runs static analysis and all Flutter tests. This project does not enforce `dart format`; keep Flutter UI code conventionally readable in review.
5. Run `flutter run -d windows` on Windows or select your connected Android device with `flutter devices` / `flutter run -d DEVICE_ID`.

Build checks: `python tool/verify.py android` and `python tool/verify.py windows` on their supported hosts. Documentation checks: `python tool/verify.py docs`. See [QUALITY.md](docs/QUALITY.md) for exact CI jobs, targeted feedback, merge gates and limitations.

CI uses GitHub-hosted runners, runs fast checks before platform builds, and requires no production credentials. A successful build is not a commercially signed release or evidence of real scanner compatibility.

## Agreed initial scope

- Online Supabase catalog with owner-only email/password access and server-enforced permissions.
- Search, create, and edit products; either barcode field identifies the same product/package.
- Customer orders with whole-number SYP or USD prices and a separate total for each currency.
- Persistent active order and local edit draft; drafts reach the server only after explicit Save.
- Android camera scanning and Windows external-reader input. The Windows reader has not been selected.
- English interface initially, with readable Arabic product data.

These are requirements to implement, not current application capabilities. Inventory, sales history, offline catalog replication, licensing, and a separate administration app are deferred.

## Documentation

| Document | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Agent contract: inspect live state, one bounded Issue, PR, verification, merge, then stop |
| [Product requirements](docs/PRODUCT.md) | Agreed scope and acceptance criteria |
| [Architecture](docs/ARCHITECTURE.md) | Technical boundaries and decisions |
| [Quality gates](docs/QUALITY.md) | Required checks and physical-device acceptance |
| [Data rules](docs/DATA_MODEL.md) | Fields, validation, barcodes, prices, and currencies |
| [Interaction flows](docs/UX_FLOWS.md) | New orders, unsaved edits, drafts, and sign-out |
| [Roadmap](docs/ROADMAP.md) | Task order, dependencies, and completion evidence |
| [Development status](docs/DEVELOPMENT_STATUS.md) | Actual implementation state and handoff |
| [Decision template](docs/decisions/TEMPLATE.md) | Context, alternatives and reasons for significant decisions |
| [CI baseline decision](docs/decisions/0001-verification-baseline.md) | Toolchain, gates and cost/complexity tradeoffs |

## Contributing and agent work

Read [AGENTS.md](AGENTS.md) first and follow its document-reading order. Refresh the remote default branch and related Issues/PRs before starting. Use a task branch and PR; do not push implementation directly to the default branch.

Use the GitHub task form and PR template to record acceptance examples, revision-specific evidence and a separate review pass. Apply the checks required by [QUALITY.md](docs/QUALITY.md). Documentation-only changes use its lighter review/link gates. Camera or reader behavior changes require the owner's real-device acceptance before merge. After completing one task, stop and wait for the owner to continue.

## Data and configuration

The full medication CSV is deliberately not included. Import it only through the future controlled backend workflow; use synthetic test fixtures in the public repository.

Never commit credentials, privileged server keys, source data dumps, or production request payloads. Backend provisioning and configuration instructions will be added with the implementing tasks; no server integration exists in this scaffold.
