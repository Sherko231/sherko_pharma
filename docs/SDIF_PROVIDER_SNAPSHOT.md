# SDIF Provider Snapshot Verification

Status: SDIF-004 repository verification tooling completed; real provider snapshot coverage remains blocked by upstream artifact reachability in the execution environment.
Task: Issue #126
Branch-start SHA: `f44ce925f154c5554a389f4e1815bfc8667e9c76`
Pinned upstream: `zdavatz/sdif@9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`
Verified: 2026-10-02

## Purpose

SDIF-004 closes the gap between having reviewed Sherko ATC metadata and being able to make a reproducible claim about a particular SDIF `interactions.db` snapshot.

A schema-compatible SQLite file is not enough evidence that it came from the pinned SDIF revision or from the expected build inputs. `tool/sdif_snapshot_audit.py` therefore combines four separate checks:

1. the SDIF-001 minimum schema contract;
2. SQLite `PRAGMA quick_check`;
3. immutable artifact fingerprinting and aggregate required-table row counts;
4. optional provenance verification of the pinned checkout Git HEAD, generated database and actual downloaded source files, plus aggregate-only SDIF-002 reviewed identity mapping.

The tool never prints provider rows, interaction descriptions, brands, source payloads, local filesystem paths, or other provider dataset content in its JSON report. The SQLite file is opened read-only and its SHA-256/size are checked again after the audit to detect accidental mutation.

## Current Sherko input boundary

SDIF-003 established reviewed ATC metadata for the three currently verified scientific identities:

| Scientific identity | Reviewed ATC |
| --- | --- |
| Amoxicillin | `J01CA04` |
| Caffeine | `N06BC01` |
| Paracetamol | `N02BE01` |

This is `3/3 (100%)` reviewed-ATC metadata coverage inside Sherko Pharma. It is **not** a statement that SDIF maps all three identities. Actual provider coverage requires a real validated SDIF snapshot.

The local identity export consumed by the audit remains outside Git and contains only:

- `scientific_ingredient_id`;
- `preferred_name`;
- `reviewed_atc_codes`.

It must not contain product names, barcodes, prices, account data, patient data, the source CSV, or unrelated catalog fields.

## Pinned upstream build

The pinned SDIF revision documents:

```bash
cargo build --release
sdif build --download
```

and generates:

```text
db/interactions.db
```

At the pinned revision the downloader uses exactly these source URLs and local paths:

```text
http://pillbox.oddb.org/amiko_db_full_idx_de.zip
  -> db/amiko_db_full_idx_de.zip
http://pillbox.oddb.org/atc.csv
  -> csv/atc.csv
http://pillbox.oddb.org/drug_interactions_csv_de.zip
  -> csv/drug_interactions_csv_de.zip
```

The generated `interactions.db` is not committed in the pinned SDIF Git repository and no GitHub Release currently publishes it. Therefore a provider snapshot must be built or supplied as an external operator artifact.

## Provenance manifest

Before treating a local database as a pinned provider snapshot, hash the three downloaded build inputs and the generated SQLite file. Keep the manifest outside Git.

Example shape:

```json
{
  "schema_version": 1,
  "upstream_repository": "https://github.com/zdavatz/sdif",
  "upstream_commit": "9f8f69519e4806d9e0e7021f403bdcb52ed77cc0",
  "artifact_sha256": "<sha256-of-interactions.db>",
  "source_artifacts": [
    {
      "url": "http://pillbox.oddb.org/amiko_db_full_idx_de.zip",
      "sha256": "<sha256>"
    },
    {
      "url": "http://pillbox.oddb.org/atc.csv",
      "sha256": "<sha256>"
    },
    {
      "url": "http://pillbox.oddb.org/drug_interactions_csv_de.zip",
      "sha256": "<sha256>"
    }
  ]
}
```

A manifest by itself is not accepted as proof of source provenance. For `provenance_verified=true`, the audit also requires `--source-root` pointing at the SDIF checkout. It runs `git rev-parse HEAD`, requires the exact pinned commit, and re-hashes the three actual source files at the paths above. It verifies:

- exact upstream repository recorded in the manifest;
- exact pinned commit recorded in the manifest;
- actual checkout Git HEAD equals the pinned commit;
- exact expected source URL set;
- generated `interactions.db` SHA-256;
- actual source-file SHA-256 values against the manifest.

A database audited without a manifest is explicitly reported as `provenance_manifest_not_supplied`. Supplying a manifest without the source root is rejected rather than being treated as verified.

This provenance check binds the evaluation to a pinned checkout and exact downloaded input bytes. It does not itself prove source-host authenticity beyond the recorded acquisition path, and it does not grant redistribution or commercial-use rights for those datasets.

## One-command snapshot audit

Keep the pinned SDIF checkout outside the Sherko repository and store evaluation artifacts under ignored `sdif_working_dir/`, for example:

```text
../sdif-pinned/                         # checkout of pinned upstream
  db/amiko_db_full_idx_de.zip
  csv/atc.csv
  csv/drug_interactions_csv_de.zip
  db/interactions.db

sherko_pharma/sdif_working_dir/
  interactions.db
  sherko_scientific_identities.json
  sdif_provenance.json
```

Run from Sherko Pharma:

```bash
python tool/sdif_snapshot_audit.py \
  sdif_working_dir/interactions.db \
  --identity-export sdif_working_dir/sherko_scientific_identities.json \
  --provenance sdif_working_dir/sdif_provenance.json \
  --source-root ../sdif-pinned \
  --json
```

The JSON report contains only:

- expected pinned commit;
- snapshot SHA-256 and byte size;
- SQLite quick-check status;
- row counts for the six required contract tables;
- provenance verification state/reason;
- SDIF-002 aggregate mapping counts and reviewed-ATC-backed coverage percentage.

Per-provider rows, interaction text, brand names, and local filesystem paths are deliberately absent.

## Reproducible operator procedure

1. Clone `https://github.com/zdavatz/sdif` outside Sherko Pharma and checkout exactly `9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`. Do not move the checkout to another commit before the audit.
2. Build the pinned Rust project.
3. Run its documented `build --download` flow so the three source artifacts and `db/interactions.db` are produced by the pinned code.
4. Compute SHA-256 for the three downloaded source artifacts and `db/interactions.db`, then write the local provenance manifest.
5. Keep the source checkout available for the audit; `--source-root` verifies Git HEAD and re-hashes the actual downloaded source files instead of trusting the manifest alone.
6. Copy only the generated SQLite file and local provenance manifest into `sdif_working_dir/`; do not commit either.
7. Produce the small reviewed Sherko identity export outside Git from the current scientific layer. Confirm it contains only the three expected verified identities and their reviewed ATC codes.
8. Run `tool/sdif_snapshot_audit.py` as shown above.
9. Record only the aggregate snapshot fingerprint/counts/mapping result in task evidence. Do not paste provider rows or interaction descriptions into the repository.

If the operator rebuilds at a different time and any source download changes, the source/artifact hashes define a new provider snapshot even when the SDIF code commit is unchanged. Compare such snapshots explicitly rather than assuming they are identical.

## Execution-environment blocker observed in SDIF-004

During SDIF-004 on 2026-10-02, the agent environment could read the pinned GitHub source and verify the downloader/build implementation, but normal network access from the execution container could not resolve GitHub for cloning and could not connect to the SDIF source host. The web retrieval path also could not retrieve the binary/source archives from `pillbox.oddb.org` or a live SDIF API response.

Additional checks found:

- the pinned SDIF Git tree contains source code but no `interactions.db`;
- the SDIF GitHub repository currently has no Releases publishing a database artifact;
- the related `zdavatz/oddb.org` Git tree references an operational `data/sqlite/interactions.db`, but does not commit that database.

Because no real provider SQLite artifact was actually obtained, SDIF-004 makes **no real SDIF provider coverage claim**. The correct state is:

```text
Sherko reviewed ATC metadata coverage: 3/3 (100%)
Real reviewed-ATC-backed SDIF provider mapping coverage: not measured yet
```

Search-engine snippets, current live-site claims, synthetic SQLite fixtures, or hand-constructed rows are not substitutes for the real pinned/provider-provenance artifact.

## Regression verification

Focused command:

```bash
python -m unittest discover -s tool -p 'test_sdif_snapshot_audit.py' -v
```

Synthetic regression coverage includes:

- deterministic snapshot SHA-256/size/table counts;
- aggregate reviewed-ATC mapping output without provider row or local-path leakage;
- byte-for-byte provider immutability;
- incompatible schema rejection;
- non-`ok` SQLite quick-check rejection;
- pinned checkout/artifact/source-file provenance acceptance;
- wrong checkout Git commit rejection;
- mismatched artifact hash rejection;
- missing pinned source hash rejection;
- actual source-file hash mismatch rejection;
- manifest-without-source-root rejection;
- explicit unverified provenance when no manifest is supplied.

The focused SDIF-004 regressions were executed locally with synthetic data during implementation: **11/11 passed**. Synthetic fixtures do not establish real provider coverage.

## Preserved boundaries

SDIF-004 does not:

- switch the active Interaction Checker runtime;
- add a Flutter SDIF adapter or UI;
- translate SDIF/EPha risk into Interaction Checker severity;
- mutate Supabase production;
- infer new scientific identities or ATC codes;
- map raw Syrian brands;
- commit or redistribute `interactions.db`, AmiKo, WHO ATC, EPha, or other source datasets;
- claim clinical completeness, patient-specific guidance, or public/commercial data rights.

## Next dependency

A real pinned/provider-provenance `interactions.db` and its three source artifacts must be supplied or built in an environment that can reach the pinned source URLs. Running the committed snapshot audit against those artifacts requires no new mapping code.

Only after the aggregate real-provider result is recorded should a new bounded task decide whether an SDIF-specific runtime adapter is justified, how provider-specific evidence is modeled, and whether the source/data licenses permit the intended distribution model.
