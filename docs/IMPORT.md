# Controlled initial catalog import

SP-005 provides a private-source import workflow for the approved corrected `sy-database(2).csv`. The source CSV and generated source-containing SQL are operator inputs, not repository assets.

## Versioned source contract

The repository stores only [the non-sensitive import contract](../backend/imports/initial_catalog_contract.json):

- SHA-256: `2923fffd24e8aaee0cda7549458aec680f6ee67b50925b93ff540c2c755029a4`
- rows: 23,750
- headers: the exact 25-column SP-003 mapping
- initial selling currency: `SYP`
- source dataset key includes the full approved fingerprint

A changed file, header order, row count, encoding/BOM contract, or unsupported currency fails before SQL generation or database access.

## Dry-run first

From the repository root:

```text
python tool/catalog_import.py dry-run --source "/private/path/sy-database(2).csv"
```

Dry-run validates every row and prints aggregate accounting plus row-number/error-code diagnostics. It does not print product payloads or contact a database.

The verified owner source dry-run on 2026-09-24 produced:

- 23,750 valid rows and 0 invalid rows;
- 423 zero selling-price source anomalies;
- 8,260 blank primary barcodes;
- 22,495 blank secondary barcodes;
- seven duplicated nonempty primary codes;
- one duplicated nonempty secondary code;
- 13 barcode codes that resolve to more than one distinct source row.

These values match the SP-003 source analysis.

## Generate reviewed SQL

For an explicit reviewable local file:

```text
python tool/catalog_import.py emit-sql \
  --source "/private/path/sy-database(2).csv" \
  --output "import_working_dir/catalog-import.sql"
```

The generated SQL contains private source data. On POSIX systems the tool creates/restricts it to mode `600`. Keep it out of Git, logs, shared folders, and CI artifacts; delete it when no longer needed.

The SQL:

- preserves both barcode fields as exact text and converts only an empty CSV cell to SQL NULL;
- preserves all 25 original source fields in `source_payload`;
- assigns the source `price` to whole-unit `selling_amount` with explicit `SYP`;
- keeps `purchasePrice` as provenance only;
- inserts by the immutable source dataset/source ID identity;
- uses `ON CONFLICT (source_dataset, source_id) DO NOTHING`, so a rerun cannot replace a later owner edit;
- inserts missing approved rows on a partial rerun;
- rejects rows already using the dataset key with source IDs outside the approved source;
- verifies the final dataset row count before commit.

## Apply only to an explicit target

No Sherko Pharma hosted Supabase environment is provisioned yet, so SP-005 does not run a real source import.

After a dedicated environment is deliberately selected, its schema/auth configuration is verified, and an administrative PostgreSQL connection is available, set the URL in an environment variable rather than a CLI argument:

```text
set SHERKO_IMPORT_DATABASE_URL=postgresql://...
python tool/catalog_import.py apply --source "C:\private\sy-database(2).csv"
```

On shells other than Windows Command Prompt, set the same environment variable using that shell's normal syntax. The tool parses the URL into PostgreSQL environment variables and invokes `psql`; it does not echo or write the connection URL.

A failed transaction is not completion evidence. Record the target environment, final import summary, and post-import verification when a real initial deployment is explicitly authorized.
