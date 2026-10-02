# Reviewed Scientific Alias Curation

Status: SP-041 repository implementation.
Task: Issue #103
Branch-start SHA: `c7ecf6a48e8bfcf94b4d57bceb406454e6711922`
Review date: 2026-10-01

## Purpose

SP-041 adds reviewed semantic aliases above the SP-040 deterministic text-cleanup stage and the SP-039 scientific identity schema.

An explicitly reviewed spelling, historical/local name, or established scientific synonym may resolve to one canonical Sherko scientific identity without rewriting the observed SP-025 lexical identity or raw catalog composition.

String similarity, AI output, edit distance or a plausible-looking drug name may nominate a review candidate, but none can insert an accepted alias automatically.

## Registry and exact resolver

Migration `backend/migrations/0019_reviewed_scientific_aliases.sql` uses `app_private.scientific_ingredient_aliases` as the accepted alias registry and adds exact resolution plus cross-table collision guards.

The resolver accepts only equality under `scientific_name_key()`: Unicode NFKC, case folding and whitespace normalization while preserving punctuation. It performs no fuzzy search, typo generation, transliteration, therapeutic matching, class matching or salt/base collapse.

Normal `public`, `anon`, and `authenticated` roles cannot execute the private resolver directly.

## Curated seed set

| Reviewed source text | Canonical scientific identity | Alias kind |
| --- | --- | --- |
| `Amoxicilline` | `Amoxicillin` | legacy name / spelling variant |
| `Amoxycillin` | `Amoxicillin` | synonym |
| `caféine` | `Caffeine` | local name |
| `cafeine` | `Caffeine` | legacy name |
| `Acetaminophen` | `Paracetamol` | common name |

The canonical reference identities seeded by this task are `Amoxicillin`, `Caffeine`, and `Paracetamol`. Each accepted alias preserves source/version/review provenance.

## Collision and ambiguity policy

One normalized alias key cannot silently mean two different scientific identities. Alias-to-canonical, canonical-to-alias and alias-to-alias collisions are rejected and require explicit curation.

`VIT.B3` remains intentionally unresolved at the semantic layer. SP-040 may format it as `Vitamin B3`, but SP-041 does not choose niacin, nicotinamide or another precise form. The same principle applies to overloaded short/mineral/vitamin tokens and other context-dependent source forms.

## Regression contract

`backend/tests/017_reviewed_scientific_aliases_test.sql` covers reviewed alias resolution, canonical-name resolution, no fuzzy auto-acceptance, no Vitamin B3 semantic collapse, cleanup-to-alias handoff, raw source/SP-025 preservation, collision rejection, required provenance and private-function access denial.

## Deployment boundary

Alias curation changes only the reviewed private scientific layer. It does not rewrite product source fields, SP-025 lexical identities, SP-026 strength state, SP-027 equivalence keys, Cart behavior or Flutter runtime.
