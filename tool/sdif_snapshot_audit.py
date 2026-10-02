#!/usr/bin/env python3
"""Verify an operator-supplied SDIF provider snapshot without exporting provider rows.

This is a read-only orchestration layer over the SDIF-001 schema validator and
SDIF-002 identity-mapping audit. It fingerprints the SQLite artifact, checks
SQLite integrity, reports aggregate table counts, optionally verifies a
provenance manifest, and emits aggregate-only mapping coverage.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from sdif_contract import (
    REQUIRED_SCHEMA,
    SDIF_PINNED_COMMIT,
    SDIF_UPSTREAM_REPOSITORY,
    SdifContractError,
    validate_sdif_database,
)
from sdif_mapping_audit import (
    SdifMappingAuditError,
    audit_identity_mapping,
    load_identity_export,
)

PROVENANCE_SCHEMA_VERSION = 1
PINNED_SOURCE_PATHS = {
    "http://pillbox.oddb.org/amiko_db_full_idx_de.zip": "db/amiko_db_full_idx_de.zip",
    "http://pillbox.oddb.org/atc.csv": "csv/atc.csv",
    "http://pillbox.oddb.org/drug_interactions_csv_de.zip": "csv/drug_interactions_csv_de.zip",
}
PINNED_SOURCE_URLS = tuple(PINNED_SOURCE_PATHS)
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class SdifSnapshotAuditError(RuntimeError):
    """Raised when a provider snapshot cannot be safely audited."""


@dataclass(frozen=True)
class SdifSnapshotReport:
    path: str
    pinned_commit: str
    sha256: str
    size_bytes: int
    quick_check: str
    table_row_counts: Mapping[str, int]
    provenance_verified: bool
    provenance_reason: str
    mapping: Mapping[str, object] | None

    def as_dict(self) -> dict[str, object]:
        return {
            "pinned_commit": self.pinned_commit,
            "sha256": self.sha256,
            "size_bytes": self.size_bytes,
            "quick_check": self.quick_check,
            "table_row_counts": dict(self.table_row_counts),
            "provenance_verified": self.provenance_verified,
            "provenance_reason": self.provenance_reason,
            "mapping": dict(self.mapping) if self.mapping is not None else None,
        }


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _open_read_only(path: Path) -> sqlite3.Connection:
    try:
        return sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)
    except sqlite3.Error as error:
        raise SdifSnapshotAuditError(
            f"Unable to open SDIF snapshot read-only: {error}"
        ) from error


def _run_quick_check(connection: sqlite3.Connection) -> tuple[str, ...]:
    try:
        return tuple(str(row[0]) for row in connection.execute("PRAGMA quick_check"))
    except sqlite3.DatabaseError as error:
        raise SdifSnapshotAuditError(
            f"SQLite quick_check failed to execute: {error}"
        ) from error


def _table_row_counts(connection: sqlite3.Connection) -> dict[str, int]:
    counts: dict[str, int] = {}
    try:
        for table in REQUIRED_SCHEMA:
            # Table names come only from the repository-owned REQUIRED_SCHEMA.
            value = connection.execute(
                f'SELECT count(*) FROM "{table}"'
            ).fetchone()
            counts[table] = int(value[0]) if value is not None else 0
    except sqlite3.DatabaseError as error:
        raise SdifSnapshotAuditError(
            f"Unable to count SDIF contract tables: {error}"
        ) from error
    return counts


def _validated_sha256(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise SdifSnapshotAuditError(f"{label} must be a SHA-256 string")
    canonical = value.strip().lower()
    if not _SHA256_RE.fullmatch(canonical):
        raise SdifSnapshotAuditError(f"{label} must be 64 lowercase hex characters")
    return canonical


def _verify_provenance_manifest(
    manifest_path: str | Path,
    artifact_sha256: str,
    source_root: str | Path,
) -> tuple[bool, str]:
    path = Path(manifest_path)
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SdifSnapshotAuditError(
            f"Unable to read SDIF provenance manifest: {error}"
        ) from error

    if not isinstance(raw, dict) or raw.get("schema_version") != PROVENANCE_SCHEMA_VERSION:
        raise SdifSnapshotAuditError(
            f"Expected provenance schema_version {PROVENANCE_SCHEMA_VERSION}"
        )
    if raw.get("upstream_repository") != SDIF_UPSTREAM_REPOSITORY:
        raise SdifSnapshotAuditError(
            "Provenance upstream_repository is not the pinned SDIF repository"
        )
    if raw.get("upstream_commit") != SDIF_PINNED_COMMIT:
        raise SdifSnapshotAuditError(
            "Provenance upstream_commit does not match the pinned SDIF commit"
        )
    manifest_artifact_sha = _validated_sha256(
        raw.get("artifact_sha256"), "artifact_sha256"
    )
    if manifest_artifact_sha != artifact_sha256:
        raise SdifSnapshotAuditError(
            "Provenance artifact_sha256 does not match interactions.db"
        )

    source_artifacts = raw.get("source_artifacts")
    if not isinstance(source_artifacts, list):
        raise SdifSnapshotAuditError("Provenance source_artifacts must be a list")

    by_url: dict[str, str] = {}
    for index, item in enumerate(source_artifacts):
        if not isinstance(item, dict):
            raise SdifSnapshotAuditError(
                f"source_artifacts[{index}] must be an object"
            )
        url = item.get("url")
        if not isinstance(url, str) or not url.strip():
            raise SdifSnapshotAuditError(
                f"source_artifacts[{index}].url must be nonblank"
            )
        if url in by_url:
            raise SdifSnapshotAuditError(f"Duplicate source artifact URL: {url}")
        by_url[url] = _validated_sha256(
            item.get("sha256"), f"source_artifacts[{index}].sha256"
        )

    missing_urls = [url for url in PINNED_SOURCE_URLS if url not in by_url]
    unexpected_urls = sorted(set(by_url) - set(PINNED_SOURCE_URLS))
    if missing_urls or unexpected_urls:
        pieces = []
        if missing_urls:
            pieces.append("missing " + ", ".join(missing_urls))
        if unexpected_urls:
            pieces.append("unexpected " + ", ".join(unexpected_urls))
        raise SdifSnapshotAuditError(
            "Provenance source artifact set does not match the pinned build inputs: "
            + "; ".join(pieces)
        )

    root = Path(source_root)
    for url, relative_path in PINNED_SOURCE_PATHS.items():
        source_path = root / relative_path
        if not source_path.is_file():
            raise SdifSnapshotAuditError(
                f"Pinned source artifact is missing: {source_path}"
            )
        actual_source_hash = _sha256_file(source_path)
        if actual_source_hash != by_url[url]:
            raise SdifSnapshotAuditError(
                f"Pinned source artifact hash does not match manifest: {relative_path}"
            )

    return True, "pinned_commit_artifact_and_source_files_match_manifest"


def audit_sdif_snapshot(
    database_path: str | Path,
    *,
    identity_export: str | Path | None = None,
    provenance_manifest: str | Path | None = None,
    source_root: str | Path | None = None,
) -> SdifSnapshotReport:
    path = Path(database_path)
    if not path.is_file():
        raise SdifSnapshotAuditError(
            f"SDIF snapshot does not exist or is not a file: {path}"
        )

    before_size = path.stat().st_size
    before_hash = _sha256_file(path)

    try:
        validate_sdif_database(path)
    except SdifContractError as error:
        raise SdifSnapshotAuditError(
            f"SDIF contract validation failed: {error}"
        ) from error

    connection = _open_read_only(path)
    try:
        quick_check_rows = _run_quick_check(connection)
        if quick_check_rows != ("ok",):
            detail = "; ".join(quick_check_rows) if quick_check_rows else "no result"
            raise SdifSnapshotAuditError(
                f"SQLite quick_check did not return ok: {detail}"
            )
        counts = _table_row_counts(connection)
    finally:
        connection.close()

    mapping: Mapping[str, object] | None = None
    if identity_export is not None:
        try:
            identities = load_identity_export(identity_export)
            mapping = audit_identity_mapping(path, identities).aggregate_dict()
        except SdifMappingAuditError as error:
            raise SdifSnapshotAuditError(
                f"SDIF mapping audit failed: {error}"
            ) from error

    after_size = path.stat().st_size
    after_hash = _sha256_file(path)
    if after_size != before_size or after_hash != before_hash:
        raise SdifSnapshotAuditError(
            "Provider snapshot bytes changed during a read-only audit"
        )

    if provenance_manifest is None:
        if source_root is not None:
            raise SdifSnapshotAuditError(
                "source_root requires a provenance manifest"
            )
        provenance_verified = False
        provenance_reason = "provenance_manifest_not_supplied"
    else:
        if source_root is None:
            raise SdifSnapshotAuditError(
                "provenance manifest verification requires source_root"
            )
        provenance_verified, provenance_reason = _verify_provenance_manifest(
            provenance_manifest,
            before_hash,
            source_root,
        )

    return SdifSnapshotReport(
        path=str(path),
        pinned_commit=SDIF_PINNED_COMMIT,
        sha256=before_hash,
        size_bytes=before_size,
        quick_check="ok",
        table_row_counts=counts,
        provenance_verified=provenance_verified,
        provenance_reason=provenance_reason,
        mapping=mapping,
    )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Validate and fingerprint an operator-supplied SDIF interactions.db "
            "and optionally run aggregate-only reviewed identity mapping."
        )
    )
    parser.add_argument("database", help="Path to SDIF interactions.db")
    parser.add_argument(
        "--identity-export",
        help="Optional Sherko reviewed scientific identity JSON export",
    )
    parser.add_argument(
        "--provenance",
        help=(
            "Optional provenance JSON binding the pinned upstream commit, "
            "source-input hashes, and interactions.db SHA-256"
        ),
    )
    parser.add_argument(
        "--source-root",
        help=(
            "Pinned SDIF checkout root containing the downloaded db/ and csv/ "
            "source artifacts; required when --provenance is supplied"
        ),
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print a machine-readable aggregate snapshot report",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        report = audit_sdif_snapshot(
            args.database,
            identity_export=args.identity_export,
            provenance_manifest=args.provenance,
            source_root=args.source_root,
        )
    except SdifSnapshotAuditError as error:
        print(f"SDIF snapshot audit failed: {error}", file=sys.stderr)
        return 2

    payload = report.as_dict()
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False))
    else:
        print(
            f"SDIF snapshot valid: sha256={report.sha256} "
            f"size={report.size_bytes} bytes quick_check={report.quick_check}"
        )
        print(
            "  provenance: "
            + ("verified" if report.provenance_verified else "not verified")
            + f" ({report.provenance_reason})"
        )
        for table, count in report.table_row_counts.items():
            print(f"  {table}: {count}")
        if report.mapping is not None:
            print(
                "  reviewed ATC provider coverage: "
                f"{report.mapping['reviewed_atc_backed_mappings']}/"
                f"{report.mapping['total_identities']} "
                f"({report.mapping['reviewed_atc_backed_coverage_percent']}%)"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
