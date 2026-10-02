#!/usr/bin/env python3
"""Build and audit the pinned SDIF provider snapshot in local ignored storage."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path
from typing import Iterable

from sdif_contract import SDIF_PINNED_COMMIT, SDIF_UPSTREAM_REPOSITORY
from sdif_snapshot_audit import PINNED_SOURCE_PATHS

UPSTREAM_GIT_URL = f"{SDIF_UPSTREAM_REPOSITORY}.git"
IDENTITY_EXPORT_SCHEMA_VERSION = 1
PROVENANCE_SCHEMA_VERSION = 1
CURRENT_REVIEWED_IDENTITIES = (
    {
        "scientific_ingredient_id": 1,
        "preferred_name": "Amoxicillin",
        "reviewed_atc_codes": ["J01CA04"],
    },
    {
        "scientific_ingredient_id": 2,
        "preferred_name": "Caffeine",
        "reviewed_atc_codes": ["N06BC01"],
    },
    {
        "scientific_ingredient_id": 3,
        "preferred_name": "Paracetamol",
        "reviewed_atc_codes": ["N02BE01"],
    },
)
EXPECTED_EXTRACTED_PATHS = (
    "db/amiko_db_full_idx_de.db",
    "csv/drug_interactions_csv_de.csv",
)


class SdifBootstrapError(RuntimeError):
    """Raised when the local provider bootstrap cannot complete safely."""


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def identity_export_payload() -> dict[str, object]:
    return {
        "schema_version": IDENTITY_EXPORT_SCHEMA_VERSION,
        "identities": [dict(item) for item in CURRENT_REVIEWED_IDENTITIES],
    }


def provenance_payload(database_path: Path, source_root: Path) -> dict[str, object]:
    if not database_path.is_file():
        raise SdifBootstrapError(f"Generated SDIF database is missing: {database_path}")
    source_artifacts = []
    for canonical_url, relative_path in PINNED_SOURCE_PATHS.items():
        path = source_root / relative_path
        if not path.is_file():
            raise SdifBootstrapError(f"Pinned source artifact is missing: {path}")
        source_artifacts.append(
            {
                "url": canonical_url,
                "sha256": _sha256_file(path),
            }
        )
    return {
        "schema_version": PROVENANCE_SCHEMA_VERSION,
        "upstream_repository": SDIF_UPSTREAM_REPOSITORY,
        "upstream_commit": SDIF_PINNED_COMMIT,
        "artifact_sha256": _sha256_file(database_path),
        "source_artifacts": source_artifacts,
    }


def _require_commands(names: Iterable[str]) -> None:
    missing = [name for name in names if shutil.which(name) is None]
    if missing:
        raise SdifBootstrapError(
            "Missing required command(s): " + ", ".join(missing)
        )


def _run(command: list[str], *, cwd: Path | None = None, capture: bool = False) -> str:
    try:
        completed = subprocess.run(
            command,
            cwd=str(cwd) if cwd is not None else None,
            check=False,
            capture_output=capture,
            text=True,
        )
    except OSError as error:
        raise SdifBootstrapError(f"Unable to execute {command[0]}: {error}") from error
    if completed.returncode != 0:
        detail = ""
        if capture:
            detail = (completed.stderr or completed.stdout or "").strip()
        suffix = f": {detail}" if detail else ""
        raise SdifBootstrapError(
            f"Command failed ({completed.returncode}): {' '.join(command)}{suffix}"
        )
    return completed.stdout.strip() if capture else ""


def _prepare_checkout(upstream_dir: Path) -> None:
    if upstream_dir.exists():
        if not (upstream_dir / ".git").is_dir():
            raise SdifBootstrapError(
                f"Existing SDIF working path is not a Git checkout: {upstream_dir}"
            )
        dirty_tracked = _run(
            [
                "git",
                "-C",
                str(upstream_dir),
                "status",
                "--porcelain",
                "--untracked-files=no",
            ],
            capture=True,
        )
        if dirty_tracked:
            raise SdifBootstrapError(
                "Pinned SDIF checkout has tracked modifications; remove or restore them before continuing"
            )
    else:
        upstream_dir.parent.mkdir(parents=True, exist_ok=True)
        _run(["git", "clone", UPSTREAM_GIT_URL, str(upstream_dir)])

    _run(["git", "-C", str(upstream_dir), "checkout", "--detach", SDIF_PINNED_COMMIT])
    head = _run(
        ["git", "-C", str(upstream_dir), "rev-parse", "HEAD"],
        capture=True,
    )
    if head != SDIF_PINNED_COMMIT:
        raise SdifBootstrapError(
            f"Pinned SDIF checkout mismatch: expected {SDIF_PINNED_COMMIT}, got {head}"
        )


def _transport_urls(canonical_url: str) -> tuple[str, ...]:
    if canonical_url.startswith("http://"):
        return (canonical_url, "https://" + canonical_url[len("http://") :])
    return (canonical_url,)


def _download(canonical_url: str, destination: Path, *, refresh: bool) -> str:
    if destination.is_file() and not refresh:
        return "existing"
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp_path = destination.with_suffix(destination.suffix + ".part")
    if temp_path.exists():
        temp_path.unlink()

    errors: list[str] = []
    for transport_url in _transport_urls(canonical_url):
        request = urllib.request.Request(
            transport_url,
            headers={"User-Agent": "SherkoPharma-SDIF-Audit/1.0"},
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response, temp_path.open(
                "wb"
            ) as output:
                shutil.copyfileobj(response, output)
            if temp_path.stat().st_size <= 0:
                raise SdifBootstrapError(
                    f"Downloaded empty source artifact from {transport_url}"
                )
            temp_path.replace(destination)
            return transport_url
        except (
            OSError,
            urllib.error.URLError,
            urllib.error.HTTPError,
            SdifBootstrapError,
        ) as error:
            errors.append(f"{transport_url}: {error}")
            if temp_path.exists():
                temp_path.unlink()
    raise SdifBootstrapError(
        f"Unable to download pinned source artifact {canonical_url}: "
        + " | ".join(errors)
    )


def _safe_extract_zip(zip_path: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    try:
        with zipfile.ZipFile(zip_path) as archive:
            for member in archive.infolist():
                target = (destination / member.filename).resolve()
                if os.path.commonpath((str(root), str(target))) != str(root):
                    raise SdifBootstrapError(
                        f"Unsafe path in source archive {zip_path.name}: {member.filename}"
                    )
            archive.extractall(destination)
    except zipfile.BadZipFile as error:
        raise SdifBootstrapError(f"Invalid ZIP source artifact: {zip_path}") from error


def _prepare_sources(upstream_dir: Path, *, refresh: bool) -> dict[str, str]:
    transports: dict[str, str] = {}
    for canonical_url, relative_path in PINNED_SOURCE_PATHS.items():
        destination = upstream_dir / relative_path
        transports[canonical_url] = _download(
            canonical_url,
            destination,
            refresh=refresh,
        )

    _safe_extract_zip(
        upstream_dir
        / PINNED_SOURCE_PATHS[
            "http://pillbox.oddb.org/amiko_db_full_idx_de.zip"
        ],
        upstream_dir / "db",
    )
    _safe_extract_zip(
        upstream_dir
        / PINNED_SOURCE_PATHS[
            "http://pillbox.oddb.org/drug_interactions_csv_de.zip"
        ],
        upstream_dir / "csv",
    )
    for relative_path in EXPECTED_EXTRACTED_PATHS:
        expected = upstream_dir / relative_path
        if not expected.is_file():
            raise SdifBootstrapError(
                f"Expected extracted SDIF build input is missing: {expected}"
            )
    return transports


def _build_sdif(upstream_dir: Path) -> Path:
    _run(["cargo", "run", "--release", "--", "build"], cwd=upstream_dir)
    artifact = upstream_dir / "db" / "interactions.db"
    if not artifact.is_file() or artifact.stat().st_size <= 0:
        raise SdifBootstrapError(
            f"SDIF build did not produce interactions.db: {artifact}"
        )
    return artifact


def _run_snapshot_audit(
    repo_root: Path,
    artifact: Path,
    identity_export: Path,
    provenance: Path,
    upstream_dir: Path,
) -> dict[str, object]:
    audit_script = repo_root / "tool" / "sdif_snapshot_audit.py"
    command = [
        sys.executable,
        str(audit_script),
        str(artifact),
        "--identity-export",
        str(identity_export),
        "--provenance",
        str(provenance),
        "--source-root",
        str(upstream_dir),
        "--json",
    ]
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as error:
        raise SdifBootstrapError(
            f"Unable to run SDIF snapshot audit: {error}"
        ) from error
    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()
        raise SdifBootstrapError(f"SDIF snapshot audit failed: {detail}")
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise SdifBootstrapError(
            "SDIF snapshot audit returned invalid JSON"
        ) from error
    if not isinstance(payload, dict):
        raise SdifBootstrapError(
            "SDIF snapshot audit returned a non-object report"
        )
    if payload.get("provenance_verified") is not True:
        raise SdifBootstrapError(
            "SDIF snapshot audit did not verify pinned provenance"
        )
    return payload


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Build the pinned SDIF snapshot locally and measure aggregate "
            "Sherko mapping coverage."
        )
    )
    parser.add_argument(
        "--working-root",
        help="Local ignored working directory (default: <repo>/sdif_working_dir)",
    )
    parser.add_argument(
        "--refresh-sources",
        action="store_true",
        help="Re-download the pinned external source artifacts before rebuilding.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    repo_root = Path(__file__).resolve().parent.parent
    working_root = (
        Path(args.working_root).expanduser().resolve()
        if args.working_root
        else repo_root / "sdif_working_dir"
    )
    upstream_dir = working_root / "sdif-pinned"
    identity_export = working_root / "sherko_scientific_identities.json"
    provenance = working_root / "sdif_provenance.json"
    report_path = working_root / "sdif_snapshot_report.json"

    try:
        _require_commands(("git", "cargo"))
        _prepare_checkout(upstream_dir)
        transports = _prepare_sources(
            upstream_dir,
            refresh=args.refresh_sources,
        )
        artifact = _build_sdif(upstream_dir)
        _write_json(identity_export, identity_export_payload())
        provenance_data = provenance_payload(artifact, upstream_dir)
        for item in provenance_data["source_artifacts"]:
            item["retrieved_via"] = transports.get(item["url"], "existing")
        _write_json(provenance, provenance_data)
        report = _run_snapshot_audit(
            repo_root,
            artifact,
            identity_export,
            provenance,
            upstream_dir,
        )
        _write_json(report_path, report)
    except SdifBootstrapError as error:
        print(f"SDIF bootstrap failed: {error}", file=sys.stderr)
        return 2

    mapping = report.get("mapping") or {}
    mapped = mapping.get("reviewed_atc_backed_mappings", 0)
    total = mapping.get("total_identities", 0)
    percent = mapping.get("reviewed_atc_backed_coverage_percent", 0.0)
    print("SDIF pinned snapshot audit completed successfully.")
    print(f"  snapshot sha256: {report.get('sha256')}")
    print(f"  reviewed ATC provider coverage: {mapped}/{total} ({percent}%)")
    print(f"  aggregate report: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
