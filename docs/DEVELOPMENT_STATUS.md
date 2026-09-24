# Sherko Pharma — Development Status

Updated: 2026-09-24
Active task: [SP-004 / Issue #11](https://github.com/Sherko231/sherko_pharma/issues/11).
Branch: `feat/sp-004-owner-catalog-api`.
Status: Owner authorization and bounded catalog API implementation in progress; no production Supabase deployment or owner UUID provisioning has been performed.

## Verified baseline

- Protected `main` was `54250d2729161331d34a484726d6d80d8c50ffc4` when SP-004 started.
- SP-000 through SP-003 are merged.
- CI latency optimization Issue #9 / PR #10 is merged; post-merge run 36038748320 passed.
- No open Issue or PR existed before SP-004 was authorized.
- No production Supabase project state, credentials, source import, Flutter sign-in, catalog UI, order UI, or scanner behavior is deployed by this task.

## SP-004 contract

- An environment-provisioned owner Auth UUID is stored privately server-side; no real owner UUID is committed.
- Normal `anon` and `authenticated` roles cannot directly read/write `products`.
- Public catalog RPC execution is denied; authenticated RPCs still perform a server-side owner UUID check.
- Bounded search covers Arabic/English names and composition with literal-text matching and a hard 50-row cap.
- Exact barcode lookup checks both text columns and preserves distinct ambiguous product matches.
- Create/update inputs expose canonical editable fields only; provenance and revision remain server-owned.
- Update uses an atomic expected-revision predicate and rejects stale writes.
- Versioned Supabase Auth config disables general, anonymous, email, and SMS signup.
- Tests use synthetic roles/users/data only.

## Verification

Final evidence requires the full existing Quality, Schema, Android, Windows, and Required verification gates. Schema now additionally applies all migrations in order and tests anonymous/non-owner/owner/direct-access/search/barcode/create/update/concurrency behavior plus signup configuration.

No physical-device acceptance applies. Production deployment and actual owner account provisioning remain explicit future deployment work.
