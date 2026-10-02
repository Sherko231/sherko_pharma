# SDIF Reviewed Identity Mapping Audit

Status: SDIF-002 repository audit tooling. No runtime provider switch.
Task: Issue #121
Branch-start SHA: `690a388e42b32c60f02ce9945618a37ba0f816f1`
Upstream contract: `zdavatz/sdif@9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`
Verified production baseline: 2026-10-02

## Purpose

SDIF-002 adds a conservative provider-specific mapping audit between Sherko Pharma's reviewed scientific identity layer and an operator-supplied SDIF `interactions.db`.

It does not make SDIF the active DDI provider. It does not change Flutter, Cart DDI behavior, Interaction Checker mapping, severity semantics, Supabase schema/data, or the authoritative catalog. It also does not infer scientific identity from SDIF text.

The audit sits after the scientific canonicalization boundary defined by SP-038 through SP-044:

```text
product
  -> reviewed Sherko scientific identity
  -> optional reviewed Sherko ATC metadata
  -> SDIF provider-mapping audit
  -> future provider-specific runtime decision
```

ATC remains classification metadata. A matching ATC code can establish provider lookup compatibility only because that code was already reviewed on the Sherko scientific identity; the SDIF provider does not create or approve Sherko ATC metadata.

## Production baseline

Read-only production inspection on 2026-10-02 found:

| Metric | Count |
| --- | ---: |
| Scientific identities currently present | 3 |
| Verified scientific identities referenced by verified lexical mappings | 3 |
| Verified lexical ingredient mappings | 4 |
| Reviewed ATC rows | 0 |
| Scientific identities with reviewed ATC metadata | 0 |
| Current reviewed-ATC-backed SDIF mapping coverage | 0 / 3 (0%) |

This zero is a real current scientific-metadata limitation, not a statement that SDIF lacks those substances. With no reviewed Sherko ATC metadata, SDIF-002 cannot claim an ATC-backed provider mapping for any current scientific identity.

No production row was written by this audit.

## Local inputs

`tool/sdif_mapping_audit.py` consumes two operator-controlled inputs that must remain outside Git.

### 1. SDIF database

Use an `interactions.db` that first passes the SDIF-001 contract validator:

```bash
python tool/sdif_contract.py sdif_working_dir/interactions.db
```

The audit opens the database read-only and uses only the pinned `drugs` and `substance_brand_map` contract after validation. It never modifies the provider database.

### 2. Reviewed Sherko scientific identity export

The audit accepts a small JSON export containing only reviewed scientific identity metadata required for mapping:

```json
{
  "schema_version": 1,
  "identities": [
    {
      "scientific_ingredient_id": 123,
      "preferred_name": "Example substance",
      "reviewed_atc_codes": ["A01AA01"]
    }
  ]
}
```

`reviewed_atc_codes` must come from Sherko's reviewed `scientific_ingredient_atc_codes` layer. The audit never derives a new ATC code from SDIF and never writes one back to Supabase.

The identity export is an evaluation artifact and must not contain product names, barcodes, prices, account data, patient data, source CSV payloads, or unrelated catalog fields.

## Mapping statuses

Every scientific identity receives exactly one provider-audit status.

| Status | Meaning |
| --- | --- |
| `reviewed_atc_match` | At least one already-reviewed Sherko ATC code exists in SDIF, and all provider rows reached by the matched reviewed codes collapse to one unique single-substance active set. This is provider lookup compatibility, not a new scientific-identity assertion. |
| `reviewed_atc_ambiguous` | A matched reviewed ATC code resolves to conflicting active-substance sets or to a combination/multi-substance active set. It is not safe as one ingredient lookup identity. |
| `exact_name_candidate` | No safe reviewed-ATC match exists, but the Sherko preferred scientific name equals an SDIF substance term under equality-only normalization and the provider term does not span multiple ATC codes. Human review is still required. |
| `ambiguous_name_candidate` | Exact normalized provider substance-name equality exists, but the provider term spans multiple ATC codes. Route/use context is required before selecting a lookup identity. |
| `unmapped` | No matched reviewed ATC code and no exact normalized SDIF substance term was found. |

If only some reviewed Sherko ATC codes exist in the provider database, the audit retains that as a reason code. A safe matched reviewed code may still provide provider lookup compatibility, but missing reviewed codes are never silently discarded from the audit evidence.

## Equality-only name normalization

Name comparison deliberately does less than catalog search:

- Unicode NFKC normalization;
- case folding;
- trim and repeated-whitespace collapse;
- punctuation and diacritics preserved.

There is no fuzzy edit-distance matching, transliteration, language translation, synonym inference, salt/base collapsing, stemming, LLM classification, or brand-name fallback.

Therefore `Caffeine` and a misspelled or differently translated term do not become a trusted match merely because they look related. A name-only exact result is always a review candidate.

## Aggregate coverage output

For a local provider snapshot:

```bash
python tool/sdif_mapping_audit.py \
  sdif_working_dir/interactions.db \
  sdif_working_dir/sherko_scientific_identities.json \
  --aggregate-only \
  --json
```

Aggregate output separates reviewed-ATC-backed mappings from review candidates and unmapped identities. This is the form suitable for Issue/PR documentation without copying provider rows into Git.

Per-identity output is available locally when manual review is needed, but provider/source datasets and generated mapping exports must remain outside the repository.

## Regression contract

`tool/test_sdif_mapping_audit.py` uses synthetic SQLite/JSON fixtures only. It covers:

- unique reviewed ATC -> `reviewed_atc_match`;
- conflicting reviewed ATC -> `reviewed_atc_ambiguous`;
- combination ATC -> `reviewed_atc_ambiguous` rather than one ingredient identity;
- exact name with no reviewed ATC -> review candidate only;
- exact name spanning multiple ATC codes -> ambiguous review candidate;
- unmapped identity remains unmapped;
- equality-only normalization does not become fuzzy matching;
- incompatible SDIF schema is rejected through the SDIF-001 validator;
- provider SQLite bytes are unchanged by the audit;
- aggregate reviewed-ATC coverage is reported separately from name candidates.

Focused command:

```bash
python -m unittest discover -s tool -p 'test_sdif_mapping_audit.py' -v
```

## Current limitation and next dependency

SDIF-002 establishes the mapping mechanism but intentionally does not fabricate coverage that the scientific layer does not yet support.

The current blocking fact is that the deployed reviewed scientific layer has zero ATC rows. A later bounded curation task should add authoritative, reviewed ATC metadata for the verified scientific identities where appropriate, preserving multiple ATC codes when route/use requires them. That task is scientific-data curation and any production write requires its own explicit owner authorization.

After reviewed ATC metadata exists, rerun this audit against a locally validated operator-supplied SDIF database and record aggregate provider coverage before considering any runtime adapter.

## Non-goals retained

SDIF-002 does not:

- switch away from Interaction Checker;
- add an SDIF Dart client or server dependency;
- change Cart DDI UI, batching, lifecycle, or severity;
- convert SDIF/EPha severity to Interaction Checker severity;
- infer or write ATC codes from SDIF;
- promote exact provider names into trusted scientific identity;
- commit or redistribute `interactions.db`, AmiKo, WHO ATC, EPha, or other provider/source datasets;
- claim clinical completeness, treatment guidance, or public/commercial redistribution permission.
