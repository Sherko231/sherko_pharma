# Scientific Canonicalization Backfill

Status: SP-044 repository implementation prepared; production deployment requires fresh explicit owner authorization immediately before the write.
Task: Issue #106
Branch-start SHA: `9567c5da2156715022a8b5e4b4bd47f50d20af3a`
Canonicalization version: `1`

## Purpose

SP-044 is the first task in the SP-038–SP-044 sequence allowed to persist reviewed scientific canonicalization into production-derived state.

It does not rewrite authoritative catalog text. `public.products.composition` and `public.products.strength` remain source/display fields. Existing product IDs, barcodes, selling amounts/currencies, revisions, SP-025 lexical identities, SP-026 strength state, SP-027 equivalence state, DDI provider mappings, Cart/order behavior and Flutter runtime remain independent and unchanged.

## Versioned derived model

Migration `backend/migrations/0022_scientific_canonicalization_backfill.sql` introduces:

- `scientific_canonicalization_versions` — records the canonicalization version and the SP-040/SP-042/SP-043 rule/parser versions it depends on;
- `product_scientific_canonicalization_nodes` — preserves SP-043 node/group provenance plus reviewed scientific identity, embedded-strength metadata and machine-readable reasons;
- `product_scientific_canonicalization` — one aggregate derived row per product, including source fingerprint, structure/identity status counts, alias resolution count and embedded-strength comparison;
- private refresh/sync functions for one lexical ingredient, one product, or the full derived layer;
- an automatic private sync trigger for future composition/strength edits.

All new tables/functions remain private from `public`, `anon` and `authenticated` direct access.

## Scientific acceptance rule

SP-044 does not treat deterministic cleanup as scientific truth.

An SP-025 lexical ingredient receives `verified` scientific mapping only when:

1. SP-040 produces a deterministic candidate;
2. that candidate resolves exactly through the reviewed SP-041 canonical/alias registry; and
3. the resolution has reviewed provenance.

Exact reviewed aliases use `mapping_method = reviewed_alias`. Exact canonical names require a reviewed scientific reference and use `mapping_method = exact_reference`. Both require confidence `100` and a review timestamp.

The same provenance rule is rechecked at product-node persistence time. SP-043 may structurally recognize an exact canonical scientific name, but SP-044 persists it as `trusted` only when the resolved alias itself has reviewed source metadata or the canonical identity has at least one reviewed scientific reference. A canonical registry row without reviewed reference evidence is downgraded to `high_confidence` with reason code `scientific_identity_missing_reviewed_provenance`.

Everything else remains explicit `needs_review` or `high_confidence` with no accepted canonical scientific identity. Existing manually verified scientific mappings, if ever curated later, are preserved by the same-version refresh rather than overwritten.

## Product-level derivation

Product parsing runs directly from the raw composition text through SP-043 so the derived layer can represent cases that the older flat SP-025 component model intentionally could not express.

This includes:

- grouped expressions and parent paths;
- parenthesized alternate names;
- reviewed alias resolution;
- embedded strength/presentation metadata from SP-042;
- strength comparison against the separate source `products.strength` value;
- explicit `trusted`, `high_confidence`, `needs_review` and `unresolved` component states;
- machine-readable unresolved/review reason codes.

`trusted` requires reviewed scientific provenance at SP-044 persistence time. A structurally deterministic but unreviewed substance name remains only `high_confidence`.

## Idempotence

Canonicalization version `1` is content-addressed by raw composition + raw strength plus explicit upstream rule versions.

For a product whose source fingerprint and parser/canonicalization versions have not changed, refresh is a no-op. Existing node rows and `normalized_at` remain unchanged.

Global lexical-ingredient mappings use an `ON CONFLICT ... WHERE ... IS DISTINCT FROM` update, so a same-version rerun does not change `updated_at` when the reviewed result is identical.

A future change to cleanup rules, reviewed scientific references/aliases, embedded parser behavior or complex parser behavior must ship under a new canonicalization version before a production refresh.

## Backfill invariants

The migration snapshots authoritative/upstream state before the backfill and aborts if it detects changes to:

- raw composition or strength;
- barcodes;
- selling amount/currency;
- product revision or `updated_at`;
- SP-025 ingredient/component/composition-normalization state;
- Interaction Checker global mappings or product-component overrides.

It also rejects any persisted `verified`/`trusted` scientific row without reviewed scientific identity/provenance.

## Coverage reporting

`backend/audits/sp044_scientific_canonicalization_coverage.sql` returns aggregate-only metrics required by Issue #106:

- mapped canonical lexical ingredient count;
- reviewed synonym/alias-resolved ingredient count;
- review-required/unresolved ingredient counts;
- fully trusted product coverage among nonblank compositions;
- reviewed alias-resolved product/component counts;
- embedded-strength cleanup product/component counts;
- product structure/identity status buckets;
- embedded/source-strength comparison buckets;
- unresolved/review reason-code counts.

The report intentionally emits no product names, raw compositions, barcodes, prices, source payloads, account identifiers or full ingredient list.

## Verification sequence

Before any production deployment:

1. review the final repository diff;
2. run migrations 0017–0022 plus `backend/tests/020_scientific_canonicalization_backfill_test.sql` in an isolated or rollback path;
3. confirm same-version idempotence, reviewed-provenance trust enforcement and raw/SP-025/DDI preservation;
4. obtain fresh explicit owner authorization immediately before the production write.

After deployment:

1. run the aggregate SP-044 coverage report;
2. compare raw composition/strength and commercial-identity fingerprints with the read-only pre-deployment baseline;
3. confirm SP-025 and DDI counts/fingerprints are unchanged;
4. record exact coverage metrics and representative unresolved categories in the Issue/PR/documentation.

## Current verification environment note

The current agent runtime has no local PostgreSQL, Docker or Supabase CLI. A raw production transaction containing repository DDL was rejected by the Supabase tool safety layer even though it was intended to end in `ROLLBACK`. The official Supabase isolated-branch alternative currently reports a cost of `$0.01344/hour`; creating it requires separate owner cost approval. No production write occurred while establishing this limitation.

## Current production boundary

Before SP-044 deployment, production remains deployed through the DDI migration sequence ending at repository migration 0016. Repository migrations 0017–0022 are not production state until the owner explicitly authorizes and the deployment is actually performed.
