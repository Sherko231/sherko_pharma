# Scientific Ingredient Identity Layer

Status: SP-039 repository schema design.
Task: Issue #101
Branch-start SHA: `358d0129997ddc59edf074a6434da864849d2b9c`

## Purpose

SP-039 implements the separate private scientific identity model required by the SP-038 canonicalization contract. It sits above the stable SP-025 lexical ingredient registry and below deterministic cleanup, curated synonyms, equivalence work and other future consumers.

This layer does not replace or rewrite:

- `public.products.composition` or `public.products.strength`;
- `app_private.catalog_ingredients` or its SP-025 IDs;
- SP-026 ingredient-strength derivations;
- SP-027 pharmaceutical-equivalence keys.

No client runtime RPC or Flutter code is required merely to define the scientific identity schema.

## Schema

Migration `backend/migrations/0017_scientific_ingredient_identity.sql` adds the private scientific identity objects.

### Canonical identities

`app_private.scientific_ingredients` owns stable internal scientific IDs and stores reviewed preferred name, punctuation-preserving equality key, category, optional parent scientific identity and an explicit relationship such as salt, ester, hydrate, solvate, derivative or component.

Parent and relation must be present together. Direct self-parenting and longer parent cycles are rejected. A salt/base relationship is represented explicitly rather than collapsing the identities.

`app_private.scientific_name_key(text)` performs equality-safe normalization for curated names: Unicode NFKC, lower-case comparison, trimming and whitespace collapse while preserving punctuation.

### References and classification

`app_private.scientific_ingredient_references` stores reviewed external identity references. Supported reference-system labels include WHO INN, FDA UNII/GSRS, RxNorm, PubChem and `other`. One external `(system, key)` can identify only one Sherko scientific identity.

`app_private.scientific_ingredient_atc_codes` stores optional reviewed ATC classification metadata. ATC remains classification metadata and is not an identity authority or evidence of equivalence.

### Reviewed aliases

`app_private.scientific_ingredient_aliases` stores reviewed aliases with source/version/review provenance. One normalized reviewed alias resolves to one scientific identity. Candidate or fuzzy aliases are not accepted automatically.

### SP-025 to scientific mapping

`app_private.catalog_ingredient_scientific_mappings` links one stable SP-025 lexical ingredient identity to the scientific layer without renumbering or rewriting SP-025.

Statuses:

- `verified`: reviewed scientific identity accepted; confidence 100 with source/review provenance.
- `candidate`: one unreviewed candidate retained; confidence 1–99 and not scientific truth.
- `needs_review`: no identity accepted; conflicting, multiple or context-dependent possibilities remain explicit.
- `unresolved`: no accepted identity exists; method `none`, confidence 0 and a review note is required.

Mapping methods are `exact_reference`, `reviewed_alias`, `deterministic_cleanup`, `context`, `manual`, and `none`.

### Multiple review candidates

`app_private.catalog_ingredient_scientific_review_candidates` stores explicit possible identities for a `needs_review` SP-025 mapping. The composite foreign key prevents candidate rows from surviving after the parent mapping leaves `needs_review`.

This supports overloaded tokens such as `K` without choosing potassium, Vitamin K or another meaning globally.

## Access boundary

All scientific curation tables are in `app_private`, have RLS enabled as defense in depth, and revoke direct privileges from `public`, `anon`, and `authenticated`. Helper functions also revoke direct execution from those roles.

SP-039 adds no public RPC and does not broaden the Data API surface.

## Regression contract

`backend/tests/015_scientific_ingredient_identity_test.sql` uses synthetic fixtures and transaction rollback to cover:

- a hydrochloride identity retaining the raw source/SP-025 lexical identity while linking to a reviewed precise scientific form and parent base;
- canonical identity with reviewed external reference/classification metadata;
- overloaded `K` remaining `needs_review` with explicit candidate identities;
- a reviewed unresolved botanical remaining unmapped rather than guessed;
- existing SP-027 equivalence state remaining unchanged by scientific curation rows;
- punctuation preservation and uniqueness/collision guards;
- direct/indirect parent-cycle rejection;
- invalid mapping-state shapes being rejected;
- review candidates blocking premature resolution;
- no direct normal-client CRUD privileges and RLS enabled on the new tables.

## Deployment boundary

The scientific schema/backfill is deployed only through separately authorized tasks. Later cleanup, alias curation, parser and backfill work must preserve raw catalog text, SP-025 identities and existing commercial/order behavior.
