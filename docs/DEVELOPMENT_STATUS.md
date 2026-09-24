# Sherko Pharma — Development Status

Updated: 2026-09-24
Active task: [SP-005 / Issue #13](https://github.com/Sherko231/sherko_pharma/issues/13).
Branch: `feat/sp-005-controlled-import`.
Status: Controlled import tooling, source contract, synthetic fixtures, and isolated rerun protections are implemented on the task branch; PR verification/review remain pending. No hosted source import has been performed.

## Verified baseline

- Protected `main` was `7b3c0b0e8870a4ddd8bb4a5f107b3e491ed315b4` when SP-005 started.
- SP-000 through SP-004 and CI-001 are merged.
- SP-004 post-merge run 36041436836 passed all required gates.
- No open Issue or PR existed before SP-005 was authorized.
- No dedicated hosted Sherko Pharma Supabase project or production database target is provisioned.

## Real corrected source dry-run

The private `sy-database(2).csv` was retrieved outside Git and revalidated with the SP-005 tool.

- SHA-256 exactly matches `2923fffd24e8aaee0cda7549458aec680f6ee67b50925b93ff540c2c755029a4`.
- 23,750 valid rows; 0 invalid rows.
- 423 zero selling-price source anomalies.
- 8,260 blank `barcode` values; 22,495 blank `barcode2` values.
- Seven duplicated nonempty primary codes; one duplicated nonempty secondary code.
- 13 cross-field barcode codes identify more than one distinct product.
- Initial selling currency is explicitly SYP.
- A reviewed local SQL generation test succeeded; the generated source-containing file was about 25.5 MB and was not committed or uploaded.

## SP-005 implementation

- `backend/imports/initial_catalog_contract.json` locks the approved fingerprint, headers, row count, BOM expectation, dataset identity, and SYP currency.
- `tool/catalog_import.py` provides `dry-run`, private `emit-sql`, and environment-variable-based `apply` modes.
- Invalid rows are reported by CSV row number and error codes without logging full product payloads.
- Exact text barcodes, integer prices, all source identifiers, and the complete 25-column JSONB payload are preserved.
- Import SQL uses insert-only conflict handling, never an update/upsert overwrite.
- Reruns restore missing approved rows while preserving existing rows and later revisions.
- Unexpected source IDs already occupying the same dataset key abort the transaction.
- CI uses only synthetic import data and stores no generated import artifact.

## Verification

The final revision requires Python import regressions plus the existing Quality, Schema, Android, Windows, and Required verification gates. The Schema gate performs a first synthetic import, later edit, missing-row rerun, preservation checks, and unexpected-source rejection against isolated PostgreSQL.

No physical-device acceptance applies. A real source import remains blocked until a dedicated environment is explicitly selected and verified.
