# Embedded Composition Strength Extraction

Status: SP-042 repository implementation.
Task: Issue #104
Branch-start SHA: `d9c930a81e6b040420c1ed8d686232655d0065b4`
Parser version: `1`

## Purpose

SP-042 handles legacy composition text where numeric strength and optional denominator/presentation suffix are embedded inside `products.composition` instead of being represented only in the separate authoritative `products.strength` field.

The task derives structured metadata without rewriting either source field. It sits above SP-040 deterministic lexical cleanup and reuses SP-026 strength/unit parsing semantics.

## Private parser contract

Migration `backend/migrations/0020_embedded_composition_strength.sql` adds private, side-effect-free helpers for component parsing, full-composition parsing, normalized vector keys, source-strength comparison and presentation normalization.

The component parser returns exact raw text, ingredient-only segment, cleanup candidate, normalized amount/unit, optional denominator/presentation, deterministic/review status, parser version and machine-readable reasons.

`deterministic` means only that the text structure was parsed without guessing. It does not verify scientific synonymy or pharmaceutical equivalence.

## Deterministic forms

Version 1 accepts an ingredient segment followed by one supported measure and optionally one trailing denominator or recognized presentation suffix.

Examples:

| Raw component | Derived ingredient candidate | Derived strength | Presentation |
| --- | --- | --- | --- |
| `alprazolam 0.5mg / tab` | `Alprazolam` | `0.5 mg` | `tablet` |
| `amoxicilline 250mg / 5ml` | `Amoxicilline` | `250 mg per 5 ml` | — |
| `dextropropoxyphene 75mg / amp` | `Dextropropoxyphene` | `75 mg` | `ampoule` |

Strength normalization reuses SP-026 helpers. Unsupported presentation suffixes remain review-required.

## Ingredient cleanup remains a separate gate

After removing a deterministic strength suffix, SP-042 sends only the ingredient segment through SP-040 lexical cleanup. A review-required ingredient candidate is not upgraded merely because its numeric strength is parseable.

## Combination handling

The product-level parser splits only on the explicit `+` boundary used by SP-025. Grouped plus expressions are left to SP-043.

A multi-component embedded-strength expression is deterministic only when each component has an explicit parseable strength or when one shared final denominator/presentation suffix can be applied under the existing SP-026 convention. Ambiguous partial pairings remain review-required.

## Authoritative source-strength comparison

`products.strength` remains authoritative raw/source text and is never overwritten by this parser.

Comparison status is one of:

- `matches`
- `conflicts`
- `source_missing`
- `source_unparseable`
- `not_comparable`

A conflict remains metadata only; neither raw field is changed and no automatic winner is selected.

## Regression contract

`backend/tests/018_embedded_composition_strength_test.sql` covers the Issue acceptance examples, shared denominators, ambiguous partial combinations, grouped-plus handoff, unsupported presentation quarantine, SP-040 review propagation, normalized concentration equality/conflicts, source missing/unparseable states, raw source preservation and private-function access denial.

## Deployment boundary

This parser does not independently mutate catalog rows. Persisted scientific canonicalization state is owned by the separately authorized backfill/refresh layer. Product source text, SP-025 lexical identity, SP-026 strength state, SP-027 equivalence state, Cart behavior and Flutter runtime remain independent.
