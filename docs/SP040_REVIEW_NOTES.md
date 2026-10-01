# SP-040 Review Notes

Task: Issue #102
Branch: `sp040/deterministic-composition-cleanup`
Base: `515e914674cf546a358cc64b82b2878808ea8e49`

## Pre-PR review findings resolved

1. **Compact chemical formula casing** — the first draft's generic display-case cleanup could have changed `NaCl` to `Nacl`. The cleanup function now detects compact element-symbol formula shapes and returns them unchanged as `needs_review`. A focused `NaCl` regression was added.
2. **Microgram Unicode normalization** — Unicode NFKC changes MICRO SIGN `µ` to GREEK SMALL LETTER MU `μ`. The embedded-strength detector now accepts both `µg` and `μg`, and a regression proves `LEVOTHYROXINE 25µg` remains quarantined for SP-042 after normalization.

## Read-only PostgreSQL expression checks

SELECT-only checks against the hosted PostgreSQL 17 project confirmed:

- NFKC normalization syntax and behavior;
- camelCase replacement backreferences;
- terminal HCL replacement;
- `NaCl` compact-formula detection while all-caps `HCL` remains outside that formula-shape detector;
- `VIT.B3` token-pattern matching;
- `25µg` normalizes to `25μg` and remains detected by the updated embedded-strength pattern.

These checks did not create functions, types, tables, migrations, rows, or derived catalog state.

## Verification limitation

The repository regression `backend/tests/016_deterministic_composition_cleanup_test.sql` has not been executed in a local Supabase/PostgreSQL stack in this session because no local Postgres/Supabase CLI/Docker runtime is available. Production is intentionally not used to execute migration 0018 or rollback DDL because SP-040 does not authorize production deployment.

No known blocking review finding remains before PR creation.
