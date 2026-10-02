# Scientific Canonicalization Backfill

Status: SP-044 production backfill completed and verified on 2026-10-02.
Task: Issue #106
Branch-start SHA: `9567c5da2156715022a8b5e4b4bd47f50d20af3a`
Canonicalization version: `1`

## Purpose

SP-044 persists the reviewed scientific canonicalization pipeline as a private, versioned derived layer over the existing catalog. It does not rewrite authoritative catalog text. `public.products.composition` and `public.products.strength` remain source/display fields, and product IDs, barcodes, selling amounts/currencies, revisions, SP-025 identities, SP-026/SP-027 state, DDI mappings, orders and Flutter runtime remain independent.

## Owner authorization and deployment path

The owner explicitly authorized skipping the unavailable isolated/rollback environment and deploying directly to production. The hosted migration surface rejected several large payloads, so SP-041, SP-043 and SP-044 were deployed as smaller recorded migrations. Repository reconciliation migrations `0021b_sp043_production_reconciliation.sql` and `0022b_sp044_production_reconciliation.sql` are assertion-only markers proving that the split production path and the repository end-state converge.

Production now contains the SP-039 through SP-044 scientific layer, including:

- scientific ingredient identities, reviewed references/aliases and ambiguity states;
- deterministic cleanup and embedded-strength parsers;
- complex-composition parser entrypoints;
- versioned product canonicalization nodes and product summaries;
- private refresh functions and future composition/strength sync trigger;
- the completed catalog backfill for canonicalization version 1.

Normal `anon` and `authenticated` roles cannot directly execute the private refresh/parser functions or read the private canonicalization tables.

## Scientific acceptance rule

Deterministic text cleanup is never scientific truth by itself.

An SP-025 lexical ingredient is persisted as `verified` only when the deterministic candidate resolves through reviewed SP-041 evidence:

- exact reviewed aliases use `mapping_method = reviewed_alias`;
- exact canonical names require at least one reviewed scientific reference and use `mapping_method = exact_reference`;
- both require confidence `100` and a review timestamp.

Product nodes are persisted as `trusted` only when the same reviewed provenance exists. Otherwise a structurally deterministic candidate remains `high_confidence`, `needs_review` or `unresolved` as appropriate.

## Production baseline and preservation

Immediately before the authorized write:

- products: 23,750;
- products with nonblank composition: 17,840;
- SP-025 lexical ingredients: 2,358;
- SP-025 product-component rows: 25,840;
- SP-025 composition-normalization rows: 23,750;
- Interaction Checker global mappings: 2,358;
- Interaction Checker component overrides: 6.

Post-deployment fingerprints exactly matched the pre-deployment baseline:

| State | Fingerprint |
| --- | --- |
| Raw composition + strength | `2a1259ca63573efaf3374d39105f1c30` |
| Commercial identity / barcode / price / revision state | `89a2ec6461a7bb10a8f2612db747a40c` |
| SP-025 ingredient registry | `edfa8492eaab52c2feaee3a2a8c423e0` |
| SP-025 product components | `6a0d8cd5ae4355e83a8cbe63d1e66ac1` |
| SP-025 composition normalization | `fb308143da45cc046b690d2b80d9d637` |
| DDI ingredient mappings | `f19511eb1cc9d21f9785030241b8c52c` |
| DDI component overrides | `c88fa8ec4312f4cd6b7d13f4196a406a` |

The backfill migration also captured temporary before-state snapshots and aborted automatically if authoritative/commercial product state, SP-025 state or DDI state changed inside the deployment transaction. No invariant fired.

## Production coverage

Canonicalization version 1 produced:

| Metric | Count |
| --- | ---: |
| Lexical ingredient mappings | 2,358 |
| Verified canonical ingredient mappings | 4 |
| Verified reviewed-alias ingredient mappings | 1 |
| Ingredient mappings requiring review | 2,354 |
| Unresolved ingredient mappings | 0 |
| Product canonicalization summaries | 23,750 |
| Products with nonblank composition | 17,840 |
| Fully trusted nonblank products | 468 |
| Fully trusted nonblank product coverage | 2.62% |
| Reviewed-alias-resolved components | 18 |
| Products with reviewed-alias resolution | 18 |
| Embedded-strength/presentation components captured | 863 |
| Products with embedded-strength/presentation capture | 516 |
| Review-required product components | 2,046 |
| Unresolved product components | 5,939 |
| Trusted ingredient nodes | 1,401 |
| Trusted canonical-name nodes | 1,383 |
| Trusted reviewed-alias nodes | 18 |

Product status buckets:

- deterministic / high-confidence: 16,202;
- deterministic / needs-review: 752;
- deterministic / trusted: 468;
- needs-review structure / high-confidence identity: 79;
- needs-review structure / needs-review identity: 309;
- needs-review structure / trusted identity: 1;
- unresolved / unresolved: 5,939.

Embedded/source-strength comparison:

- matches: 26;
- conflicts: 30;
- source missing: 320;
- source unparseable: 6;
- not comparable: 23,368.

The largest review/unresolved categories are blank composition (5,910 components), unreviewed numeric/formula tokens (777), standalone abbreviations/formulas (651), structural syntax (282), botanical/extract identity review (278), parenthesized structure review (208), ambiguous short tokens (190), and bare-mineral form ambiguity (95). Smaller explicit categories remain available in the aggregate coverage query.

## Idempotence

A production same-version rerun of `refresh_all_scientific_canonicalization()` was executed after the backfill. Fingerprints of:

- `catalog_ingredient_scientific_mappings` including `updated_at`;
- `product_scientific_canonicalization` including `normalized_at`;
- `product_scientific_canonicalization_nodes` including `normalized_at`;

were identical before and after the rerun. Canonicalization version 1 is therefore verified idempotent for the deployed state.

## SP-043 acceptance verification

Before the SP-044 backfill, the completed production SP-043 parser was checked read-only with synthetic acceptance examples:

- grouped `ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)` -> deterministic structure, three high-confidence/unverified ingredient identities;
- `DICYCLOMINE HCL (DICYCLOVERINE HCL)` -> one needs-review ingredient rather than two automatic ingredients;
- `K` and `VIT.B3` -> deterministic structure but scientific identity `needs_review`;
- malformed unmatched-parenthesis input -> unresolved structure and identity.

## Security and performance review

Supabase advisors were run after deployment.

Security advisor output contains the expected `RLS enabled, no policy` INFO findings for private scientific tables. These tables intentionally have no client policies and direct privileges are revoked from `anon`/`authenticated`; reconciliation checks confirmed that access remains denied. Existing public catalog SECURITY DEFINER warnings and the pre-existing `public.set_product_revision` search-path warning are outside SP-044 scope.

Performance advisors report informational unindexed-FK/unused-index notices. Two new notices concern the canonicalization-version foreign keys on the new private product tables. Version cardinality is currently one and no performance regression was observed during the one-time backfill; index tuning remains a separate optimization task rather than part of the scientific-data contract.

Advisor references:

- https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

## Verification limitation

`backend/tests/020_scientific_canonicalization_backfill_test.sql` was not executed in its original isolated rollback-fixture mode because this session had no local PostgreSQL/Docker/Supabase runtime and the production raw-DDL rollback bundle was rejected before execution. The owner explicitly authorized direct production deployment instead.

Production verification that was actually executed includes the SP-043 synthetic parser checks, the migration-embedded preservation/provenance invariants, exact before/after fingerprints, exact aggregate coverage, security/performance advisors, assertion-only reconciliation migrations, and a successful same-version idempotence rerun.

## Reproducibility

- Aggregate coverage query: `backend/audits/sp044_scientific_canonicalization_coverage.sql`.
- Main backfill definition: `backend/migrations/0022_scientific_canonicalization_backfill.sql`.
- Split-rollout convergence checks: `backend/migrations/0021b_sp043_production_reconciliation.sql` and `backend/migrations/0022b_sp044_production_reconciliation.sql`.
- Rollback regression fixture retained for future isolated environments: `backend/tests/020_scientific_canonicalization_backfill_test.sql`.

No production catalog dump, product names, barcodes, prices, account identifiers or source CSV are committed by SP-044.