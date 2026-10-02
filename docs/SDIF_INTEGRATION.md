# SDIF Integration Foundation

Status: SDIF-001 integration contract only. No runtime provider switch.
Task: Issue #119
Sherko branch-start SHA: `38bab89c95c11c926b2e9be90e03faca0e37c41b`
Evaluated upstream: `zdavatz/sdif@9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`
Verified: 2026-10-02

## Purpose

SDIF-001 establishes a reproducible boundary for evaluating the Swiss Drug Interaction Finder without changing Sherko Pharma's active Interaction Checker DDI implementation.

The current Cart DDI engine, lifecycle, presentation and Interaction Checker mapping remain unchanged. This task does not wire SDIF into Flutter, change severity semantics, write production data, import an SDIF database, or claim that SDIF/source-data licensing permits commercial redistribution.

## Pinned upstream

The evaluated upstream project is `https://github.com/zdavatz/sdif`, Swiss Drug Interaction Finder, pinned to commit:

`9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`

At that revision the Rust package is `sdif` version `0.1.0`, edition 2021, and uses bundled SQLite through `rusqlite` plus Axum/Tokio for its local HTTP server.

Pinning matters because SDIF builds a generated database and its parsing/matching rules can change independently of Sherko Pharma. Future evaluation against another upstream revision must record the new revision and re-run the contract/clinical comparison work rather than silently treating it as the same provider version.

## Upstream data pipeline

At the pinned revision SDIF documents/builds `db/interactions.db` from several inputs:

1. AmiKo Swiss full-text drug database;
2. WHO ATC classification CSV;
3. label/Fachinformation interaction text parsed by SDIF;
4. optional EPha curated ATC-pair interactions.

Its interaction engine can surface four distinct hit families:

- `substance`: a substance mention in another drug's Swiss label text;
- `class-level`: ATC-class keyword matching against label text;
- `CYP`: query-time CYP inhibitor/inducer rules;
- `epha`: curated EPha ATC-pair records when the server starts with `--epha`.

These families have different evidence and inference paths. Sherko Pharma must preserve that distinction instead of flattening them into one unsupported clinical meaning.

## Generated SQLite contract

`tool/sdif_contract.py` validates the minimum schema required by this pinned SDIF-001 contract. Extra additive tables/columns are allowed, but all required tables and columns below must exist.

### `drugs`

- `id`
- `brand_name`
- `atc_code`
- `atc_class`
- `active_substances`
- `interactions_text`
- `route`
- `combo_hint`

### `interactions`

- `id`
- `drug_brand`
- `drug_substance`
- `interacting_substance`
- `interacting_brands`
- `description`
- `severity_score`
- `severity_label`

### `substance_brand_map`

- `substance`
- `brand_name`
- `route`

### `epha_interactions`

- `id`
- `atc1`
- `atc2`
- `risk_class`
- `risk_label`
- `effect`
- `mechanism`
- `measures`
- `title`
- `severity_score`

### `class_keywords`

- `atc_prefix`
- `keyword`

### `cyp_rules`

- `enzyme`
- `text_pattern`
- `role`
- `atc_prefix`
- `substance`

The validator opens the supplied file read-only and inspects SQLite metadata only. It does not export rows or interaction text.

Recommended local working location:

```text
sdif_working_dir/interactions.db
```

Validation:

```bash
python tool/sdif_contract.py sdif_working_dir/interactions.db
python tool/sdif_contract.py sdif_working_dir/interactions.db --json
```

The working directory is ignored by Git. Do not commit an SDIF database or downloaded source dataset.

## HTTP contract relevant to future work

The pinned server exposes, among other routes:

- `GET /api/search-drugs?q=<term>`
- `GET /api/search-drugs?atc=<code>`
- `POST /api/check`

Exact ATC lookup returns JSON records containing `brand_name`, `atc_code`, and `substances`. In the pinned implementation an ATC lookup selects one matching `drugs` row, preferring the row with the longest `interactions_text`.

`POST /api/check` accepts:

```json
{"drugs":["Ponstan","Marcoumar"]}
```

The pinned implementation resolves each input by brand-name substring first and then substance-name substring. It does not expose a stable provider substance ID in the request contract.

A successful check response has:

- `basket[]`: `brand`, `atc_code`, `substances`;
- `interactions[]`: `drug_a`, `drug_a_atc`, `drug_a_route`, `drug_b`, `drug_b_atc`, `drug_b_route`, `interaction_type`, `severity_score`, `severity_label`, `severity_indicator`, `keyword`, `description`, `explanation`, `source`, `combo_hint`.

Because `/api/check` resolves free text to an SDIF drug record, Sherko Pharma must not send raw Syrian brand names or assume text resolution itself establishes scientific identity. A later bridge should start from reviewed Sherko scientific identity/classification metadata and make the SDIF provider mapping explicit and auditable.

## Severity and EPha risk are not Interaction Checker severity

SDIF's Swiss-label severity scoring and EPha risk grading are not the same contract as Sherko Pharma's current Interaction Checker values `major|moderate|minor|none|unknown`.

At the pinned revision EPha records preserve risk classes `A|B|C|D|X`; SDIF maps them internally to numeric display scores (`X -> 3`, `D -> 2`, `C/B -> 1`, `A -> 0`). Swiss-label findings use SDIF's own German keyword-based severity scoring.

SDIF-001 therefore performs **no cross-provider severity conversion**. A future clinical-semantics task must define and validate any presentation model using provenance and source-specific meaning rather than numerically equating the two providers.

## Sherko identity bridge for the next task

The authoritative Sherko path remains:

```text
product
  -> SP-038..SP-044 scientific canonicalization
  -> reviewed scientific identity
  -> optional reviewed ATC classification metadata
  -> provider-specific SDIF mapping
  -> SDIF evidence lookup
```

Important constraints:

- ATC is classification metadata, not Sherko scientific identity truth.
- One scientific substance may have multiple ATC codes depending on route/use; an ATC code is not silently selected when context is missing.
- Salt/ester/hydrate relationships remain explicit in Sherko scientific identities.
- `needs_review`, `high_confidence`, and unresolved scientific identities must not be auto-promoted merely because SDIF text happens to match.
- SDIF provider mapping must remain separate from the existing Interaction Checker mapping tables.
- Product prices, barcodes, account identifiers, patient information and unrelated catalog data never belong in an SDIF query.

The next bounded mapping task should measure coverage before any runtime provider decision.

## Runtime boundary

The existing Dart `InteractionCheckGateway` is tied to the current `InteractionCheckResult` semantics and Interaction Checker integrity model. SDIF-001 deliberately does not make SDIF implement that interface because doing so would prematurely equate different input identity, evidence, interaction-type and severity contracts.

A later runtime task should introduce an SDIF-specific adapter/model first, preserve raw SDIF provenance, then decide whether a provider-neutral aggregation model is justified after comparison tests.

No live SDIF server is required by repository tests.

## Licensing and redistribution boundary

The pinned SDIF repository code carries the GNU GPL version 3 license.

That code license must not be assumed to grant rights to every dataset used to build `interactions.db`. The SDIF pipeline references AmiKo/Swiss drug information, WHO ATC data and EPha interaction data. Their applicable source/data licenses and any redistribution, derivative-database, attribution, commercial-use or API conditions require separate review before Sherko Pharma bundles, republishes or commercially distributes a generated SDIF database or a service built from those datasets.

Therefore SDIF-001:

- copies no SDIF source code into Sherko Pharma;
- commits no `interactions.db`;
- commits no AmiKo, WHO ATC or EPha data;
- makes no commercial/public-release permission claim;
- treats any local SDIF database as an operator-supplied evaluation artifact only.

## Verification

Focused synthetic test command:

```bash
python -m unittest discover -s tool -p 'test_sdif_contract.py' -v
```

The tests create temporary SQLite databases containing synthetic schema only and cover:

- accepted pinned minimum schema;
- missing required table rejection;
- missing required column rejection.

They contain no real medicine or interaction data.

## Non-goals retained

SDIF-001 does not:

- replace Interaction Checker;
- change Cart DDI UI or runtime behavior;
- map the catalog to SDIF/ATC in bulk;
- write to Supabase production;
- translate SDIF/EPha severity into current provider severity;
- bundle or redistribute SDIF/source datasets;
- establish clinical completeness, correctness, equivalence or substitution guidance.
