# Sherko Pharma

Flutter project for an online pharmacy product catalog and customer-order calculator on Android and Windows.

## Current state

SP-000 through SP-007 establish the product contract, schema/source mapping, owner-only bounded catalog API, controlled import workflow, secure owner authentication/session handling, and server-backed catalog search/detail. The earlier hosted-CI setup has been retired by owner decision. SP-008 adds validated product create/edit flows; SP-009 adds account-scoped persistent edit drafts; SP-010 adds the manual customer-order calculator; SP-011 adds account-scoped local page/order session persistence; SP-012 adds scoped current-data refresh and explicit order price-change handling; SP-013 adds Android camera barcode scanning. SP-015 prepares the current scope for release-mode delivery without reintroducing deferred SP-014. SP-016 through SP-020 refine Android scanning with focused framing, a compact continuous scanner, one server lookup per unique scan, explicit color/beep/haptic feedback, and no automatic zoom; SP-020 also applies comma-grouped whole-amount display/input formatting without changing integer price semantics. SP-021 merges normal catalog search and order management into one always-primary compact Cart workspace with no separate Catalog/Order navigation. SP-022 refines it into a POS-style workflow with a unified search/scan command surface, transient search results, persistent totals, flat dense cart rows and an adaptive supporting pane on wide screens. SP-023 upgrades manual catalog search with indexed Unicode/Arabic normalization, weighted multi-token prefix search, typo-tolerant trigram matching, exact barcode/name priority and a faster 180 ms client debounce. SP-024 normalizes manufacturer and dosage form into reference identities with aliases/FKs, types currency as an SYP/USD database enum, and keeps complex composition/strength/package data as text where automatic decomposition would be unsafe. SP-025 keeps the raw composition text unchanged while adding a private conservative ingredient registry, lexical aliases, product ingredient links, order-independent ingredient-set keys, and explicit review/unresolved statuses as the foundation for later strength/equivalence work. SP-026 keeps raw strength text unchanged while deriving exact unit-normalized ingredient-strength pairs only for deterministic syntax, distinguishing concentration denominators from presentation suffixes and quarantining ambiguous mappings. SP-027 adds a private conservative pharmaceutical-equivalence layer that emits a strict key only when trusted ingredient-strength, dosage-form, route, and release dimensions are complete; ambiguous routes/forms remain reviewable or unresolved. SP-028 exposes those reviewed relationships through one owner-only bounded alternatives RPC with separate exact, different-strength, and different-form groups; it does not add UI or therapeutic-interchangeability inference. The dedicated hosted project remains on the Free plan; the approved corrected source catalog has been imported and verified at 23,750 source rows. See [development status](docs/DEVELOPMENT_STATUS.md) and [delivery acceptance](docs/DELIVERY_ACCEPTANCE.md) for evidence.

## Setup and verification

1. Install the exact stable Flutter version from `.flutter-version` (currently 3.38.7) using the [official archive](https://docs.flutter.dev/install/archive), and add its `bin` directory to PATH. This is a compatible baseline, not a claim to be the newest release.
2. Install Python 3.11+ for the optional local helper scripts. For Android, install Android SDK tooling and JDK 17. For Windows, use Windows with Visual Studio 2022 and Desktop development with C++.
3. Run `flutter doctor -v` to inspect your target-platform prerequisites.
4. From the repository root, run `python tool/verify.py quick` (`python3` where required). This enforces the pinned SDK and committed lockfile, then runs static analysis and all Flutter tests. This project does not enforce `dart format`; keep Flutter UI code conventionally readable in review.
5. For an unconfigured development launch, run normally and the app will fail closed on a configuration-required screen. For a configured Supabase environment, provide the client-safe project values at build/run time, for example `flutter run -d windows --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=CLIENT_SAFE_KEY`. Use the same defines for an Android target. Never pass a service-role/secret key.

Optional local checks include `python tool/verify.py quick`, `python tool/verify.py android`, `python tool/verify.py windows`, and `python tool/verify.py docs`. They are available for diagnosis or release preparation but are not automatic merge gates. See [QUALITY.md](docs/QUALITY.md) for the current owner-local verification policy and [RELEASE.md](docs/RELEASE.md) for signing/packaging.

## Agreed initial scope

- Online Supabase catalog with owner-only email/password access and server-enforced permissions.
- Search, create, and edit products; either barcode field identifies the same product/package.
- One compact Cart workspace combines manual catalog search, Android barcode scanning, customer-order lines and separate SYP/USD totals.
- Persistent active order and local edit draft; drafts reach the server only after explicit Save.
- Android camera scanning. Windows external-reader input is deferred from the current initial delivery and will be re-authorized as a later hardware task.
- English interface initially, with readable Arabic product data.

Authentication, catalog search/detail, product create/edit, persistent product drafts, manual order calculation, durable account-scoped local restoration, scoped catalog/order refresh, and Android camera barcode scanning are implemented. Server price/currency changes preserve captured order totals until explicit acceptance. Windows external-reader integration is deferred from the current initial delivery and remains planned for later owner re-authorization after hardware selection. Inventory, sales history, offline catalog replication, licensing, and a separate administration app are also deferred.

## Documentation

| Document | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Agent contract: inspect live state, one bounded Issue/PR, review, merge, then stop |
| [Product requirements](docs/PRODUCT.md) | Agreed scope and acceptance criteria |
| [Architecture](docs/ARCHITECTURE.md) | Technical boundaries and decisions |
| [Local verification](docs/QUALITY.md) | Optional local checks, owner testing, and production-sensitive safeguards |
| [Data rules](docs/DATA_MODEL.md) | Fields, validation, barcodes, prices, and currencies |
| [Source mapping](docs/SOURCE_MAPPING.md) | Corrected CSV fingerprint, complete 25-column mapping, and anomaly policy |
| [Controlled import](docs/IMPORT.md) | Dry-run, fingerprint enforcement, idempotent import, and deployment safety |
| [Auth acceptance](docs/AUTH_ACCEPTANCE.md) | Secret-safe real Windows/Android sign-in and session-restoration checklist |
| [Delivery acceptance](docs/DELIVERY_ACCEPTANCE.md) | Current initial-scope acceptance matrix and remaining owner-only release actions |
| [Release procedure](docs/RELEASE.md) | Runtime configuration, external signing, packaging, artifact handling, and recovery |
| [Interaction flows](docs/UX_FLOWS.md) | New orders, unsaved edits, drafts, and sign-out |
| [Roadmap](docs/ROADMAP.md) | Task order, dependencies, and completion evidence |
| [Development status](docs/DEVELOPMENT_STATUS.md) | Actual implementation state and handoff |
| [Decision template](docs/decisions/TEMPLATE.md) | Context, alternatives and reasons for significant decisions |
| [Historical verification decision](docs/decisions/0001-verification-baseline.md) | Retired hosted-CI decision and current no-CI policy |
| [Release identity decision](docs/decisions/0002-release-identity.md) | Android package identity and external signing boundary |

## Contributing and agent work

Read [AGENTS.md](AGENTS.md) first and follow its document-reading order. Refresh the remote default branch and related Issues/PRs before starting. Use a task branch and PR; do not push implementation directly to the default branch.

Use the GitHub task form and PR template to record acceptance examples and a separate diff review. Hosted CI is intentionally disabled. Local checks are optional unless the owner explicitly asks for one; the owner may pull and test the merged revision on the real target device and report problems for a follow-up fix. After completing one task, stop and wait for the owner to continue.

## Data and configuration

The full medication CSV is deliberately not included. Use the controlled workflow in [IMPORT.md](docs/IMPORT.md); only synthetic import fixtures belong in the public repository.

Never commit credentials, privileged server keys, source data dumps, or production request payloads. A dedicated Free hosted Sherko Pharma environment is provisioned for the versioned schema/API/auth boundary. The approved corrected source catalog was imported with 23,750 source rows; future controlled reruns remain insert-only for that dataset identity.
