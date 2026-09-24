# Sherko Pharma — Development Status

Updated: 2026-09-24
Active task: [SP-003 / Issue #7](https://github.com/Sherko231/sherko_pharma/issues/7).
Branch: `feat/sp-003-versioned-schema`.
Status: Schema, mapping, and fail-closed schema verification are implemented on the task branch; PR verification/review remain pending.

## Verified current baseline

- Default branch: `main` at `d57b2ced143b70aa4b2addd9089306ef0b0dce43` when SP-003 started.
- SP-000 merged through PR #2.
- SP-001 merged through PR #4.
- SP-002 merged through PR #6; Issue #5 closed completed.
- SP-002 post-merge CI run 36013245321 passed on `main`.
- Active repository ruleset `Protect main` (ID 23941205) requires a PR, strict up-to-date `Required verification`, resolved review conversations, blocks deletion/non-fast-forward changes, and has no bypass actors.
- No production Supabase schema, owner authorization, source import, production credentials, catalog feature, order feature, or scanner behavior has been deployed.

## SP-003 inspected source evidence

The owner-supplied corrected `sy-database(2).csv` was inspected outside the public repository and is not committed.

- SHA-256: `2923fffd24e8aaee0cda7549458aec680f6ee67b50925b93ff540c2c755029a4`.
- 23,750 records and 25 columns.
- `Id` and `itemId` are unique and equal in the inspected source; `num` is separately unique but differs from them in most rows.
- `price` values are integer text from 0 to 75,993,500; 423 rows are zero-priced anomalies.
- Primary barcode has 8,260 blanks and seven duplicated nonempty values.
- Secondary barcode has 22,495 blanks and one duplicated nonempty value.
- Across both barcode fields, 13 codes refer to more than one distinct source row.
- Some nonempty barcode values contain a leading minus sign, so barcode storage remains exact text rather than numeric/GS1-normalized.
- Current source selling prices map to explicit SYP without conversion. Purchase price remains provenance only.

## SP-003 implementation

- Versioned migration: `backend/migrations/0001_product_schema.sql`.
- Synthetic schema tests: `backend/tests/001_product_schema_test.sql`.
- Complete source mapping and anomaly policy: `docs/SOURCE_MAPPING.md`.
- Generated UUID application identity independent of source identifiers and mutable catalog values.
- Explicit source identifiers plus complete raw JSONB source-row provenance.
- Nullable text barcodes with non-unique lookup indexes.
- Whole-unit integer selling amount with explicit SYP/USD currency.
- Zero-priced source rows are representable as anomalies; ordinary/manual rows require a positive amount.
- Revision metadata increments automatically on accepted updates; SP-004 owns authenticated atomic expected-revision mutations.
- Hosted CI now has a `Schema` job on full changes and `Required verification` fails closed if it is missing/failing.

## Verification expectations

The final revision requires documentation/link verification, verification-tool regressions, full Flutter quick verification, isolated PostgreSQL migration/constraint tests, Android build, Windows build, complete diff/gate review, and final merge-eligibility/protection readback.

No physical-device acceptance is required.

## Handoff

SP-003 is complete only after the latest reviewed PR revision passes all applicable hosted gates, the separate review is recorded, the PR merges through protected `main`, and post-merge CI succeeds.

After SP-003, stop for owner continuation. SP-004 owner authorization/bounded API and SP-005 controlled CSV import remain separate future tasks.


## CI latency optimization — Issue #9

Before SP-004, CI optimization is being benchmarked against post-SP-003 run 36033756966 (~6m46s wall clock).

The candidate keeps every existing full gate but:
- uses the current Python 3.12 patch rather than forcing 3.12.9;
- runs Quality, Schema, Android, and Windows in parallel after Change scope;
- disables the oversized Flutter SDK/pub cache restore on Windows while retaining Linux Flutter/Gradle caching;
- keeps Required verification fail-closed over all existing gate results.

Only measured improvements that preserve verification strength are eligible to merge.
