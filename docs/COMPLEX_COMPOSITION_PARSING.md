# Complex Composition Parsing

Status: SP-043 repository implementation. Migration 0021 is not deployed to production by this task.
Task: Issue #105
Branch-start SHA: `b008605177abbbdfb06d763bc7a2da0ab1f1df8f`
Parser version: `1`

## Purpose

SP-043 extends the scientific canonicalization sequence beyond flat `+` splitting while keeping structural interpretation separate from scientific identity truth.

The parser can preserve deterministic grouping and selected legacy delimiters without claiming that every parsed token is a verified medicinal substance. Raw `products.composition`, SP-025 lexical identities, raw `products.strength`, equivalence state, DDI mappings and client behavior remain unchanged.

## Two independent status axes

Every ingredient node has separate structure and identity status.

### Structure status

- `deterministic` — the source structure can be represented without guessing.
- `needs_review` — useful text can be retained but punctuation/scope is not safe enough to assert a deterministic structure.
- `unresolved` — the source is malformed or incomplete enough that a reliable structural node cannot be produced.

### Identity status

- `trusted` — the ingredient candidate resolves exactly through the reviewed SP-041 scientific canonical/alias registry.
- `high_confidence` — lexical/structural extraction is deterministic, but no reviewed scientific identity has been accepted. This is still only a candidate.
- `needs_review` — the text is scientifically overloaded, contextual, botanical/extract-like, an unreviewed alternate name, or otherwise unsafe to accept as one identity.
- `unresolved` — no defensible ingredient candidate is available.

A row is suitable for a future trusted production canonicalization only when its structure is deterministic and its scientific identity is trusted. SP-043 itself persists no product mapping.

## Group provenance

`app_private.scientific_parse_complex_composition(text)` returns ordered nodes with integer-array paths.

For:

`ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)`

version 1 emits:

- ingredient path `{1}` — `ARTESUNATE`;
- group path `{2}` — raw `(SULFADOXINE+PYRIMETHAMINE)`, including the outer `+` separator;
- ingredient path `{2,1}` — `SULFADOXINE`;
- ingredient path `{2,2}` — `PYRIMETHAMINE`, including the inner `+` separator.

The group row is structural metadata and has no scientific identity status. Ingredient children retain their immediate `parent_path` and `group_raw_fragment`, so flattening does not destroy grouping provenance.

Nested balanced groups are handled recursively. Unbalanced parentheses remain unresolved instead of being repaired heuristically.

## Parenthesized alternate names

A trailing simple parenthesized name is represented on the same ingredient node rather than creating another active ingredient.

`DICYCLOMINE HCL (DICYCLOVERINE HCL)` therefore produces one ingredient node with:

- primary candidate `Dicyclomine hydrochloride`;
- alternate-name candidate `Dicycloverine hydrochloride`;
- deterministic recognized structure;
- scientific identity `needs_review` until the synonym relationship is explicitly reviewed.

If both primary and alternate names independently resolve through the SP-041 registry to the same scientific identity, the identity may be `trusted`. `Amoxicilline (Amoxicillin)` is the synthetic regression example for this reviewed path.

Parenthesized text containing numeric content or structural delimiters is not treated as a safe alias merely because it appears in parentheses.

## Delimiter policy

### Plus

Top-level `+` is a deterministic component separator. A plus inside a balanced parenthesized group is preserved inside that group and parsed recursively.

### Semicolon

A top-level semicolon is treated as a strong legacy component separator. Its exact separator provenance remains on the following node.

### Comma

Comma splitting is deliberately narrow. A simple comma list is split only when every token already resolves exactly through the reviewed SP-041 registry and all resolved scientific identities are distinct.

For example, the seeded acceptance pair `Amoxicillin, Caffeine` can be represented as two trusted identities.

`Paracetamol, Acetaminophen` is not split because both names resolve to the same identity; the comma could be a synonym/name list rather than two active ingredients. It remains review-required.

Unreviewed comma syntax also remains review-required.

### Slash

SP-043 delegates quantitative denominator and recognized presentation suffixes to SP-042. A slash such as `250 mg / 5 ml` is deterministic when SP-042 parses it under the existing SP-026 strength rules. Other slash meanings remain `needs_review`.

### Other structural punctuation

Brackets, braces, ampersands, colons, equality signs and pipes remain explicit review cases in version 1 rather than being assigned new semantics.

## Botanical and extract text

Botanical/extract-like markers are retained as ingredient candidates but do not automatically become drug-substance identities.

Examples include text containing `extract`, `root`, `leaf`, `seed`, `oil`, or reviewed botanical-name markers used by the SP-038 audit. These receive `identity_hint = botanical_or_extract` and identity status `needs_review`.

This deliberately avoids collapsing a plant, extract, plant part, standardized preparation, oil, or mixture into one chemical substance.

## Vitamins, minerals and contextual abbreviations

SP-040 deterministic lexical formatting remains the first candidate layer.

- `VIT.C` may become the unverified lexical candidate `Vitamin C`, but this alone is not a trusted scientific mapping.
- `VIT.B3` remains `needs_review` because the shorthand does not choose one precise chemical form.
- overloaded `K`, `P`, and `PP` remain `needs_review`.
- bare mineral names such as `Potassium` remain review-required because the source does not specify a precise substance/form.

Provider-specific DDI overrides are not reused as scientific truth. A future reviewed product-specific scientific rule may resolve a contextual token, but SP-043 does not create or infer such a rule.

## Embedded strength handoff

Leaf parsing reuses SP-042 before identity classification. This means:

`amoxicilline 250mg / 5ml`

can have deterministic structure/strength metadata (`250 mg per 5 ml`) while the stripped ingredient candidate is separately resolved through the reviewed SP-041 alias registry to trusted `Amoxicillin`.

If the strength/presentation syntax itself is ambiguous, structure can remain `needs_review` even when the stripped scientific identity is independently trusted. The two status axes intentionally allow this distinction.

## Malformed input

Version 1 never silently deletes malformed structure.

Examples:

- unbalanced parentheses -> `unresolved / unbalanced_parentheses`;
- an empty component in `A++B` -> explicit unresolved component node with `empty_component`;
- punctuation-only token -> `unresolved / malformed_component_token`;
- unsupported brackets/braces/other structural delimiters -> review-required with machine-readable reason.

`app_private.scientific_complex_composition_summary(text)` reports overall structure/identity status and ingredient counts while excluding structural group-container rows from ingredient counts.

## Private API

Migration `backend/migrations/0021_complex_composition_parser.sql` adds private helpers only:

- `app_private.scientific_parse_complex_composition(text)`
- `app_private.scientific_complex_composition_summary(text)`
- internal balanced-parenthesis, top-level-split, comma-safety, recursive-child and leaf helpers
- parser status/node enums and version function

Normal `public`, `anon`, and `authenticated` roles cannot execute these helpers directly.

There is no public RPC and no Flutter consumer in SP-043.

## Regression contract

`backend/tests/019_complex_composition_parser_test.sql` covers:

- grouped-expression paths, group nodes and separator provenance;
- parenthesized alternate name as one active ingredient;
- reviewed parenthesized alias confirmation;
- deterministic semicolon separation;
- narrow reviewed distinct-identity comma separation plus same-identity comma quarantine;
- SP-042 slash/embedded-strength handoff;
- botanical/extract review state;
- Vitamin C lexical candidate vs Vitamin B3 ambiguity;
- `K`, `P`, `PP` review behavior and bare-mineral ambiguity;
- unbalanced parentheses, empty components and unsupported bracket syntax;
- aggregate status/count summary;
- raw source/revision preservation;
- direct client execution denial.

## Verification and deployment boundary

SP-043 is repository-only. Migration 0021 is not applied to the hosted Sherko Pharma production project by this task. Production remains deployed through the existing DDI migration 0016; repository scientific migrations 0017–0021 remain unapplied there.

The SQL regression is intended for the repository migration stack/isolated rollback path. Running it against production solely to test repository-only DDL is not authorized by SP-043.

SP-044 is the first task in this sequence allowed to backfill reviewed derived scientific canonicalization state into production, and it requires fresh explicit owner authorization immediately before any production write.