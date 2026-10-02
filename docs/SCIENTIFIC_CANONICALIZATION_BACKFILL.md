# Scientific Canonicalization Backfill

Status: SP-044 production backfill completed and verified on 2026-10-02.
Task: Issue #106
Branch-start SHA: `9567c5da2156715022a8b5e4b4bd47f50d20af3a`
Canonicalization version: `1`

## Purpose

SP-044 persists the reviewed scientific canonicalization pipeline as a private, versioned derived layer over the existing catalog. It does not rewrite authoritative catalog text. `public.products.composition` and `public.products.strength` remain source/display fields, and product IDs, barcodes, selling amounts/currencies, revisions, SP-025 identities, SP-026/SP-027 state, orders and Flutter runtime remain independent.

## Owner authorization and deployment path

The owner explicitly authorized the production scientific backfill after the isolated environment was unavailable. Large migration payloads were deployed through smaller recorded migrations, with repository reconciliation migrations proving that the split production path and repository end-state converge.

Production contains the SP-039 through SP-044 scientific layer, including:

- scientific ingredient identities, reviewed references/aliases and ambiguity states;
- deterministic cleanup and embedded-strength parsers;
- complex-composition parser entrypoints;
- versioned product canonicalization nodes and product summaries;
- private refresh functions and composition/strength sync behavior;
- the completed catalog backfill for canonicalization version 1.

Normal `anon` and `authenticated` roles cannot directly execute the private refresh/parser functions or read the private canonicalization tables.

## Scientific acceptance rule

Deterministic text cleanup is never scientific truth by itself.

An SP-025 lexical ingredient is persisted as `verified` only when the deterministic candidate resolves through reviewed SP-041 evidence. Exact reviewed aliases use `mapping_method = reviewed_alias`; exact canonical names require reviewed scientific reference provenance and use `mapping_method = exact_reference`. Both require confidence `100` and a review timestamp.

Product nodes are persisted as `trusted` only when the same reviewed provenance exists. Otherwise a structurally deterministic candidate remains `high_confidence`, `needs_review` or `unresolved` as appropriate.

## Production baseline and preservation

Immediately before the authorized write:

- products: 23,750;
- products with nonblank composition: 17,840;
- SP-025 lexical ingredients: 2,358;
- SP-025 product-component rows: 25,840;
- SP-025 composition-normalization rows: 23,750.

Post-deployment fingerprints exactly matched the pre-deployment baseline for authoritative raw composition/strength, commercial identity/barcode/price/revision state, the SP-025 ingredient registry, SP-025 product components and SP-025 composition normalization.

The backfill transaction captured before-state snapshots and aborted if those preserved domains changed unexpectedly. No invariant fired.

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

The largest review/unresolved categories are blank composition, unreviewed numeric/formula tokens, standalone abbreviations/formulas, structural syntax, botanical/extract identity review, parenthesized structure review, ambiguous short tokens and bare-mineral form ambiguity.

## Idempotence

A production same-version rerun of `refresh_all_scientific_canonicalization()` was executed after the backfill. Fingerprints of ingredient scientific mappings, product canonicalization summaries and product canonicalization nodes, including their derived timestamps, were identical before and after the rerun. Canonicalization version 1 is therefore verified idempotent for the deployed state.

## Parser acceptance verification

Before the backfill, the completed complex-composition parser was checked with synthetic acceptance examples covering grouped expressions, alternate names, overloaded tokens and malformed unmatched-parenthesis input. Structure and scientific identity states remained separated as designed.

## Security and performance review

Supabase advisors were run after deployment. Private scientific tables intentionally expose no normal-client policies/privileges. Existing public catalog security warnings outside the scientific task remain separate work.

Performance advisors reported informational unindexed-FK/unused-index notices. Version cardinality is currently one and no performance regression was observed during the one-time backfill; index tuning remains a separate optimization task.

## Verification limitation

`backend/tests/020_scientific_canonicalization_backfill_test.sql` was not executed in its original isolated rollback-fixture mode because the session had no local PostgreSQL/Docker/Supabase runtime. Production verification instead used parser acceptance checks, migration-embedded preservation/provenance invariants, before/after fingerprints, aggregate coverage, advisor review, reconciliation migrations and a successful same-version idempotence rerun.

## Reproducibility

- Aggregate coverage query: `backend/audits/sp044_scientific_canonicalization_coverage.sql`.
- Main backfill definition: `backend/migrations/0022_scientific_canonicalization_backfill.sql`.
- Split-rollout convergence checks: `backend/migrations/0021b_sp043_production_reconciliation.sql` and `backend/migrations/0022b_sp044_production_reconciliation.sql`.
- Rollback regression fixture: `backend/tests/020_scientific_canonicalization_backfill_test.sql`.

No production catalog dump, product names, barcodes, prices, account identifiers or source CSV are committed by SP-044.
