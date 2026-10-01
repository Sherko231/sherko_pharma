# Embedded Composition Strength Extraction

Status: SP-042 repository implementation. Migration 0020 is not deployed to production by this task.
Task: Issue #104
Branch-start SHA: `d9c930a81e6b040420c1ed8d686232655d0065b4`
Parser version: `1`

## Purpose

SP-042 handles legacy composition text where a numeric strength and optional denominator or presentation suffix were embedded inside `products.composition` instead of being represented only in the separate authoritative `products.strength` field.

The task derives structured metadata without rewriting either source field. It sits above SP-040 deterministic lexical cleanup and reuses SP-026 strength/unit parsing semantics.

Production profiling from SP-038 found 526 products with an embedded strength marker in composition. Only 88 of those also have a nonblank separate strength field; 438 do not. The parser introduced here is repository-only and does not backfill any of them.

## Private parser contract

Migration `backend/migrations/0020_embedded_composition_strength.sql` adds private, side-effect-free helpers:

- `app_private.scientific_parse_embedded_component(text)`
- `app_private.scientific_parse_embedded_composition(text)`
- `app_private.scientific_embedded_strength_vector_key(text)`
- `app_private.scientific_source_strength_vector_key(text)`
- `app_private.scientific_compare_embedded_source_strength(text,text)`
- `app_private.catalog_strength_presentation_name(text)`
- `app_private.embedded_composition_parser_version()`

Normal `public`, `anon`, and `authenticated` roles cannot execute these helpers directly.

The component parser returns:

- exact raw component text;
- the ingredient-only source segment;
- the SP-040 deterministic cleanup candidate;
- normalized amount/unit using the SP-026 unit model;
- optional normalized denominator amount/unit;
- optional canonical presentation label;
- `deterministic`, `needs_review`, or `not_present` status;
- parser version and machine-readable review reasons.

`deterministic` means only that the text structure was parsed without guessing. It does not verify scientific synonymy or pharmaceutical equivalence.

## Deterministic single-component forms

Version 1 accepts an ingredient segment followed by one SP-026-supported measure and, optionally, one trailing denominator or recognized presentation suffix.

Examples:

| Raw component | Derived ingredient candidate | Derived strength | Presentation |
| --- | --- | --- | --- |
| `alprazolam 0.5mg / tab` | `Alprazolam` | `0.5 mg` | `tablet` |
| `amoxicilline 250mg / 5ml` | `Amoxicilline` | `250 mg per 5 ml` | — |
| `dextropropoxyphene 75mg / amp` | `Dextropropoxyphene` | `75 mg` | `ampoule` |

Strength normalization reuses SP-026 helpers. Mass is normalized to `mg`; supported IU/U/mEq/mmol/percent domains remain distinct; volume/mass denominators normalize to `ml`/`mg` in the same way as SP-026.

Unsupported presentation suffixes are review-required. For example, `/ bottle` is not silently interpreted as a dosage form or package unit.

## Ingredient cleanup remains a separate gate

After removing the deterministic strength suffix, SP-042 sends only the ingredient segment through the SP-040 lexical cleanup function.

If SP-040 says the ingredient candidate still needs review, SP-042 does not upgrade it merely because the numeric strength was parseable. This keeps formulas, ambiguous numeric ingredient names, structural punctuation, and overloaded abbreviations inside their existing review boundary.

For example, a numeric vitamin name such as `Vitamin B12` remains review-required under SP-040 version 1 even when a following `1000mcg` measure can be normalized safely.

## Combination handling

The product-level parser splits only on the same explicit `+` boundary used by SP-025. It does not own grouped-expression semantics; plus signs inside parentheses are quarantined for SP-043.

A multi-component embedded-strength expression is deterministic only when every component has an explicit parseable strength. Version 1 supports:

- one strength per explicit component with no suffix;
- one explicit denominator/presentation on every component;
- one shared trailing denominator or presentation suffix on the final component, applied to all preceding explicitly strengthened components, matching SP-026's shared-tail convention.

Example:

`amoxicillin 125mg + clavulanic acid 31.25mg / 5ml`

is represented as two ordered components, both `per 5 ml`.

By contrast:

`amoxicillin + clavulanic acid 31.25mg / 5ml`

is quarantined because there is no deterministic ingredient-to-strength pairing for the first component. Mixed suffix scopes that are neither fully explicit nor one shared final suffix are also review-required.

## Authoritative source-strength comparison

`products.strength` remains the authoritative raw/source field. SP-042 never overwrites it.

For deterministic embedded parses, the comparison helper builds an order-preserving normalized strength vector and compares it with a source-strength vector parsed under SP-026 rules. Presentation suffixes do not change numeric strength equality.

The comparison status is one of:

- `matches` — both deterministic normalized strength vectors are equal;
- `conflicts` — both are parseable and differ;
- `source_missing` — embedded strength is deterministic but the separate source field is blank;
- `source_unparseable` — embedded strength is deterministic but the separate field cannot be parsed under the supported SP-026 syntax;
- `not_comparable` — the embedded composition itself is ambiguous/review-required.

Concentrations compare by normalized rate, so `250 mg / 5 ml` and `50 mg / ml` compare as equal. A conflict remains metadata only; neither raw field is changed and no automatic winner is selected.

## Presentation vocabulary

Canonical presentation labels reuse only suffixes that SP-026 already recognizes as presentation rather than numeric denominator syntax. Version 1 includes ordinary tablet/capsule/vial/ampoule/suppository/ovule/sachet/dose forms plus the existing reviewed modified-release and special tablet/capsule suffixes.

This presentation label is descriptive parsing metadata. It does not replace the catalog dosage-form reference, infer route, or establish equivalence.

## Regression contract

`backend/tests/018_embedded_composition_strength_test.sql` covers:

- all Issue #104 acceptance examples;
- shared per-volume combination handling;
- ambiguous partial combination quarantine;
- grouped-plus handoff to SP-043;
- unsupported presentation quarantine;
- SP-040 review propagation for ingredient candidates;
- normalized concentration equality and explicit conflict detection;
- missing/unparseable authoritative strength states;
- SP-026 gram/microgram/presentation normalization reuse;
- unchanged raw composition, raw strength, product revision/timestamp, and SP-025 lexical identity after parser/comparison calls;
- private-function access denial for normal client roles.

## Deployment boundary

SP-042 is repository-only. Migration 0020 is not applied to the hosted Sherko Pharma project by this task. Hosted production remains deployed through migration 0016; repository migrations 0017–0020 remain unapplied there.

No production product row, raw composition, raw strength, scientific mapping, SP-025 lexical identity, SP-026 strength mapping, SP-027 equivalence key, DDI provider mapping, Cart behavior, or Flutter runtime is changed.

SP-043 may consume these deterministic structures while adding complex grouped/parenthesized parsing. SP-044 remains the first task allowed to backfill reviewed scientific canonicalization state into production and still requires fresh explicit owner authorization immediately before that write.
