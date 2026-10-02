# Deterministic Composition Cleanup

Status: SP-040 repository implementation.
Task: Issue #102
Branch-start SHA: `515e914674cf546a358cc64b82b2878808ea8e49`
Cleanup rule version: `1`

## Purpose

SP-040 adds a private deterministic lexical-cleanup stage between the stable SP-025 lexical ingredient layer and later scientific semantic curation.

The stage produces a text candidate only. It does not create or verify a scientific identity, accept a synonym, change SP-025 ingredient IDs, rewrite `products.composition`, rewrite `products.strength`, or alter unrelated derived product state.

## Private function contract

Migration `backend/migrations/0018_deterministic_composition_cleanup.sql` adds:

- `app_private.scientific_cleanup_rule_version()`
- `app_private.scientific_cleanup_component_candidate(text)`
- `app_private.scientific_cleanup_status`

The candidate function is immutable and side-effect-free. It returns the exact input, candidate text, deterministic/review status, rule version, applied rules and review reasons. Normal `anon` and `authenticated` roles cannot execute the private helpers.

`deterministic_candidate` means only that the text transformation is deterministic under the current lexical rules. It does not mean the candidate is a verified scientific identity.

## Version 1 automatic rules

- Unicode-NFKC normalization, trimming and repeated-whitespace collapse while preserving the original input separately.
- Display-case cleanup for ordinary non-formula text while protecting chemical-formula casing.
- A narrow reviewed camelCase prefix allow-list for deterministic boundaries such as `calciumCarbonate` -> `Calcium carbonate`.
- Terminal `HCL` / `HBR` expansion when attached to a nonblank substance name.
- Whole-token `VIT.` formatting such as `VIT.C` -> `Vitamin C` without selecting a precise chemical form.
- One reviewed exact formula expansion: `NH4CL` -> `Ammonium chloride`.

## Review-required cases

The function returns `needs_review` without semantic expansion for overloaded short tokens (`MG`, `K`, `P`, `PP`), embedded strength, structural delimiters, unreviewed formula-like tokens, compact formulas and standalone abbreviations.

SP-042 owns embedded-strength/presentation extraction. SP-043 owns complex structural parsing. SP-041 owns reviewed semantic synonym/misspelling mappings.

## Regression contract

`backend/tests/016_deterministic_composition_cleanup_test.sql` covers the Issue acceptance examples, deterministic boundary recovery, vitamin formatting without semantic collapse, exact formula expansion, overloaded-token quarantine, embedded-strength/structure quarantine, formula casing, repeat output/provenance, raw source preservation, blank-input rejection and private-function access denial.

## Deployment boundary

The cleanup layer is private derived logic. Running it must not change production catalog rows, scientific mappings, equivalence keys, source composition or source strength unless a separately authorized persistence/backfill task explicitly performs that write.
