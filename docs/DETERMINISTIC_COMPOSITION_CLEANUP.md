# Deterministic Composition Cleanup

Status: SP-040 repository implementation. Migration 0018 is not deployed to production by this task.
Task: Issue #102
Branch-start SHA: `515e914674cf546a358cc64b82b2878808ea8e49`
Cleanup rule version: `1`

## Purpose

SP-040 adds a private deterministic lexical-cleanup stage between the stable SP-025 lexical ingredient layer and later scientific semantic curation.

The stage produces a text candidate only. It does not create or verify a scientific identity, accept a synonym, change SP-025 ingredient IDs, rewrite `products.composition`, rewrite `products.strength`, or change DDI/provider mappings.

## Private function contract

Migration `backend/migrations/0018_deterministic_composition_cleanup.sql` adds:

- `app_private.scientific_cleanup_rule_version()`
- `app_private.scientific_cleanup_component_candidate(text)`
- `app_private.scientific_cleanup_status`

The candidate function is immutable and side-effect-free. It returns:

- the exact input text as `raw_component`;
- `candidate_text`;
- `deterministic_candidate` or `needs_review`;
- the numeric cleanup rule version;
- machine-readable `applied_rules`;
- machine-readable `review_reasons`.

Normal `anon` and `authenticated` roles cannot execute either private helper.

`deterministic_candidate` means only that the text transformation is deterministic under the current lexical rules. It does not mean the candidate is a verified scientific identity.

## Version 1 automatic rules

### Equality-safe formatting

Input is Unicode-NFKC normalized, surrounding whitespace is trimmed, and repeated whitespace is collapsed. The original input remains returned separately and no catalog row is changed.

Generic punctuation is not stripped because punctuation can carry chemical or structural meaning. Complex delimiters are quarantined for SP-043 instead.

### Display-case cleanup

Ordinary non-formula text is lower-cased and then sentence-cased. This turns the legacy mixed-case example `paraCetamol` into the lexical candidate `Paracetamol` without asserting a synonym mapping.

### Reviewed camelCase boundaries

A deliberately small prefix allow-list can recover a word boundary when the original capitalization itself makes the boundary deterministic. Version 1 includes:

- calcium
- magnesium
- sodium
- potassium
- ferrous
- ferric
- zinc
- aluminium
- aluminum

Example: `calciumCarbonate` -> `Calcium carbonate`.

Arbitrary camelCase is not split. This is why `paraCetamol` is case-normalized as one token instead of becoming `para Cetamol`.

### Terminal salt abbreviations

Only terminal `HCL` and `HBR` attached to a nonblank substance name are expanded:

- `DIPHENHYDRAMINE HCL` -> `Diphenhydramine hydrochloride`
- `DEXTROMETHORPHAN HBR` -> `Dextromethorphan hydrobromide`

Standalone `HCL` or `HBR` is review-required instead of being treated as an ingredient name.

### Explicit vitamin notation

Whole-token `VIT.` notation is formatted lexically:

- `VIT.C` -> `Vitamin C`
- `VIT.B3` -> `Vitamin B3`

This formatting does not select a chemical form. In particular, `Vitamin B3` is not automatically mapped to niacin, nicotinamide, or another scientific identity; SP-041 owns reviewed semantic aliases.

### Explicit formula expansion

Version 1 contains one reviewed exact formula expansion required by Issue #102:

- `NH4CL` -> `Ammonium chloride`

The implementation deliberately does not generalize arbitrary chemical formulas from string shape alone.

## Review-required cases

The function returns `needs_review` without semantic expansion for:

- exact overloaded short tokens `MG`, `K`, `P`, and `PP`;
- embedded numeric strength/unit contamination such as `0.5MG`;
- structural syntax such as parentheses, `/`, commas, semicolons, ampersands, brackets, braces, or similar delimiters;
- unreviewed numeric/formula-like tokens such as `FeSO4`;
- standalone short uppercase abbreviations/formulas such as `HCL`, `CA`, `FE`, or `ZN`.

SP-042 owns embedded-strength/presentation extraction. SP-043 owns complex structural parsing. SP-041 owns reviewed semantic synonym/misspelling mappings.

## Regression contract

`backend/tests/016_deterministic_composition_cleanup_test.sql` covers:

- all Issue #102 acceptance examples;
- `calciumCarbonate` deterministic boundary recovery;
- `VIT.B3` formatting without semantic collapse;
- exact `NH4CL` expansion;
- non-expansion of `MG`, `K`, `P`, and `PP`;
- quarantine of embedded strength and structural syntax;
- preservation of unreviewed formulas and standalone abbreviations;
- deterministic repeat output and rule provenance;
- unchanged raw product revision/source state and unchanged SP-025 lexical identity after candidate generation;
- blank-input rejection;
- no direct client execution of the private functions.

## Deployment boundary

SP-040 is repository-only. Migration 0018 is not applied to the hosted Sherko Pharma production project by this task. No production catalog row, scientific mapping, provider mapping, equivalence key, source composition, or source strength is changed.

SP-041 may use these deterministic candidates as inputs to reviewed scientific synonym curation. SP-044 remains the first task authorized by the sequence to backfill reviewed derived scientific canonicalization state, and it still requires fresh explicit owner authorization immediately before any production write.
