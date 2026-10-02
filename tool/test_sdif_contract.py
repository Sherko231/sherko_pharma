from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from sdif_contract import REQUIRED_SCHEMA, SdifContractError, validate_sdif_database


class SdifContractValidatorTest(unittest.TestCase):
    def _database(
        self,
        root: Path,
        *,
        omit_table: str | None = None,
        omit_column: tuple[str, str] | None = None,
    ) -> Path:
        path = root / "interactions.db"
        connection = sqlite3.connect(path)
        try:
            for table, columns in REQUIRED_SCHEMA.items():
                if table == omit_table:
                    continue

                effective_columns = [
                    column
                    for column in columns
                    if omit_column != (table, column)
                ]
                definitions = []
                for column in effective_columns:
                    column_type = "INTEGER" if column == "id" else "TEXT"
                    definitions.append(f'"{column}" {column_type}')
                connection.execute(
                    f'CREATE TABLE "{table}" ({", ".join(definitions)})'
                )
            connection.commit()
        finally:
            connection.close()
        return path

    def test_accepts_pinned_minimum_schema(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self._database(Path(directory))
            report = validate_sdif_database(path)

        self.assertEqual(set(report.tables), set(REQUIRED_SCHEMA))
        for table, required_columns in REQUIRED_SCHEMA.items():
            self.assertTrue(set(required_columns).issubset(report.tables[table]))

    def test_rejects_missing_required_table(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self._database(Path(directory), omit_table="epha_interactions")
            with self.assertRaisesRegex(
                SdifContractError,
                r"Missing required SDIF table\(s\): epha_interactions",
            ):
                validate_sdif_database(path)

    def test_rejects_missing_required_column(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self._database(
                Path(directory),
                omit_column=("drugs", "atc_code"),
            )
            with self.assertRaisesRegex(
                SdifContractError,
                r"drugs: missing atc_code",
            ):
                validate_sdif_database(path)


if __name__ == "__main__":
    unittest.main()
