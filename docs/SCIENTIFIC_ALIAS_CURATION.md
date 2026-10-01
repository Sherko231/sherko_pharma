# Reviewed Scientific Alias Curation

Status: SP-041 repository implementation. Migration 0019 is not deployed to production by this task.
Task: Issue #103
Branch-start SHA: `c7ecf6a48e8bfcf94b4d57bceb406454e6711922`
Review date: 2026-10-01

## Purpose

SP-041 adds reviewed semantic aliases above the SP-040 deterministic text-cleanup stage and the SP-039 scientific identity schema.

The purpose is to let an explicitly reviewed spelling, historical/local name, or established scientific synonym resolve to one canonical Sherko scientific identity without rewriting the observed SP-025 lexical identity or the raw catalog composition.

This layer is not a fuzzy matcher. String similarity, AI output, edit distance, provider matching, or a plausible-looking drug name can nominate a review candidate, but none of those mechanisms can insert an accepted alias automatically.

## Registry and exact resolver

Migration `backend/migrations/0019_reviewed_scientific_aliases.sql` uses the existing private SP-039 table `app_private.scientific_ingredient_aliases` as the accepted alias registry and adds:

- `app_private.resolve_reviewed_scientific_alias(text)` — an exact scientific-name-key resolver;
- `app_private.guard_scientific_alias_canonical_collision()` — prevents an alias from claiming another identity's canonical name;
- `app_private.guard_scientific_canonical_alias_collision()` — prevents a later canonical name from claiming a reviewed alias already owned by another identity.

The resolver accepts only equality under `scientific_name_key()`: Unicode NFKC, case folding and whitespace normalization while preserving punctuation. It performs no fuzzy search, typo generation, transliteration, therapeutic matching, class matching, salt/base collapse, or provider lookup.

The private resolver returns the canonical identity plus alias provenance when the match came from a reviewed alias. Normal `public`, `anon`, and `authenticated` roles cannot execute it directly.

## Curated seed set

The migration seeds only a small reviewed global reference set. It does not map any production SP-025 ingredient rows.

| Reviewed source text | Canonical scientific identity | Alias kind | Evidence |
| --- | --- | --- | --- |
| `Amoxicilline` | `Amoxicillin` | legacy name / spelling variant | PubChem CID 33613 lists `Amoxicilline` as a synonym/MeSH entry term |
| `Amoxycillin` | `Amoxicillin` | synonym | PubChem CID 33613 lists `Amoxycillin` as a synonym/MeSH entry term |
| `caféine` | `Caffeine` | local name | ChEBI CHEBI:27732 records French `caféine` for caffeine |
| `cafeine` | `Caffeine` | legacy name | PubChem SID 8144467 explicitly lists `cafeine` for caffeine |
| `Acetaminophen` | `Paracetamol` | common name | PubChem CID 1983 lists both names for the same compound and reports INN `PARACETAMOL` |

The canonical reference identities seeded by this task are `Amoxicillin`, `Caffeine`, and `Paracetamol` only. This is an acceptance/reference set, not an attempt to curate the full Syrian catalog in one migration.

## External evidence

Reviewed sources checked on 2026-10-01:

- PubChem Amoxicillin, CID 33613: https://pubchem.ncbi.nlm.nih.gov/compound/33613
- PubChem Caffeine, CID 2519: https://pubchem.ncbi.nlm.nih.gov/compound/2519
- PubChem Caffeine substance record, SID 8144467: https://pubchem.ncbi.nlm.nih.gov/substance/8144467
- ChEBI Caffeine, CHEBI:27732: https://www.ebi.ac.uk/chebi/searchId.do?chebiId=CHEBI%3A27732
- PubChem Acetaminophen/Paracetamol, CID 1983: https://pubchem.ncbi.nlm.nih.gov/compound/1983

Each accepted alias row records a source, source/retrieval version, review timestamp, and review note. Supporting canonical identity references are also stored in `scientific_ingredient_references`.

## Collision policy

A reviewed alias is global scientific identity data, so one normalized alias key cannot silently mean two different scientific identities.

SP-039 already makes `scientific_ingredient_aliases.normalized_alias` a primary key. SP-041 adds the missing cross-table protection:

- alias `X -> identity A` is rejected if `X` is already the canonical preferred name of identity B;
- a new/renamed canonical identity B is rejected if its preferred name is already a reviewed alias owned by identity A;
- an existing reviewed alias key cannot be inserted again for another identity.

Because canonical names and aliases are stored in separate tables, both collision guards take a transaction-scoped PostgreSQL advisory lock derived from the normalized scientific-name key before checking the opposite table. Concurrent curation of the same key is therefore serialized rather than relying on a race-prone check-then-write sequence.

Collision rejection uses a uniqueness-style database error. It does not choose a winner and it does not downgrade either identity automatically. A curator must resolve the evidence explicitly.

## Ambiguity policy

`VIT.B3` remains intentionally unresolved at the semantic layer. SP-040 may format it as `Vitamin B3`, but SP-041 does not add `VIT.B3` or `Vitamin B3` as an alias of niacin/nicotinic acid, nicotinamide, or another single chemical identity because the source shorthand is not sufficiently specific.

The same principle applies to overloaded one-letter/mineral/vitamin tokens and other context-dependent source forms. Product-specific context belongs to an explicit reviewed mapping/override path, not a global scientific alias.

## Relationship to SP-025 and SP-040

A source product containing `amoxicilline` still keeps:

- raw `products.composition = 'amoxicilline'`;
- its existing SP-025 lexical ingredient identity and observed spelling;
- the SP-040 cleanup candidate `Amoxicilline`.

Only after explicit reviewed alias lookup can that candidate resolve to canonical `Amoxicillin`. The lookup itself is side-effect-free and does not persist `catalog_ingredient_scientific_mappings` rows.

This separation keeps observed source data auditable and prevents a cleanup/fuzzy rule from becoming medical truth merely because it resembles a known medicine name.

## Regression contract

`backend/tests/017_reviewed_scientific_aliases_test.sql` covers:

- `amoxicilline -> Amoxicillin` only through a reviewed alias with provenance;
- `Amoxycillin -> Amoxicillin`;
- `cafeine -> Caffeine` and exact accented `caféine -> Caffeine`;
- `Acetaminophen -> Paracetamol`;
- canonical-name exact resolution;
- no auto-acceptance of fuzzy `amoxicilin`;
- no `VIT.B3` / `Vitamin B3` semantic collapse;
- SP-040 candidate handoff into exact reviewed alias lookup;
- unchanged raw SP-025 spelling/identity and no persisted product scientific mapping;
- alias↔canonical and alias↔alias collision rejection;
- required provenance/review timestamp on accepted aliases;
- no direct client execution of the private resolver or either collision guard.

## Deployment boundary

SP-041 is repository-only. Migration 0019 is not applied to the hosted Sherko Pharma project by this task. Hosted production remains deployed through migration 0016; repository migrations 0017–0019 remain unapplied there.

No production product row, raw composition, raw strength, SP-025 lexical identity, SP-026 strength mapping, SP-027 equivalence key, DDI provider mapping, Cart behavior, or Flutter runtime is changed.

SP-042 may consume the existing deterministic cleanup boundary for embedded-strength/presentation extraction. SP-043 may combine reviewed aliases with complex structural parsing. SP-044 remains the first task allowed to backfill reviewed scientific canonicalization state into production and still requires fresh explicit owner authorization immediately before that write.
