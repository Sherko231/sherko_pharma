# Complex Composition Parsing

Status: SP-043 repository implementation.
Task: Issue #105
Branch-start SHA: `b008605177abbbdfb06d763bc7a2da0ab1f1df8f`
Parser version: `1`

## Purpose

SP-043 extends the scientific canonicalization sequence beyond flat `+` splitting while keeping structural interpretation separate from scientific identity truth.

The parser preserves deterministic grouping and selected legacy delimiters without claiming every parsed token is a verified medicinal substance. Raw `products.composition`, SP-025 lexical identities, raw `products.strength`, equivalence state and client behavior remain unchanged.

## Two independent status axes

Every ingredient node has separate structure and identity status.

### Structure status

- `deterministic` — source structure can be represented without guessing.
- `needs_review` — useful text can be retained but punctuation/scope is not safe enough to assert deterministic structure.
- `unresolved` — malformed or incomplete source prevents a reliable structural node.

### Identity status

- `trusted` — ingredient candidate resolves exactly through reviewed scientific canonical/alias evidence.
- `high_confidence` — lexical/structural extraction is deterministic, but no reviewed scientific identity has been accepted.
- `needs_review` — text is scientifically overloaded, contextual, botanical/extract-like, an unreviewed alternate name, or otherwise unsafe to accept as one identity.
- `unresolved` — no defensible ingredient candidate is available.

A row is suitable for trusted production canonicalization only when its structure is deterministic and its scientific identity is trusted.

## Group provenance

`app_private.scientific_parse_complex_composition(text)` returns ordered nodes with integer-array paths and preserves grouping/separator provenance.

For `ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)`, the outer ingredient plus inner group and its two ingredient children remain distinguishable rather than being flattened into an untraceable list.

Nested balanced groups are handled recursively. Unbalanced parentheses remain unresolved instead of being repaired heuristically.

## Parenthesized alternate names

A trailing simple parenthesized name is represented on the same ingredient node rather than creating another active ingredient.

`DICYCLOMINE HCL (DICYCLOVERINE HCL)` therefore remains one ingredient with a primary and alternate-name candidate and scientific identity `needs_review` until the synonym relationship is explicitly reviewed.

Parenthesized text containing numeric content or structural delimiters is not treated as a safe alias merely because it appears in parentheses.

## Delimiter policy

- Top-level `+` is a deterministic component separator; grouped plus signs remain inside their group.
- Top-level semicolon is a strong legacy separator with provenance retained.
- Comma splitting is deliberately narrow and allowed only when every token resolves through reviewed scientific identities and the identities are distinct.
- Quantitative slash syntax is delegated to SP-042/SP-026 rules.
- Brackets, braces, ampersands, colons, equality signs and pipes remain explicit review cases in version 1.

## Botanical, vitamin, mineral and contextual text

Botanical/extract-like markers remain ingredient candidates but do not automatically become drug-substance identities. `VIT.C` may become an unverified lexical candidate; `VIT.B3`, overloaded `K`, `P`, `PP`, and underspecified bare mineral names remain review-required.

A future reviewed product-specific scientific rule may resolve contextual text, but this parser does not invent one.

## Embedded strength handoff

Leaf parsing reuses SP-042 before identity classification. A component can therefore have deterministic strength structure while its scientific identity remains separately trusted, high-confidence, review-required or unresolved.

## Malformed input

Version 1 never silently deletes malformed structure. Unbalanced parentheses, empty components, punctuation-only tokens and unsupported structural syntax remain explicit unresolved/review states with machine-readable reasons.

## Private API and regression contract

Migration `backend/migrations/0021_complex_composition_parser.sql` adds only private parser/summary helpers and supporting types/functions. Normal `public`, `anon`, and `authenticated` roles cannot execute them directly.

`backend/tests/019_complex_composition_parser_test.sql` covers grouped paths/provenance, alternate names, semicolon/comma policy, strength handoff, botanical/vitamin/mineral ambiguity, malformed input, aggregate status/count summary, raw source preservation and client access denial.

## Deployment boundary

Parser execution alone does not mutate source catalog fields. Persisted product scientific state is owned by the separately authorized versioned canonicalization refresh/backfill layer.
