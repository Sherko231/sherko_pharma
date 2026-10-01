# Scientific Canonicalization Backfill

> Deployment status override — 2026-10-01: the owner explicitly authorized skipping isolated verification and deploying directly to production. Migration 0017 / SP-039 was applied successfully. Migration 0018 / SP-040 was then blocked twice by the Supabase/OpenAI tool safety layer before PostgreSQL execution. Migrations 0019–0022 were not attempted because they depend on 0018. The SP-039 production tables remain empty and private; no catalog backfill has occurred.

Status: SP-044 production deployment is partially started and stopped safely at the dependency boundary described above.
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

## Verification and deployment record

Pre-deployment read-only baseline immediately before the authorized write:

- products: 23,750;
- nonblank compositions: 17,840;
- SP-025 lexical ingredients: 2,358;
- SP-025 component rows: 25,840;
- SP-025 composition-normalization rows: 23,750;
- Interaction Checker global mappings: 2,358;
- Interaction Checker component overrides: 6.

The owner explicitly authorized bypassing the unavailable isolated/rollback environment and requested immediate production deployment.

Deployment result so far:

1. 0017 / `sp039_scientific_ingredient_identity` — applied successfully to production.
2. 0018 / `sp040_deterministic_composition_cleanup` — blocked by the execution safety layer before database execution on both the initial and exact-repository attempts.
3. 0019–0022 — not attempted because they depend on 0018.
4. Production inspection confirms the SP-039 type exists, the SP-040 type/function do not exist, scientific identity/mapping tables contain zero rows, and `anon`/`authenticated` still lack direct access to the private schema/table.

Do not attempt 0019–0022 until 0018 is successfully applied. Once the chain completes, run the aggregate coverage report and compare raw/commercial/SP-025/DDI fingerprints against the captured baseline before merging PR #118.
