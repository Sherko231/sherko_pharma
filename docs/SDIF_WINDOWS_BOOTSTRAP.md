# SDIF Windows Provider Bootstrap

Status: SDIF-005 local operator workflow. No runtime provider switch.
Task: Issue #128
Branch-start SHA: `833fef9177d2d567ffbddbdeaed387cb0ce1a0e0`
Pinned upstream: `zdavatz/sdif@9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`

## Purpose

SDIF-004 added the read-only snapshot/provenance/mapping audit, but the agent execution environment cannot resolve or reach `pillbox.oddb.org` / `sdif.oddb.org`, so it cannot obtain the real generated provider database itself.

SDIF-005 provides a Windows-friendly local bootstrap that performs the missing external step on the owner's machine without changing Sherko Pharma runtime behavior. The bootstrap:

1. checks for Git and Rust/Cargo;
2. clones the SDIF repository under ignored `sdif_working_dir/`;
3. checks out the exact pinned SDIF commit;
4. downloads the three pinned source artifacts used by that revision;
5. extracts the two ZIP inputs with Python's standard library, avoiding a dependency on a Windows `unzip` command;
6. runs the pinned SDIF build locally;
7. generates the current three-identity Sherko audit export in ignored local storage;
8. generates SHA-256 provenance for the provider database and source artifacts;
9. runs the existing SDIF-004 snapshot audit;
10. writes and prints aggregate reviewed-ATC-backed provider coverage only.

No generated/downloaded provider data is committed.

## Current reviewed identity input

The production scientific layer was read-only checked at SDIF-005 startup and currently exposes these reviewed identities for this audit:

| Scientific ingredient ID | Preferred name | Reviewed ATC |
| ---: | --- | --- |
| 1 | Amoxicillin | `J01CA04` |
| 2 | Caffeine | `N06BC01` |
| 3 | Paracetamol | `N02BE01` |

`tool/sdif_bootstrap.py` writes only these fields to the local identity-export JSON. It does not export products, brands, barcodes, prices, accounts, patient data, source CSV rows, or unrelated catalog fields.

If the reviewed scientific layer changes later, refresh this bounded export contract before treating a later audit as current.

## Windows prerequisites

Required on PATH:

- Python 3.11+;
- Git;
- Rust/Cargo.

The repository already requires Python for optional helper tooling. Install Rust from the official Rust toolchain if `cargo --version` is unavailable.

The bootstrap does **not** require a system `unzip` command.

## One-command Windows run

From the Sherko Pharma repository root in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\sdif_bootstrap_windows.ps1
```

If PowerShell execution policy already permits local scripts, this shorter form is equivalent:

```powershell
.\tool\sdif_bootstrap_windows.ps1
```

The wrapper uses `python.exe` when available and falls back to the standard Windows `py.exe -3` launcher.

The underlying cross-platform command is:

```text
python tool/sdif_bootstrap.py
```

## Local working layout

Everything generated or downloaded stays under the already ignored directory:

```text
sdif_working_dir/
  sdif-pinned/
    .git/
    db/
      amiko_db_full_idx_de.zip
      amiko_db_full_idx_de.db
      interactions.db
    csv/
      atc.csv
      drug_interactions_csv_de.zip
      drug_interactions_csv_de.csv
  sherko_scientific_identities.json
  sdif_provenance.json
  sdif_snapshot_report.json
```

The pinned upstream code itself is cloned under this ignored working tree. No provider database, source archive, provider interaction text, or source payload belongs in Git.

## Pinned source acquisition

The pinned SDIF revision declares these canonical inputs:

```text
http://pillbox.oddb.org/amiko_db_full_idx_de.zip
http://pillbox.oddb.org/atc.csv
http://pillbox.oddb.org/drug_interactions_csv_de.zip
```

The bootstrap tries each canonical HTTP URL first. If the same host rejects plain HTTP, it may retry the same path over HTTPS. The provenance manifest keeps the canonical pinned URL and hashes the actual downloaded bytes. It also records the transport used as informational metadata.

A later `tool/sdif_snapshot_audit.py` run still requires:

- exact pinned SDIF Git HEAD;
- the exact expected canonical source URL set;
- actual source-file SHA-256 values matching the local files;
- actual `interactions.db` SHA-256 matching the local database;
- compatible SQLite schema;
- successful `PRAGMA quick_check`;
- byte-for-byte read-only behavior during the audit.

## Build behavior

The bootstrap runs the pinned checkout with:

```text
cargo run --release -- build
```

It deliberately does not call upstream `build --download`, because that implementation shells out to `curl` and `unzip`; `unzip` is not a guaranteed standard Windows command. SDIF-005 performs acquisition/extraction first with Python and then invokes the same pinned build logic against those local files.

The build must produce:

```text
sdif_working_dir/sdif-pinned/db/interactions.db
```

Missing source files, malformed ZIP archives, tracked modifications in the pinned SDIF checkout, wrong pinned commit, build failure, missing output, provenance failure, SQLite failure, or mapping-audit failure all stop the bootstrap with a non-zero exit code.

## Output

On success the console prints an aggregate summary such as:

```text
SDIF pinned snapshot audit completed successfully.
  snapshot sha256: <sha256>
  reviewed ATC provider coverage: X/3 (Y%)
  aggregate report: .../sdif_working_dir/sdif_snapshot_report.json
```

The JSON report is generated by the existing SDIF-004 audit and contains aggregate-only evidence:

- pinned commit;
- snapshot SHA-256/size;
- SQLite quick-check status;
- required-table row counts;
- provenance verification state;
- mapping-status aggregate counts;
- reviewed-ATC-backed coverage percentage.

It does not contain provider rows, interaction descriptions, Syrian brands, local catalog rows, or patient/account data.

## Re-running

A normal rerun reuses already downloaded source artifacts and rebuilds the provider database from the pinned checkout.

To intentionally fetch a fresh copy of the external source artifacts:

```powershell
.\tool\sdif_bootstrap_windows.ps1 --refresh-sources
```

A refreshed download may produce different source hashes because the external provider controls those files. That is a new provider snapshot and should be recorded as such rather than assumed equivalent to an earlier build.

## Verification

Focused repository regression command:

```text
python -m unittest discover -s tool -p 'test_sdif_bootstrap.py' -v
```

These tests are offline and synthetic. They cover the current minimal identity export, actual-byte provenance hashing, required-source failure, HTTP-to-HTTPS transport fallback ordering, existing-source reuse without network, safe ZIP extraction/path-traversal rejection, and required-command failure.

They do not claim that the external SDIF source host is reachable from every machine, that Rust builds on every Windows installation, or that a real provider coverage result exists before the owner successfully runs the bootstrap.

## Preserved boundaries

SDIF-005 does not:

- replace Interaction Checker;
- add an SDIF Flutter/runtime adapter;
- change Cart DDI behavior or UI;
- convert SDIF/EPha severity into Interaction Checker severity;
- mutate Supabase production;
- infer new scientific identities or ATC codes;
- map raw Syrian brand names;
- commit or redistribute SDIF/provider/source datasets;
- claim clinical completeness or commercial/public redistribution rights.

A runtime integration task should begin only after a real successful local bootstrap produces a validated aggregate provider mapping result.