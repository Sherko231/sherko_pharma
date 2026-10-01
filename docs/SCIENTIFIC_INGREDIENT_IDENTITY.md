# Scientific Ingredient Identity Layer

Status: SP-039 repository schema design. Migration 0017 is not deployed to production by this task.
Task: Issue #101
Branch-start SHA: `358d0129997ddc59edf074a6434da864849d2b9c`

## Purpose

SP-039 implements the separate private scientific identity model required by the SP-038 canonicalization contract. It sits above the stable SP-025 lexical ingredient registry and below any future consumer such as deterministic cleanup, curated synonyms, or later provider/equivalence work.

This layer does not replace or rewrite:

- `public.products.composition` or `public.products.strength`;
- `app_private.catalog_ingredients` or its SP-025 IDs;
- SP-026 ingredient-strength derivations;
- SP-027 pharmaceutical-equivalence keys;
- Interaction Checker provider mappings.

No current runtime RPC or Flutter code consumes this layer in SP-039.

## Schema

Migration `backend/migrations/0017_scientific_ingredient_identity.sql` adds the following private objects.

### Canonical identities

`app_private.scientific_ingredients` owns stable internal scientific IDs and stores:

- reviewed preferred scientific name;
- punctuation-preserving scientific equality key;
- category: medicinal substance, vitamin, mineral, botanical, biologic, probiotic, mixture, or other;
- optional parent scientific identity;
- explicit relationship such as salt, ester, hydrate, solvate, derivative, or component.

Parent and relation must be present together. Direct self-parenting and longer parent cycles are rejected. A salt/base relationship is represented explicitly rather than collapsing the two identities.

`app_private.scientific_name_key(text)` performs only equality-safe normalization for curated names: Unicode NFKC, lower-case comparison, trimming, and whitespace collapse. It deliberately preserves punctuation because punctuation can carry chemical meaning. The broader search-oriented `catalog_search_normalize()` is not used as scientific identity truth.

### References and classification

`app_private.scientific_ingredient_references` stores reviewed external identity references. Supported reference-system labels are WHO INN, FDA UNII/GSRS, RxNorm, PubChem, and `other`. One external `(system, key)` can identify only one Sherko scientific identity.

`app_private.scientific_ingredient_atc_codes` stores optional reviewed ATC classification metadata. ATC remains classification metadata and is not an identity authority or evidence of equivalence.

### Reviewed aliases

`app_private.scientific_ingredient_aliases` stores reviewed aliases with source/version/review provenance. One normalized reviewed alias resolves to one scientific identity. Candidate or fuzzy aliases are not accepted here automatically.

### SP-025 to scientific mapping

`app_private.catalog_ingredient_scientific_mappings` links one stable SP-025 lexical ingredient identity to the scientific layer without renumbering or rewriting SP-025.

Statuses follow the SP-038 contract:

- `verified`: reviewed scientific identity is accepted; confidence is 100 and review/source provenance is required.
- `candidate`: one unreviewed candidate identity is retained; confidence is 1–99 and it is not scientific truth.
- `needs_review`: no identity is accepted; conflicting/multiple/context-dependent possibilities remain explicit and require a nonblank review note.
- `unresolved`: no accepted identity exists; method is `none`, confidence is 0, and a review note is required. `reviewed_at` may be populated when a human review still concludes that the source cannot be resolved.

Mapping methods are `exact_reference`, `reviewed_alias`, `deterministic_cleanup`, `context`, `manual`, and `none`. A method other than `none` requires a reference/rule source.

### Multiple review candidates

`app_private.catalog_ingredient_scientific_review_candidates` stores multiple explicit possible scientific identities for a `needs_review` SP-025 mapping. The composite foreign key prevents these candidate rows from surviving after the parent mapping is moved out of `needs_review`; curation must clear the ambiguity before marking a mapping verified/candidate/unresolved.

This supports overloaded tokens such as `K` without choosing potassium, Vitamin K, or another meaning globally.

## Access boundary

All six new tables are in `app_private`, have RLS enabled as defense in depth, and revoke direct privileges from `public`, `anon`, and `authenticated`. The helper functions also revoke direct execution from those roles.

SP-039 adds no public RPC and does not broaden the Data API surface.

## Regression contract

`backend/tests/015_scientific_ingredient_identity_test.sql` uses synthetic fixtures and a transaction rollback to cover:

- `DIPHENHYDRAMINE HCL` retaining its raw composition and SP-025 lexical identity while linking to `Diphenhydramine hydrochloride` with parent `Diphenhydramine` and `salt_of`;
- `PARACETAMOL` linking to a canonical identity with reviewed INN and optional ATC metadata;
- overloaded `K` remaining `needs_review` while retaining two explicit candidate identities;
- a reviewed unresolved botanical remaining unmapped rather than guessed;
- existing SP-027 pharmaceutical-equivalence state remaining byte-for-byte JSON-equivalent before/after scientific curation rows;
- scientific-name punctuation preservation;
- canonical-name, external-reference, and reviewed-alias uniqueness;
- direct/indirect parent-cycle rejection;
- invalid mapping-state shapes being rejected;
- review candidates blocking premature resolution;
- no direct `anon`/`authenticated` CRUD privileges and RLS enabled on every new table.

## Deployment boundary

SP-039 is repository-only. Migration 0017 is not applied to the hosted Sherko Pharma project by this task, and no catalog backfill occurs.

SP-040 may build deterministic cleanup/abbreviation candidates against this schema. SP-041 may curate scientifically reviewed aliases/mappings. Production-wide derived-state population remains reserved for SP-044 and requires fresh explicit owner authorization immediately before that write.
