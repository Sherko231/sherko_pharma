# Scientific Composition Canonicalization Contract

Status: SP-038 factual baseline and contract. This document does not authorize any production mutation.
Audit date: 2026-10-01
Task: Issue #100
Branch-start SHA: `bb1f9411408658a095f0c1dc2dab98dfc3d20760`

## Purpose

SP-025 intentionally models lexical ingredient identities, not scientific truth. SP-038 establishes the factual production baseline and the contract for a separate scientific canonicalization layer before later tasks change derived normalization behavior.

The authoritative source/display fields remain:

- `public.products.composition`
- `public.products.strength`

Neither field is rewritten by this contract.

## Production baseline

The audit was run read-only against the dedicated hosted Sherko Pharma database. Only aggregate queries were retained in the repository; no production catalog dump or full list of ingredient strings is committed.

| Metric | Count |
| --- | ---: |
| Products | 23,750 |
| Products with nonblank composition | 17,840 |
| Products without composition | 5,910 |
| SP-025 product-component rows | 25,840 |
| Distinct observed raw component strings | 2,427 |
| Distinct SP-025 normalized component keys | 2,358 |
| SP-025 catalog ingredient identities | 2,358 |
| Observed lexical spellings | 2,427 |
| Lexical alias keys | 2,358 |
| Alias keys with more than one observed spelling | 64 |
| Observed spellings belonging to those multi-spelling aliases | 133 |

### Current SP-025 normalization state

| Status | Products |
| --- | ---: |
| `auto_verified` | 17,029 |
| `high_confidence` | 0 |
| `needs_review` | 799 |
| `unresolved` | 5,922 |

Of the 5,922 unresolved products, 5,910 have no composition. The remaining 12 have a nonblank composition and every one contains an empty `+` segment. Of the 799 `needs_review` products, 797 are explained by the SP-025 special-character/embedded-strength rule and 2 by duplicate normalized components.

### Component-count distribution

| SP-025 component count | Products |
| ---: | ---: |
| 0 | 5,910 |
| 1 | 13,087 |
| 2 | 3,171 |
| 3 | 980 |
| 4 | 334 |
| 5 or more | 268 |

The maximum observed SP-025 component count is 18.

## Audit anomaly classes

These classes are deterministic audit flags, not accepted scientific mappings. Categories intentionally overlap. Counts must not be added together to estimate a unique number of problematic products. The exact rules are stored in `backend/audits/sp038_composition_quality_audit.sql`.

| Audit class | Distinct strings / identities | Affected products | Meaning |
| --- | ---: | ---: | --- |
| Lexical variants already collapsed by SP-025 | 64 alias keys / 133 spellings | 1,799 | Multiple observed spellings normalize to the same lexical key |
| Orthographic spelling candidates | 26 candidate pairs / 49 identities | 277 | Review candidates only; not synonyms until scientifically reviewed |
| camelCase contamination | 332 strings | 275 | Deterministic formatting cleanup candidate |
| Parenthesized content | 46 strings | 222 | May encode synonym, alternate name, qualifier, or other semantics |
| Parenthesized name-like candidates | 30 strings | 198 | Parenthesized alphabetic content without an embedded unit expression |
| Structural delimiters | 337 strings | 463 | Slash/comma/semicolon/colon/ampersand/equality/pipe/bracket syntax requiring structural interpretation |
| Embedded strength | 631 strings | 526 | Numeric strength/unit text appears inside a composition component |
| Denominator or presentation suffix | 179 strings | 243 | Per-volume or package/presentation suffix candidates |
| Salt/ester marker | 219 strings | 2,972 | A salt/ester/base relationship may need explicit scientific modeling |
| Abbreviation or chemical-formula marker | 212 strings | 2,060 | Expansion may be possible, but overloaded forms require context |
| Supplement/botanical marker | 288 strings | 987 | Candidate vitamins, minerals, botanicals, extracts, probiotics, oils, or supplement-like components |
| Ambiguous short token | 4 normalized strings | 142 | Exact short tokens `K`, `P`, `PP`, or `MG`; no global expansion is safe |
| Unbalanced grouping | 9 strings | 19 | Parenthesis/bracket/brace counts do not balance |
| Grouped `+` expression | product-level flag | 5 | `+` occurs inside parentheses and flat splitting loses grouping provenance |
| Empty `+` segment | product-level flag | 12 | Current nonblank SP-025 unresolved cases |

Representative accepted audit examples include `amoxicilline 250mg / 5ml`, `VIT.C`, `NH4CL`, overloaded `K`, grouped `ARTESUNATE+(SULFADOXINE+PYRIMETHAMINE)` and alternate-name form `DICYCLOMINE HCL (DICYCLOVERINE HCL)`. They demonstrate classification boundaries and do not authorize automatic semantic correction.

## Embedded strength relationship to SP-026

Composition-derived strength remains separate from the authoritative `products.strength` field.

Among the 526 products with an embedded strength marker in composition, 88 also have a nonblank separate `products.strength`; 438 do not. SP-042 may derive structured metadata where deterministic, but it must never silently overwrite the source strength. Any disagreement remains an explicit conflict.

## Scientific canonicalization contract

### Layering

1. **Raw source layer** — preserve `products.composition` and `products.strength` unless the owner explicitly edits the catalog through the existing product workflow.
2. **SP-025 lexical layer** — preserve current ingredient IDs, lexical aliases, raw component spelling, component order, and parser provenance.
3. **Scientific identity layer** — link an SP-025 identity to a reviewed canonical scientific identity without rewriting or renumbering the SP-025 identity.
4. **External references/classification** — reviewed identifiers/classifications remain metadata attached to the Sherko scientific identity; no external spelling or identifier replaces the internal canonical identity automatically.
5. **Equivalence/substitution** — scientific identity does not by itself establish pharmaceutical equivalence, bioequivalence, substitutability, dosing, or treatment suitability.

### Scientific identity fields

The layer can represent stable internal canonical identity, preferred scientific name, category, optional parent/base identity and precise-form relationship, reviewed external references, optional ATC classification metadata, mapping status/method, review evidence and reviewed aliases without deleting observed source spellings.

### Mapping status

- `verified` — exact scientific identity confirmed by reviewed evidence.
- `candidate` — one candidate exists but has not been accepted by scientific review.
- `needs_review` — multiple candidates, overloaded abbreviation, parent/base uncertainty, mixture/botanical ambiguity, or conflicting evidence requires review.
- `unresolved` — no defensible scientific identity candidate is available.

A numeric confidence score may prioritize review but cannot promote an unreviewed mapping to `verified` automatically.

### Canonicalization rules

- Case, Unicode, whitespace and deterministic camelCase cleanup may generate candidate text without changing the raw source.
- Standard abbreviations may be expanded only when meaning is unambiguous under an explicit rule.
- Overloaded short tokens such as `K`, `P`, `PP`, and `MG` do not receive a global scientific expansion.
- Fuzzy/string-similarity matching may nominate review candidates only.
- Salt, ester, hydrate, solvate and parent/base identities remain explicitly related rather than silently collapsed.
- Botanicals, extracts, mixtures, probiotics, vitamins and minerals may use non-INN identity categories.
- Product-specific context may resolve an otherwise ambiguous source token only through an explicit auditable rule.
- Every accepted synonym or scientific mapping preserves provenance and review evidence.
- Downstream consumer output must never be used as the sole evidence that two scientific ingredient identities are the same.

## External reference hierarchy

The hierarchy is evidence-oriented rather than a requirement that every substance exist in every source.

1. WHO International Nonproprietary Names (INN) — preferred naming authority when an INN exists.
2. FDA Global Substance Registration System / UNII — stable substance identifier cross-reference.
3. NLM RxNorm — secondary terminology/crosswalk for normalized ingredient and dose-form relationships.
4. PubChem — supporting chemical-structure and synonym cross-check for chemically defined substances.
5. WHO ATC/DDD — classification metadata only, not the primary identity authority or proof of synonymy/equivalence.

Primary references:

- https://www.who.int/teams/health-product-and-policy-standards/inn/inn-lists
- https://www.fda.gov/industry/fda-data-standards-advisory-board/fdas-global-substance-registration-system
- https://www.nlm.nih.gov/research/umls/rxnorm/overview.html
- https://pubchem.ncbi.nlm.nih.gov/docs/
- https://www.who.int/tools/atc-ddd-toolkit/atc-classification

## Downstream task boundaries

- SP-039 implements the separate scientific identity model.
- SP-040 implements deterministic lexical cleanup candidates.
- SP-041 curates reviewed semantic aliases.
- SP-042 extracts deterministic embedded strength/presentation metadata without overwriting source strength.
- SP-043 handles complex structural syntax while keeping ambiguous scientific meaning quarantined.
- SP-044 owns the reviewed production backfill and requires the production safeguards recorded in its task/evidence.

## Reproducibility and privacy

The committed audit SQL returns aggregate counts only. It does not export the source CSV, product rows, complete component lists, barcodes, account identifiers, prices, or production payloads.
