"""Tests for the controlled catalog import tooling."""

import csv
import hashlib
import io
import json
import os
from pathlib import Path
import stat
from tempfile import TemporaryDirectory
import unittest

from catalog_import import (
    database_env_from_url,
    generate_sql,
    load_contract,
    validate_source,
    write_private,
)


HEADERS = [
    "Id", "name", "tarkibah", "shakielSaidalaani", "maamaal", "tarkiez",
    "shakielOboaa", "price", "barcode", "barcode2", "notice", "itemId",
    "purchasePrice", "name_ar", "volume", "type", "source", "expireDate",
    "num", "isDirty", "Indications", "Contraindications", "Pregnancy",
    "isRepeated", "isForDelete",
]


def write_csv(path: Path, rows: list[dict[str, str]], bom: bool = False) -> str:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=HEADERS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    content = stream.getvalue().encode("utf-8")
    if bom:
        content = b"\xef\xbb\xbf" + content
    path.write_bytes(content)
    return hashlib.sha256(content).hexdigest()


def make_row(**changes):
    row = {
        "Id": "1",
        "name": "O'Brien % Product",
        "tarkibah": "acetyl_test",
        "shakielSaidalaani": "tablet",
        "maamaal": "Maker A",
        "tarkiez": "10 mg",
        "shakielOboaa": "box",
        "price": "14500",
        "barcode": "00123",
        "barcode2": "-1002",
        "notice": 'quoted "notice", safe',
        "itemId": "1",
        "purchasePrice": "12000",
        "name_ar": "منتج ألفا",
        "volume": "",
        "type": "",
        "source": "",
        "expireDate": "",
        "num": "101",
        "isDirty": "0",
        "Indications": "",
        "Contraindications": "",
        "Pregnancy": "",
        "isRepeated": "0",
        "isForDelete": "0",
    }
    row.update(changes)
    return row


def write_contract(path: Path, source: Path, rows: int, *, currency="SYP", bom=False):
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    contract = {
        "dataset": "synthetic@sha256:" + digest,
        "sha256": digest,
        "row_count": rows,
        "headers": HEADERS,
        "currency": currency,
        "utf8_bom": bom,
    }
    path.write_text(json.dumps(contract), encoding="utf-8")
    return contract


class CatalogImportTests(unittest.TestCase):
    def test_valid_source_preserves_text_currency_and_payload(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.csv"
            write_csv(
                source,
                [
                    make_row(),
                    make_row(
                        Id="2", itemId="2", num="102", price="0",
                        barcode="", barcode2="00123",
                    ),
                ],
            )
            contract_path = root / "contract.json"
            write_contract(contract_path, source, 2)
            contract = load_contract(contract_path)

            report, rows = validate_source(source, contract)

            self.assertEqual(report["valid_rows"], 2)
            self.assertEqual(report["invalid_rows"], 0)
            self.assertEqual(report["zero_selling_amount_rows"], 1)
            self.assertEqual(rows[0]["barcode"], "00123")
            self.assertEqual(rows[0]["barcode2"], "-1002")
            self.assertEqual(rows[0]["currency"], "SYP")
            self.assertEqual(rows[0]["source_payload"]["barcode"], "00123")
            self.assertEqual(len(rows[0]["source_payload"]), 25)

    def test_fingerprint_change_is_rejected(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.csv"
            write_csv(source, [make_row()])
            contract_path = root / "contract.json"
            contract = write_contract(contract_path, source, 1)
            source.write_bytes(source.read_bytes() + b"\n")

            report, _ = validate_source(source, contract)

            self.assertIn("contract:sha256_mismatch", report["contract_errors"])

    def test_invalid_row_is_reported_not_dropped_silently(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.csv"
            write_csv(source, [make_row(price="1.5")])
            contract_path = root / "contract.json"
            contract = write_contract(contract_path, source, 1)

            report, rows = validate_source(source, contract)

            self.assertEqual(rows, [])
            self.assertEqual(report["invalid_rows"], 1)
            self.assertEqual(report["diagnostics"][0]["row"], 2)
            self.assertIn("price:invalid_integer", report["diagnostics"][0]["errors"])

    def test_generated_sql_never_updates_existing_source_identity(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.csv"
            write_csv(source, [make_row()])
            contract_path = root / "contract.json"
            contract = write_contract(contract_path, source, 1)
            report, rows = validate_source(source, contract)

            sql = generate_sql(report, rows)

            self.assertIn("on conflict (source_dataset, source_id) do nothing", sql)
            self.assertNotIn("do update set", sql.lower())
            self.assertIn("'00123'", sql)
            self.assertIn("'-1002'", sql)
            self.assertIn("'SYP'", sql)
            self.assertIn("O''Brien % Product", sql)
            self.assertIn('"barcode":"00123"', sql)

    def test_private_sql_output_uses_restrictive_permissions(self):
        if os.name == "nt":
            self.skipTest("POSIX file mode assertion")
        with TemporaryDirectory() as directory:
            target = Path(directory) / "import.sql"
            write_private(target, "select 1;\n", overwrite=False)
            mode = stat.S_IMODE(target.stat().st_mode)
            self.assertEqual(mode, 0o600)

    def test_database_url_is_converted_to_pg_environment_without_password_in_command(self):
        env = database_env_from_url(
            "postgresql://owner:p%40ss@example.test:6543/catalog?sslmode=require"
        )
        self.assertEqual(env["PGHOST"], "example.test")
        self.assertEqual(env["PGPORT"], "6543")
        self.assertEqual(env["PGUSER"], "owner")
        self.assertEqual(env["PGPASSWORD"], "p@ss")
        self.assertEqual(env["PGDATABASE"], "catalog")
        self.assertEqual(env["PGSSLMODE"], "require")


if __name__ == "__main__":
    unittest.main()
