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
4. optional provenance-manifest verification plus aggregate-only SDIF-002 reviewed identity mapping.

The tool never prints provider rows, interaction descriptions, brands, source payloads, or other provider dataset content. The SQLite file is opened read-only and its SHA-256/size are checked again after the audit to detect accidental mutation.

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

At the pinned revision the downloader uses exactly these source URLs:

```text
http://pillbox.oddb.org/amiko_db_full_idx_de.zip
http://pillbox.oddb.org/atc.csv
http://pillbox.oddb.org/drug_interactions_csv_de.zip
```

The generated `interactions.db` is not committed in the pinned SDIF Git repository and no GitHub Release currently publishes it. Therefore a provider snapshot must be built or supplied as an external operator artifact.

## Provenance manifest

Before treating a local database as a pinned provider snapshot, hash the three downloaded build inputs and the generated SQLite file. Keep the manifest outside Git beside the working database.

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

`tool/sdif_snapshot_audit.py` verifies the repository, pinned commit, exact expected source URL set, every supplied SHA-256 shape, and the generated database hash. A database audited without this manifest is explicitly reported as `provenance_manifest_not_supplied`; schema compatibility is never silently promoted into pinned-build provenance.

The manifest binds the evaluation to exact downloaded input bytes. It does not itself grant redistribution or commercial-use rights for those source datasets.

## One-command snapshot audit

Store all external artifacts under the ignored `sdif_working_dir/`, for example:

```text
sdif_working_dir/interactions.db
sdif_working_dir/sherko_scientific_identities.json
sdif_working_dir/sdif_provenance.json
```

Run:

```bash
python tool/sdif_snapshot_audit.py \
  sdif_working_dir/interactions.db \
  --identity-export sdif_working_dir/sherko_scientific_identities.json \
  --provenance sdif_working_dir/sdif_provenance.json \
  --json
```

The JSON report contains only:

- expected pinned commit;
- snapshot SHA-256 and byte size;
- SQLite quick-check status;
- row counts for the six required contract tables;
- provenance verification state/reason;
- SDIF-002 aggregate mapping counts and reviewed-ATC-backed coverage percentage.

Per-provider rows and interaction text are deliberately absent.

## Reproducible operator procedure

1. Clone `https://github.com/zdavatz/sdif` outside Sherko Pharma and checkout exactly `9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`.
2. Build the pinned Rust project.
3. Run its documented `build --download` flow so the source artifacts and `db/interactions.db` are produced by the pinned code.
4. Compute SHA-256 for the three downloaded source artifacts before deleting or replacing them, and for `db/interactions.db`.
5. Copy only the generated SQLite file and local provenance manifest into `sdif_working_dir/`; do not commit either.
6. Produce the small reviewed Sherko identity export outside Git from the current scientific layer. Confirm it contains only the three expected verified identities and their reviewed ATC codes.
7. Run `tool/sdif_snapshot_audit.py` as shown above.
8. Record only the aggregate snapshot fingerprint/counts/mapping result in the task evidence. Do not paste provider rows or interaction descriptions into the repository.

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
- aggregate reviewed-ATC mapping output without provider row leakage;
- byte-for-byte provider immutability;
- incompatible schema rejection;
- non-`ok` SQLite quick-check rejection;
- pinned upstream/source/artifact provenance acceptance;
- mismatched artifact hash rejection;
- missing pinned source hash rejection;
- explicit unverified provenance when no manifest is supplied.

The focused SDIF-004 regressions were executed locally with synthetic data during implementation: 8/8 passed. Synthetic fixtures do not establish real provider coverage.

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

A real pinned/provider-provenance `interactions.db` must be supplied or built in an environment that can reach the three pinned source URLs. Running the committed snapshot audit against that artifact requires no new mapping code.

Only after the aggregate real-provider result is recorded should a new bounded task decide whether an SDIF-specific runtime adapter is justified, how provider-specific evidence is modeled, and whether the source/data licenses permit the intended distribution model.
