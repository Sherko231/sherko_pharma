# Sherko Pharma

Flutter project for an online pharmacy product catalog and customer-order calculator on Android and Windows.

## Current state

The application is still the initial `Hello World!` scaffold. SP-000 adds the agreed documentation and workflow; it does not implement the catalog, authentication, orders, scanning, or CI.

The current manifest declares Dart `^3.10.7` and app version `0.1.0`. A compatible exact Flutter SDK pin, reproducible setup commands, and hosted Android/Windows verification will be established in SP-001. No tests or GitHub Actions workflows are present yet. Do not describe an unrun build or planned check as passing.

See [development status](docs/DEVELOPMENT_STATUS.md) for the inspected baseline, this task's references, and remaining work.

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

## Contributing and agent work

Read [AGENTS.md](AGENTS.md) first and follow its document-reading order. Refresh the remote default branch and related Issues/PRs before starting. Use a task branch and PR; do not push implementation directly to the default branch.

Apply the checks required by [QUALITY.md](docs/QUALITY.md). Documentation-only changes use its lighter review/link gates. Camera or reader behavior changes require the owner's real-device acceptance before merge. After completing one task, stop and wait for the owner to continue.

## Data and configuration

The full medication CSV is deliberately not included. Import it only through the future controlled backend workflow; use synthetic test fixtures in the public repository.

Never commit credentials, privileged server keys, source data dumps, or production request payloads. Backend provisioning and configuration instructions will be added with the implementing tasks; no server integration exists in this scaffold.
