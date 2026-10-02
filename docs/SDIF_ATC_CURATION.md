# SDIF Reviewed ATC Curation

Status: SDIF-003 production curation completed and verified on 2026-10-02.
Task: Issue #123
Branch-start SHA: `cb652bafd877cda2eb8d4aceab720af2c12b08c2`
Migration: `backend/migrations/0023_reviewed_atc_metadata.sql`

## Purpose

SDIF-003 adds a deliberately small set of reviewed ATC classification metadata to the verified Sherko scientific-identity layer so SDIF provider mapping can use reviewed classification context instead of inferring ATC from provider text.

ATC remains classification metadata, not scientific identity truth. These rows do not change the scientific ingredient identity, raw catalog composition/strength, SP-025 lexical identities, Interaction Checker mappings, products, alternatives, or Flutter runtime.

## Reviewed source

The source of record for this task is the official WHO Collaborating Centre for Drug Statistics Methodology ATC/DDD Index, checked on 2026-10-02. The relevant pages reported a last-updated date of 2026-01-20.

| Sherko scientific identity | Reviewed ATC | ATC name | Scope | Official source |
| --- | --- | --- | --- | --- |
| Amoxicillin | `J01CA04` | amoxicillin | plain systemic amoxicillin | https://atcddd.fhi.no/atc_ddd_index/?code=J01CA04&showdescription=no |
| Caffeine | `N06BC01` | caffeine | plain caffeine | https://atcddd.fhi.no/atc_ddd_index/?code=N06BC01&showdescription=no |
| Paracetamol | `N02BE01` | paracetamol | plain paracetamol | https://atcddd.fhi.no/atc_ddd_index/?code=N02BE01&showdescription=no |

The official ATC material also documents combination-specific classification rules. These three rows therefore must not be interpreted as product-level classification for every combination, route, or therapeutic use containing the substance. Future route/use-specific codes require separate reviewed curation and may coexist with these rows.

## Migration safety

`0023_reviewed_atc_metadata.sql` resolves each target identity by `scientific_name_key(preferred_name)` rather than generated database IDs.

For each target it requires:

- exactly one matching scientific identity;
- at least one current `verified` lexical-to-scientific mapping;
- no pre-existing row for the same identity/code with a conflicting ATC name.

The insert is idempotent. Provenance uses a fixed review timestamp and fixed reference version so rerunning the same migration logic does not create time-only changes.

The migration writes only `app_private.scientific_ingredient_atc_codes`.

## Production verification

Immediately before SDIF-003:

- scientific identities: 3;
- verified lexical mappings: 4;
- verified scientific identities: 3;
- reviewed ATC rows: 0;
- identities with reviewed ATC metadata: 0.

Baseline fingerprints:

- scientific identity fingerprint: `47e750b04856e05254f060f54b579b4f`;
- lexical scientific-mapping fingerprint: `8f3de19d0e93e05aa4003982920bc9b0`;
- empty ATC fingerprint: `d41d8cd98f00b204e9800998ecf8427e`.

After deployment:

- scientific identities: 3;
- verified lexical mappings: 4;
- verified scientific identities: 3;
- reviewed ATC rows: 3;
- identities with reviewed ATC metadata: 3;
- reviewed-ATC metadata coverage of currently verified scientific identities: `3/3 (100%)`.

Post-deployment fingerprints:

- scientific identity fingerprint: `47e750b04856e05254f060f54b579b4f` — unchanged;
- lexical scientific-mapping fingerprint: `8f3de19d0e93e05aa4003982920bc9b0` — unchanged;
- reviewed ATC fingerprint: `7de2cb98aa7a9eac4540671224900460`.

`backend/tests/021_reviewed_atc_metadata_test.sql` was executed read-only against production after migration and completed without exception.

## What this does and does not prove for SDIF

Sherko now has reviewed ATC metadata for all three currently verified scientific identities. This removes the specific metadata blocker identified by SDIF-002.

It does **not** prove that all three identities are valid SDIF provider mappings. The SDIF-002 audit still needs an operator-supplied `interactions.db` from the pinned SDIF baseline to determine whether each reviewed ATC code resolves to a unique single-substance provider record, an ambiguous/combination record, or no provider record.

Therefore the current state is:

```text
Sherko verified scientific identity coverage with reviewed ATC metadata: 3/3 (100%)
Actual reviewed-ATC-backed SDIF provider mapping coverage: not yet measured against a real interactions.db
```

No provider database, SDIF source dataset, production catalog dump, credentials, product names, barcodes, prices, or patient/account data are committed by this task.

## Next dependency

The next bounded SDIF task should obtain or build an operator-local SDIF `interactions.db` for the pinned upstream revision, validate it with `tool/sdif_contract.py`, export only the three reviewed Sherko identity records needed by `tool/sdif_mapping_audit.py`, and record aggregate provider mapping coverage.

Only after that provider-side comparison should a runtime SDIF adapter or provider-selection decision be considered.
