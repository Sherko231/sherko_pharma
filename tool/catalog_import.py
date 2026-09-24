"""Controlled one-time catalog import for the approved corrected CSV.

Dry-run is the default safe workflow. The source CSV is private input and must
never be committed. SQL generation/apply is allowed only after the exact
versioned import contract passes.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import parse_qs, unquote, urlsplit

BIGINT_MAX = 9_223_372_036_854_775_807

CANONICAL_COLUMNS = (
    "name_en",
    "name_ar",
    "composition",
    "manufacturer",
    "strength",
    "dosage_form",
    "package_description",
    "barcode",
    "barcode2",
    "selling_amount",
    "currency",
    "notes",
    "source_dataset",
    "source_id",
    "source_item_id",
    "source_num",
    "source_purchase_amount",
    "source_payload",
)

INTEGER_FIELDS = {
    "Id": False,
    "itemId": False,
    "num": False,
    "price": True,
    "purchasePrice": True,
}


class ImportErrorDetail(RuntimeError):
    """Expected validation or operator error."""


def load_contract(path: Path) -> dict:
    try:
        contract = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ImportErrorDetail(f"Cannot read import contract: {error}") from error

    required = {"dataset", "sha256", "row_count", "headers", "currency", "utf8_bom"}
    missing = sorted(required - contract.keys())
    if missing:
        raise ImportErrorDetail(f"Import contract is missing keys: {', '.join(missing)}")

    if not isinstance(contract["dataset"], str) or not contract["dataset"].strip():
        raise ImportErrorDetail("Import contract dataset must be a nonempty string")
    if not re.fullmatch(r"[0-9a-f]{64}", str(contract["sha256"])):
        raise ImportErrorDetail("Import contract sha256 must be 64 lowercase hex characters")
    if not isinstance(contract["row_count"], int) or contract["row_count"] <= 0:
        raise ImportErrorDetail("Import contract row_count must be a positive integer")
    if not isinstance(contract["headers"], list) or not all(
        isinstance(value, str) and value for value in contract["headers"]
    ):
        raise ImportErrorDetail("Import contract headers must be a nonempty string list")
    if len(set(contract["headers"])) != len(contract["headers"]):
        raise ImportErrorDetail("Import contract headers must be unique")
    if contract["currency"] != "SYP":
        raise ImportErrorDetail("Initial import currency contract must be SYP")
    if not isinstance(contract["utf8_bom"], bool):
        raise ImportErrorDetail("Import contract utf8_bom must be boolean")
    return contract


def _parse_bigint(value: str, field: str, allow_zero: bool) -> tuple[int | None, str | None]:
    pattern = r"(?:0|[1-9][0-9]*)" if allow_zero else r"[1-9][0-9]*"
    if not re.fullmatch(pattern, value or ""):
        return None, f"{field}:invalid_integer"
    number = int(value)
    if number > BIGINT_MAX:
        return None, f"{field}:bigint_overflow"
    return number, None


def _nullable_exact(value: str) -> str | None:
    return None if value == "" else value


def _row_errors(row: dict[str, str]) -> tuple[dict[str, int], list[str]]:
    parsed: dict[str, int] = {}
    errors: list[str] = []

    for field, allow_zero in INTEGER_FIELDS.items():
        number, error = _parse_bigint(row.get(field, ""), field, allow_zero)
        if error:
            errors.append(error)
        else:
            parsed[field] = number

    if not (row.get("name", "").strip() or row.get("name_ar", "").strip()):
        errors.append("name:both_blank")

    for field, value in row.items():
        if value is None:
            errors.append(f"{field}:missing_value")
        elif "\x00" in value:
            errors.append(f"{field}:nul_character")

    return parsed, errors


def validate_source(source: Path, contract: dict) -> tuple[dict, list[dict]]:
    try:
        raw = source.read_bytes()
    except OSError as error:
        raise ImportErrorDetail(f"Cannot read source CSV: {error}") from error

    actual_sha = hashlib.sha256(raw).hexdigest()
    has_bom = raw.startswith(b"\xef\xbb\xbf")
    contract_errors: list[str] = []
    if actual_sha != contract["sha256"]:
        contract_errors.append("contract:sha256_mismatch")
    if has_bom != contract["utf8_bom"]:
        contract_errors.append("contract:utf8_bom_mismatch")

    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as error:
        raise ImportErrorDetail(f"Source CSV is not valid UTF-8: {error}") from error

    reader = csv.DictReader(io.StringIO(text, newline=""))
    actual_headers = reader.fieldnames or []
    if actual_headers != contract["headers"]:
        contract_errors.append("contract:headers_mismatch")

    normalized: list[dict] = []
    diagnostics: list[dict] = []
    source_ids: set[int] = set()
    source_item_ids: set[int] = set()
    source_nums: set[int] = set()
    primary_codes: dict[str, set[int]] = {}
    secondary_codes: dict[str, set[int]] = {}
    combined_codes: dict[str, set[int]] = {}
    zero_prices = 0
    blank_barcode = 0
    blank_barcode2 = 0
    row_count = 0

    if actual_headers == contract["headers"]:
        for row_count, row in enumerate(reader, start=1):
            csv_row_number = row_count + 1
            if None in row:
                diagnostics.append({"row": csv_row_number, "errors": ["row:extra_columns"]})
                continue

            parsed, errors = _row_errors(row)
            source_id = parsed.get("Id")
            source_item_id = parsed.get("itemId")
            source_num = parsed.get("num")

            if source_id is not None:
                if source_id in source_ids:
                    errors.append("Id:duplicate")
                source_ids.add(source_id)
            if source_item_id is not None:
                if source_item_id in source_item_ids:
                    errors.append("itemId:duplicate")
                source_item_ids.add(source_item_id)
            if source_num is not None:
                if source_num in source_nums:
                    errors.append("num:duplicate")
                source_nums.add(source_num)

            if errors:
                diagnostics.append({"row": csv_row_number, "errors": sorted(set(errors))})
                continue

            assert source_id is not None
            price = parsed["price"]
            if price == 0:
                zero_prices += 1

            barcode = row["barcode"]
            barcode2 = row["barcode2"]
            if barcode == "":
                blank_barcode += 1
            else:
                primary_codes.setdefault(barcode, set()).add(source_id)
                combined_codes.setdefault(barcode, set()).add(source_id)
            if barcode2 == "":
                blank_barcode2 += 1
            else:
                secondary_codes.setdefault(barcode2, set()).add(source_id)
                combined_codes.setdefault(barcode2, set()).add(source_id)

            payload = {header: row[header] for header in contract["headers"]}
            normalized.append(
                {
                    "name_en": _nullable_exact(row["name"]),
                    "name_ar": _nullable_exact(row["name_ar"]),
                    "composition": _nullable_exact(row["tarkibah"]),
                    "manufacturer": _nullable_exact(row["maamaal"]),
                    "strength": _nullable_exact(row["tarkiez"]),
                    "dosage_form": _nullable_exact(row["shakielSaidalaani"]),
                    "package_description": _nullable_exact(row["shakielOboaa"]),
                    "barcode": _nullable_exact(barcode),
                    "barcode2": _nullable_exact(barcode2),
                    "selling_amount": price,
                    "currency": contract["currency"],
                    "notes": None,
                    "source_dataset": contract["dataset"],
                    "source_id": source_id,
                    "source_item_id": parsed["itemId"],
                    "source_num": parsed["num"],
                    "source_purchase_amount": parsed["purchasePrice"],
                    "source_payload": payload,
                }
            )

    if row_count != contract["row_count"]:
        contract_errors.append("contract:row_count_mismatch")

    report = {
        "mode": "dry-run",
        "dataset": contract["dataset"],
        "sha256": actual_sha,
        "expected_sha256": contract["sha256"],
        "row_count": row_count,
        "expected_row_count": contract["row_count"],
        "valid_rows": len(normalized),
        "invalid_rows": len(diagnostics),
        "zero_selling_amount_rows": zero_prices,
        "blank_barcode_rows": blank_barcode,
        "blank_barcode2_rows": blank_barcode2,
        "duplicate_primary_barcode_codes": sum(1 for ids in primary_codes.values() if len(ids) > 1),
        "duplicate_secondary_barcode_codes": sum(1 for ids in secondary_codes.values() if len(ids) > 1),
        "ambiguous_cross_field_barcode_codes": sum(1 for ids in combined_codes.values() if len(ids) > 1),
        "currency": contract["currency"],
        "contract_errors": sorted(set(contract_errors)),
        "diagnostics": diagnostics,
    }
    return report, normalized


def ensure_valid(report: dict) -> None:
    if report["contract_errors"]:
        raise ImportErrorDetail(
            "Source does not match the versioned import contract: "
            + ", ".join(report["contract_errors"])
        )
    if report["invalid_rows"]:
        raise ImportErrorDetail(
            f"Source contains {report['invalid_rows']} invalid row(s); see dry-run diagnostics"
        )
    if report["valid_rows"] != report["expected_row_count"]:
        raise ImportErrorDetail(
            f"Valid row count {report['valid_rows']} does not match contract "
            f"{report['expected_row_count']}"
        )


def _sql_text(value: str | None) -> str:
    if value is None:
        return "NULL"
    return "'" + value.replace("'", "''") + "'"


def _sql_json(value: dict) -> str:
    payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return _sql_text(payload) + "::jsonb"


def _chunks(values: list, size: int):
    for index in range(0, len(values), size):
        yield values[index:index + size]


def generate_sql(report: dict, rows: list[dict], batch_size: int = 250) -> str:
    ensure_valid(report)
    if batch_size <= 0:
        raise ImportErrorDetail("batch_size must be positive")

    dataset = rows[0]["source_dataset"]
    dataset_sql = _sql_text(dataset)
    lines = [
        r"\set ON_ERROR_STOP on",
        "-- SP-005 controlled catalog import. Generated file contains private source data.",
        f"-- Source SHA-256: {report['sha256']}",
        "begin;",
        "set local standard_conforming_strings = on;",
        "create temp table _catalog_import_expected (source_id bigint primary key) on commit drop;",
        "create temp table _catalog_import_inserted (source_id bigint primary key) on commit drop;",
    ]

    source_ids = [row["source_id"] for row in rows]
    for batch in _chunks(source_ids, 1000):
        values = ", ".join(f"({value})" for value in batch)
        lines.append("insert into _catalog_import_expected (source_id) values " + values + ";")

    lines.extend(
        [
            "do $sp005$",
            "begin",
            "  if exists (",
            "    select 1 from public.products p",
            f"    where p.source_dataset = {dataset_sql}",
            "      and not exists (",
            "        select 1 from _catalog_import_expected e where e.source_id = p.source_id",
            "      )",
            "  ) then",
            "    raise exception 'unexpected existing source_id for import dataset';",
            "  end if;",
            "end",
            "$sp005$;",
        ]
    )

    for batch in _chunks(rows, batch_size):
        tuples = []
        for row in batch:
            values = [
                _sql_text(row["name_en"]),
                _sql_text(row["name_ar"]),
                _sql_text(row["composition"]),
                _sql_text(row["manufacturer"]),
                _sql_text(row["strength"]),
                _sql_text(row["dosage_form"]),
                _sql_text(row["package_description"]),
                _sql_text(row["barcode"]),
                _sql_text(row["barcode2"]),
                str(row["selling_amount"]),
                _sql_text(row["currency"]),
                "NULL",
                _sql_text(row["source_dataset"]),
                str(row["source_id"]),
                str(row["source_item_id"]),
                str(row["source_num"]),
                str(row["source_purchase_amount"]),
                _sql_json(row["source_payload"]),
            ]
            tuples.append("(" + ", ".join(values) + ")")
        lines.extend(
            [
                "with inserted as (",
                "  insert into public.products (" + ", ".join(CANONICAL_COLUMNS) + ")",
                "  values",
                "    " + ",\n    ".join(tuples),
                "  on conflict (source_dataset, source_id) do nothing",
                "  returning source_id",
                ")",
                "insert into _catalog_import_inserted (source_id)",
                "select source_id from inserted;",
            ]
        )

    expected_count = report["expected_row_count"]
    lines.extend(
        [
            "do $sp005$",
            "declare",
            "  dataset_rows bigint;",
            "begin",
            f"  select count(*) into dataset_rows from public.products where source_dataset = {dataset_sql};",
            f"  if dataset_rows <> {expected_count} then",
            "    raise exception 'catalog import row count mismatch: expected %, found %', "
            f"{expected_count}, dataset_rows;",
            "  end if;",
            "end",
            "$sp005$;",
            "select json_build_object(",
            f"  'dataset', {dataset_sql},",
            f"  'source_rows', {expected_count},",
            "  'inserted_rows', (select count(*) from _catalog_import_inserted),",
            f"  'existing_rows', {expected_count} - (select count(*) from _catalog_import_inserted)",
            ")::text as catalog_import_summary;",
            "commit;",
            "",
        ]
    )
    return "\n".join(lines)


def write_private(path: Path, content: str, overwrite: bool) -> None:
    if path.exists() and not overwrite:
        raise ImportErrorDetail(f"Output already exists: {path}; pass --overwrite to replace it")
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    fd = os.open(path, flags, 0o600)
    try:
        try:
            os.fchmod(fd, 0o600)
        except (AttributeError, OSError):
            pass
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(content)
    except Exception:
        try:
            path.unlink(missing_ok=True)
        finally:
            raise


def database_env_from_url(url: str) -> dict[str, str]:
    parts = urlsplit(url)
    if parts.scheme not in {"postgres", "postgresql"}:
        raise ImportErrorDetail("Database URL must use postgres:// or postgresql://")
    if not parts.hostname or not parts.username or not parts.path.lstrip("/"):
        raise ImportErrorDetail("Database URL must include host, user, and database name")

    query = parse_qs(parts.query, keep_blank_values=True)
    unsupported = sorted(set(query) - {"sslmode"})
    if unsupported:
        raise ImportErrorDetail(
            "Unsupported database URL query parameters: " + ", ".join(unsupported)
        )

    try:
        port = parts.port or 5432
    except ValueError as error:
        raise ImportErrorDetail(f"Invalid database URL port: {error}") from error

    env = {
        "PGHOST": parts.hostname,
        "PGPORT": str(port),
        "PGUSER": unquote(parts.username),
        "PGDATABASE": unquote(parts.path.lstrip("/")),
    }
    if parts.password is not None:
        env["PGPASSWORD"] = unquote(parts.password)
    if query.get("sslmode"):
        env["PGSSLMODE"] = query["sslmode"][-1]
    return env


def apply_sql(sql: str, database_url: str, psql: str) -> str:
    executable = shutil.which(psql)
    if not executable:
        raise ImportErrorDetail(f"Required psql executable is missing: {psql}")

    pg_env = os.environ.copy()
    pg_env.update(database_env_from_url(database_url))
    result = subprocess.run(
        [
            executable,
            "--no-psqlrc",
            "--quiet",
            "--tuples-only",
            "--no-align",
            "--set",
            "ON_ERROR_STOP=1",
        ],
        input=sql,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=pg_env,
        check=False,
    )
    if result.returncode:
        message = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "psql failed"
        raise ImportErrorDetail(f"Database import failed: {message}")
    return result.stdout.strip()


def print_report(report: dict) -> None:
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def common(subparser):
        subparser.add_argument("--source", type=Path, required=True)
        subparser.add_argument(
            "--contract",
            type=Path,
            default=Path("backend/imports/initial_catalog_contract.json"),
        )

    dry_run = subparsers.add_parser("dry-run", help="Validate and report without database access")
    common(dry_run)

    emit = subparsers.add_parser("emit-sql", help="Write reviewed import SQL to a private local file")
    common(emit)
    emit.add_argument("--output", type=Path, required=True)
    emit.add_argument("--overwrite", action="store_true")

    apply = subparsers.add_parser("apply", help="Validate then apply through psql")
    common(apply)
    apply.add_argument(
        "--database-url-env",
        default="SHERKO_IMPORT_DATABASE_URL",
        help="Environment variable containing the database URL; the URL is never accepted as a CLI value",
    )
    apply.add_argument("--psql", default="psql")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    contract = load_contract(args.contract)
    report, rows = validate_source(args.source, contract)

    if args.command == "dry-run":
        print_report(report)
        return 0 if not report["contract_errors"] and not report["invalid_rows"] else 2

    ensure_valid(report)
    sql = generate_sql(report, rows)

    if args.command == "emit-sql":
        write_private(args.output, sql, args.overwrite)
        safe = {key: value for key, value in report.items() if key != "diagnostics"}
        safe["mode"] = "emit-sql"
        safe["output"] = str(args.output)
        safe["output_contains_private_source_data"] = True
        print_report(safe)
        return 0

    database_url = os.environ.get(args.database_url_env)
    if not database_url:
        raise ImportErrorDetail(
            f"Database URL environment variable is missing: {args.database_url_env}"
        )
    output = apply_sql(sql, database_url, args.psql)
    safe = {key: value for key, value in report.items() if key != "diagnostics"}
    safe["mode"] = "apply"
    safe["database_result"] = output
    print_report(safe)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ImportErrorDetail as error:
        print(f"Catalog import failed: {error}", file=sys.stderr)
        raise SystemExit(2)
