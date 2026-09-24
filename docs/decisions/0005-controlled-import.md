# Decision 0005 — Fingerprinted, insert-only initial catalog import

Status: Accepted for SP-005
Date: 2026-09-24

## Context

The approved corrected source contains 23,750 private catalog rows. Initial import must preserve exact source identity and text while preventing an accidental rerun from overwriting edits made after deployment. There is no dedicated hosted Sherko Pharma Supabase environment yet.

## Decision

- Version a non-sensitive contract containing the exact source SHA-256, row count, ordered headers, dataset key, BOM expectation, and fixed initial currency.
- Require a full dry-run before SQL generation or apply.
- Keep the source CSV and generated source-containing SQL outside the repository and CI artifacts.
- Generate direct administrative inserts only after validation. Normal application roles continue using the SP-004 bounded API.
- Use `(source_dataset, source_id)` as the import idempotency key and `ON CONFLICT DO NOTHING`; the importer never updates an existing source identity.
- Recover missing approved rows on rerun, but reject unexpected source IDs already using the same dataset key.
- Preserve both barcode columns exactly as text, every source field in JSONB provenance, and initial selling prices as integer SYP without conversion.
- Require the database URL through an environment variable for the optional `apply` command; do not accept it as a CLI value or store it in repository configuration.
- Defer real source deployment until a dedicated environment is explicitly targeted and verified.

## Consequences

A repeated import is safe for later owner edits but intentionally does not repair or overwrite an existing imported row. Correcting an already-imported row must use an explicit reviewed catalog/database operation rather than silently changing import semantics.

The generated SQL is intentionally source-containing private material. It is an ephemeral operator artifact, not a build artifact or backup format.
