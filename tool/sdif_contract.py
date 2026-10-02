#!/usr/bin/env python3
"""Validate the minimum SQLite schema expected from the pinned SDIF baseline.

This tool is intentionally schema-only. It never copies, exports, prints, or
commits SDIF interaction data. Pass an operator-controlled interactions.db path
when evaluating an SDIF build locally.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

SDIF_UPSTREAM_REPOSITORY = "https://github.com/zdavatz/sdif"
SDIF_PINNED_COMMIT = "9f8f69519e4806d9e0e7021f403bdcb52ed77cc0"

# Minimum columns consumed by the documented SDIF-001 contract. Additional
# upstream tables/columns are tolerated so an additive schema change does not
# invalidate an otherwise compatible database.
REQUIRED_SCHEMA: Mapping[str, tuple[str, ...]] = {
    "drugs": (
        "id",
        "brand_name",
        "atc_code",
        "atc_class",
        "active_substances",
        "interactions_text",
        "route",
        "combo_hint",
    ),
    "interactions": (
        "id",
        "drug_brand",
        "drug_substance",
        "interacting_substance",
        "interacting_brands",
        "description",
        "severity_score",
        "severity_label",
    ),
    "substance_brand_map": (
        "substance",
        "brand_name",
        "route",
    ),
    "epha_interactions": (
        "id",
        "atc1",
        "atc2",
        "risk_class",
        "risk_label",
        "effect",
        "mechanism",
        "measures",
        "title",
        "severity_score",
    ),
    "class_keywords": (
        "atc_prefix",
        "keyword",
    ),
    "cyp_rules": (
        "enzyme",
        "text_pattern",
        "role",
        "atc_prefix",
        "substance",
    ),
}


class SdifContractError(RuntimeError):
    """Raised when an SDIF database does not match the pinned minimum contract."""


@dataclass(frozen=True)
class SdifContractReport:
    path: str
    pinned_commit: str
    tables: Mapping[str, tuple[str, ...]]

    def as_dict(self) -> dict[str, object]:
        return {
            "path": self.path,
            "pinned_commit": self.pinned_commit,
            "tables": {name: list(columns) for name, columns in self.tables.items()},
        }


def _open_read_only(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise SdifContractError(f"SDIF database does not exist or is not a file: {path}")

    # pathlib.as_uri() percent-encodes platform paths. SQLite accepts the
    # resulting file: URI and mode=ro prevents accidental mutation.
    uri = f"{path.resolve().as_uri()}?mode=ro"
    try:
        return sqlite3.connect(uri, uri=True)
    except sqlite3.Error as error:
        raise SdifContractError(f"Unable to open SDIF database read-only: {error}") from error


def _table_columns(connection: sqlite3.Connection, table: str) -> tuple[str, ...]:
    # Table names come only from the hard-coded REQUIRED_SCHEMA mapping.
    rows = connection.execute(f'PRAGMA table_info("{table}")').fetchall()
    return tuple(str(row[1]) for row in rows)


def validate_sdif_database(database_path: str | Path) -> SdifContractReport:
    path = Path(database_path)
    connection = _open_read_only(path)
    try:
        available_tables = {
            str(row[0])
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            ).fetchall()
        }

        missing_tables = sorted(set(REQUIRED_SCHEMA) - available_tables)
        if missing_tables:
            raise SdifContractError(
                "Missing required SDIF table(s): " + ", ".join(missing_tables)
            )

        observed: dict[str, tuple[str, ...]] = {}
        column_failures: list[str] = []
        for table, required_columns in REQUIRED_SCHEMA.items():
            actual_columns = _table_columns(connection, table)
            observed[table] = actual_columns
            missing_columns = [
                column for column in required_columns if column not in actual_columns
            ]
            if missing_columns:
                column_failures.append(
                    f"{table}: missing {', '.join(missing_columns)}"
                )

        if column_failures:
            raise SdifContractError(
                "Incompatible SDIF table contract: " + "; ".join(column_failures)
            )

        return SdifContractReport(
            path=str(path),
            pinned_commit=SDIF_PINNED_COMMIT,
            tables=observed,
        )
    except sqlite3.DatabaseError as error:
        raise SdifContractError(f"Invalid or unreadable SQLite database: {error}") from error
    finally:
        connection.close()


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Validate an operator-supplied SDIF interactions.db against the "
            "Sherko Pharma SDIF-001 pinned minimum schema contract."
        )
    )
    parser.add_argument("database", help="Path to SDIF interactions.db")
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print a machine-readable schema report on success.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        report = validate_sdif_database(args.database)
    except SdifContractError as error:
        print(f"SDIF contract validation failed: {error}", file=sys.stderr)
        return 2

    if args.json:
        print(json.dumps(report.as_dict(), indent=2, sort_keys=True))
    else:
        print(
            "SDIF contract valid for pinned baseline "
            f"{report.pinned_commit}: {len(report.tables)} required tables present."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
