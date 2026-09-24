# Decision 0003 — Versioned product identity and source preservation

Status: Accepted for SP-003
Date: 2026-09-24

## Context

The corrected source has 23,750 rows and several source identifiers. Names and prices are mutable, barcodes are optional, and barcode collisions exist across distinct rows. Unsupported source fields must be preserved without inventing application semantics.

## Decision

- Generate UUID `products.id` as application identity.
- Preserve `source_id`, `source_item_id`, `source_num`, source purchase amount, a versioned dataset key, and full raw JSONB provenance.
- Keep canonical barcodes nullable text with non-unique indexes.
- Store whole-unit selling amount as `bigint` with explicit `SYP` or `USD`.
- Allow zero selling amount only for represented source-import anomalies; ordinary/manual rows require positive amount.
- Start at revision 1 and increment revision in a database trigger on every accepted update. SP-004 owns atomic expected-revision authorization/API behavior.
- Do not deploy or import production data in SP-003.

## Consequences

Identity survives catalog edits, barcode ambiguity remains representable, and every source column is retained without turning unsupported fields into editable application behavior.
