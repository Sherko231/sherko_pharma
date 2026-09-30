# Scientific Composition Canonicalization Contract

Status: SP-038 factual baseline and contract. This document does not authorize any production mutation.
Audit date: 2026-10-01
Task: Issue #100
Branch-start SHA: `bb1f9411408658a095f0c1dc2dab98dfc3d20760`

## Purpose

SP-025 intentionally models lexical ingredient identities, not scientific truth. SP-038 establishes the factual production baseline and the contract for a separate scientific canonicalization layer before SP-039 through SP-044 change any derived normalization behavior.

The authoritative source/display fields remain:

- `public.products.composition`
- `public.products.strength`

Neither field is rewritten by this contract.

## Production baseline

The audit was run read-only against the dedicated hosted Sherko Pharma production database. Only aggregate queries were retained in the repository; no production catalog dump or full list of ingredient strings is committed.

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

Of the 5,922 unresolved products, 5,910 have no composition. The remaining 12 have a nonblank composition and every one contains an empty `+` segment. There was no other nonblank unresolved case at the audit snapshot.

Of the 799 `needs_review` products, 797 are explained by the SP-025 special-character/embedded-strength rule and 2 by duplicate normalized components. No `needs_review` row was unaccounted for by the current parser rules.

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

These classes are deterministic audit flags, not accepted scientific mappings. Categories intentionally overlap. Counts must not be added together to estimate a unique number of problematic products.

The exact rules are stored in `backend/audits/sp038_composition_quality_audit.sql`.

| Audit class | Distinct strings / identities | Affected products | Meaning |
| --- | ---: | ---: | --- |
| Lexical variants already collapsed by SP-025 | 64 alias keys / 133 spellings | 1,799 | Multiple observed spellings normalize to the same lexical key |
| Orthographic spelling candidates | 26 candidate pairs / 49 identities | 277 | Unreviewed trigram-neighbor candidates; not synonyms until scientifically reviewed |
| camelCase contamination | 332 strings | 275 | Deterministic formatting cleanup candidate |
| Parenthesized content | 46 strings | 222 | May encode synonym, alternate name, qualifier, or other semantics |
| Parenthesized name-like candidates | 30 strings | 198 | Parenthesized alphabetic content without an embedded unit expression |
| Structural delimiters | 337 strings | 463 | Slash/comma/semicolon/colon/ampersand/equality/pipe/bracket syntax requiring structural interpretation |
| Embedded strength | 631 strings | 526 | Numeric strength/unit text appears inside a composition component |
| Denominator or presentation suffix | 179 strings | 243 | Examples include per-volume denominators or tablet/capsule/ampoule/vial-like suffixes |
| Salt/ester marker | 219 strings | 2,972 | A salt/ester/base relationship may need explicit scientific modeling |
| Abbreviation or chemical-formula marker | 212 strings | 2,060 | Deterministic abbreviation expansion may be possible, but overloaded forms require context |
| Supplement/botanical marker | 288 strings | 987 | Candidate vitamins, minerals, botanicals, extracts, probiotics, oils, or supplement-like components |
| Ambiguous short token | 4 normalized strings | 142 | Exact short tokens `K`, `P`, `PP`, or `MG`; no global expansion is safe |
| Unbalanced grouping | 9 strings | 19 | Parenthesis/bracket/brace counts do not balance |
| Grouped `+` expression | product-level flag | 5 | `+` occurs inside parentheses and SP-025 flat splitting loses grouping provenance |
| Empty `+` segment | product-level flag | 12 | Current nonblank SP-025 unresolved cases |

### Issue examples confirmed in production

The examples below were already named in Issue #100 / the planned sequence and are included only to validate the audit rules, not to expose a broader source dump.

| Observed form | Component rows |
| --- | ---: |
| `amoxicilline...` | 2 |
| `cafeine...` | 16 |
| `paraCetamol` pattern | 33 |
| `calciumCarbonate` pattern | 12 |
| exact `VIT.C` | 19 |
| exact `NH4CL` | 7 |
| exact `K` | 6 |
| exact `P` | 5 |
| exact `PP` | 134 |
| exact `MG` | 45 |

### Orthographic-candidate rule

SP-038 uses an intentionally narrow review-candidate heuristic only to size the spelling-curation workload:

- two different SP-025 ingredient identities;
- both normalized names are at least 5 characters;
- same first 3 normalized characters;
- length difference at most 2;
- PostgreSQL `pg_trgm.similarity >= 0.85`.

This produced 26 candidate pairs involving 49 identities and 277 products. The result is not a synonym mapping. Similar drug names can represent medically different substances, so SP-041 must review every accepted semantic alias against external references.

## Embedded strength relationship to SP-026

Composition-derived strength must remain separate from the authoritative `products.strength` field.

Among the 526 products with an embedded strength marker in composition:

- 88 also have a nonblank separate `products.strength`; their existing SP-026 strength state is `needs_review`.
- 438 have no separate `products.strength`; their existing SP-026 strength state is `unresolved`.
- 243 products have a denominator/presentation suffix inside composition.
- Of those 243, 15 also have a separate strength and 228 do not.

SP-042 may derive structured metadata from composition where deterministic, but it must never silently overwrite `products.strength`. Any disagreement between composition-derived and source strength remains an explicit conflict.

## What SP-025 status means

`auto_verified` in SP-025 means the lexical parser successfully split and normalized the text under SP-025 rules. It does not mean that the ingredient name is scientifically canonical.

At the audit snapshot, 2,255 SP-025 `auto_verified` products contain at least one new scientific-attention flag from the SP-038 heuristic set (camelCase, abbreviation/formula, orthographic candidate, supplement/botanical marker, or ambiguous short token). Separately, 2,955 `auto_verified` products contain a salt/ester marker.

Therefore the scientific layer must be separate from SP-025 rather than redefining SP-025 trust.

## Scientific canonicalization contract

### Layering

1. **Raw source layer** — preserve `products.composition` and `products.strength` byte-for-byte unless the owner explicitly edits the catalog through the existing product workflow.
2. **SP-025 lexical layer** — preserve current ingredient IDs, lexical aliases, raw component spelling, component order, and parser provenance.
3. **Scientific identity layer** — SP-039 may link an SP-025 identity to a reviewed canonical scientific identity. It must not rewrite or renumber the SP-025 identity.
4. **Provider mappings** — DDI-provider identities remain provider-specific downstream mappings. A provider spelling/ID is never the Sherko scientific canonical identity.
5. **Equivalence/substitution** — scientific identity does not by itself establish pharmaceutical equivalence, bioequivalence, substitutability, dosing, or treatment suitability.

### Proposed scientific identity fields

SP-039 should be able to represent, without requiring every field to exist for every ingredient:

- stable internal canonical identity ID;
- preferred scientific name;
- identity/category type;
- optional parent/base identity;
- explicit salt, ester, hydrate, solvate, or other precise-form relationship;
- optional WHO INN name/reference;
- optional FDA GSRS/UNII;
- optional RxNorm RXCUI and concept type;
- optional PubChem CID/SID reference where chemically meaningful;
- zero or more ATC codes as classification metadata;
- mapping status;
- mapping method;
- candidate confidence as diagnostic metadata only;
- reference source, source version/date, checked date, and review notes;
- reviewed aliases linked to the canonical identity without deleting observed source spellings.

### Mapping status

Scientific status is independent from SP-025 parsing status.

- `verified` — the exact scientific identity is confirmed by reviewed evidence. Only this state may be treated as a trusted scientific mapping.
- `candidate` — one machine/deterministic candidate exists but has not been accepted by scientific review.
- `needs_review` — multiple candidates, overloaded abbreviation, parent/base uncertainty, mixture/botanical ambiguity, or conflicting references require human review.
- `unresolved` — no defensible scientific identity candidate is available.

A numeric confidence score may help prioritize review, but it must never promote `candidate` or `needs_review` to `verified` automatically.

### Canonicalization rules

- Case, Unicode, whitespace, punctuation, and deterministic camelCase cleanup may generate a candidate string without changing the raw source.
- Standard abbreviations such as salt forms may be expanded only when their meaning is unambiguous in context.
- One-letter/short overloaded tokens such as `K`, `P`, `PP`, and `MG` must not receive a global scientific expansion.
- A fuzzy/string-similarity match may generate review candidates only.
- Parent/base, salt, ester, hydrate, and solvate identities must be explicitly related rather than silently collapsed.
- Botanicals, extracts, mixtures, probiotics, vitamins, and minerals may need non-INN identity categories; lack of an INN is not itself an error.
- Product-specific context may resolve an otherwise ambiguous source token, but the override must be explicit and auditable.
- Every accepted synonym or scientific mapping must preserve provenance and review evidence.
- No downstream DDI/provider result may be used as sole evidence that two scientific ingredient identities are the same.

## External reference hierarchy

The hierarchy is evidence-oriented rather than a rule that every substance must exist in every source.

1. **WHO International Nonproprietary Names (INN)** — preferred naming authority for medicinal substances when an INN exists. As of the audit date, WHO lists Recommended INN List 95 (30 March 2026) and Proposed INN List 135 (19 July 2026). Proposed names are not equivalent to recommended INNs.
2. **FDA Global Substance Registration System / UNII** — preferred stable substance identifier cross-reference for precise substance identity, including many chemicals, biologics, botanicals, and other regulated substances. A UNII is an identifier, not an approval or therapeutic recommendation.
3. **NLM RxNorm** — secondary terminology/crosswalk for normalized ingredient, precise-ingredient, strength, dose-form, and synonym relationships. Its scope is primarily prescription and many OTC drugs available in the United States, so absence from RxNorm does not imply an invalid Syrian ingredient.
4. **PubChem** — supporting chemical-structure and synonym cross-check for chemically defined substances. PubChem Substance is an archive of submitted substance records while PubChem Compound groups unique chemical structures; neither should silently collapse mixtures or botanical material.
5. **WHO ATC/DDD** — classification metadata only. ATC is designed for drug-utilization classification and uses INNs where possible; it must not be treated as the primary identity authority or as proof of synonymy/equivalence.

Primary references:

- WHO INN programme and current lists: https://www.who.int/teams/health-product-and-policy-standards/inn/inn-lists
- WHO INN guidance: https://www.who.int/teams/health-product-and-policy-standards/inn/
- FDA GSRS / UNII: https://www.fda.gov/industry/fda-data-standards-advisory-board/fdas-global-substance-registration-system
- NLM RxNorm overview: https://www.nlm.nih.gov/research/umls/rxnorm/overview.html
- PubChem documentation: https://pubchem.ncbi.nlm.nih.gov/docs/
- WHO ATC classification: https://www.who.int/tools/atc-ddd-toolkit/atc-classification

## Downstream task boundaries

- **SP-039** implements the separate scientific identity model only.
- **SP-040** implements deterministic lexical cleanup/abbreviation expansion candidates.
- **SP-041** curates reviewed semantic aliases; fuzzy matching can nominate but cannot approve.
- **SP-042** extracts deterministic embedded strength/presentation metadata without overwriting source strength.
- **SP-043** handles complex structural syntax while keeping ambiguous scientific meaning quarantined.
- **SP-044** is the first task in this sequence allowed to mutate production derived canonicalization state and requires fresh explicit owner authorization immediately before that production write.

## Reproducibility and privacy

The committed audit SQL returns aggregate counts only. It does not export the source CSV, product rows, complete component lists, barcodes, account identifiers, prices, or production payloads.

SP-038 itself performs no migration, no DDL, no DML, no provider call, and no production data mutation.
