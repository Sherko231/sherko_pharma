from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from sdif_contract import REQUIRED_SCHEMA
from sdif_mapping_audit import (
    STATUS_AMBIGUOUS_NAME_CANDIDATE,
    STATUS_EXACT_NAME_CANDIDATE,
    STATUS_REVIEWED_ATC_AMBIGUOUS,
    STATUS_REVIEWED_ATC_MATCH,
    STATUS_UNMAPPED,
    SdifMappingAuditError,
    SherkoScientificIdentity,
    audit_identity_mapping,
    load_identity_export,
    scientific_name_key,
)


class SdifMappingAuditTest(unittest.TestCase):
    def _database(self, root: Path) -> Path:
        path = root / 'interactions.db'
        connection = sqlite3.connect(path)
        try:
            for table, columns in REQUIRED_SCHEMA.items():
                definitions = [
                    f'"{column}" {"INTEGER" if column == "id" else "TEXT"}'
                    for column in columns
                ]
                connection.execute(
                    f'CREATE TABLE "{table}" ({", ".join(definitions)})'
                )
            connection.executemany(
                'insert into drugs('
                'id, brand_name, atc_code, atc_class, active_substances, '
                'interactions_text, route, combo_hint'
                ') values (?, ?, ?, ?, ?, ?, ?, ?)',
                [
                    (1, 'Alpha One', 'A01AA01', '', 'Alpha', '', '', ''),
                    (2, 'Alpha Two', 'A01AA01', '', 'Alpha', '', '', ''),
                    (3, 'Conflict One', 'B02BB02', '', 'Beta', '', '', ''),
                    (4, 'Conflict Two', 'B02BB02', '', 'Gamma', '', '', ''),
                    (5, 'Delta One', 'C03CC03', '', 'Delta', '', '', ''),
                    (6, 'Epsilon One', 'D04DD04', '', 'Epsilon', '', '', ''),
                    (7, 'Epsilon Two', 'E05EE05', '', 'Epsilon', '', '', ''),
                    (8, 'Combo One', 'F06FF06', '', 'Theta, Iota', '', '', ''),
                ],
            )
            connection.executemany(
                'insert into substance_brand_map('
                'substance, brand_name, route'
                ') values (?, ?, ?)',
                [
                    ('Alpha', 'Alpha One', ''),
                    ('Alpha', 'Alpha Two', ''),
                    ('Beta', 'Conflict One', ''),
                    ('Gamma', 'Conflict Two', ''),
                    ('Delta', 'Delta One', ''),
                    ('Epsilon', 'Epsilon One', ''),
                    ('Epsilon', 'Epsilon Two', ''),
                    ('Theta', 'Combo One', ''),
                    ('Iota', 'Combo One', ''),
                ],
            )
            connection.commit()
        finally:
            connection.close()
        return path

    def test_unique_reviewed_atc_is_provider_match(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            report = audit_identity_mapping(
                db,
                [SherkoScientificIdentity(1, 'Unrelated name', ('A01AA01',))],
            )

        result = report.results[0]
        self.assertEqual(result.status, STATUS_REVIEWED_ATC_MATCH)
        self.assertEqual(result.provider_atc_codes, ('A01AA01',))

    def test_conflicting_reviewed_atc_is_ambiguous(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            report = audit_identity_mapping(
                db,
                [SherkoScientificIdentity(2, 'Beta', ('B02BB02',))],
            )

        self.assertEqual(
            report.results[0].status,
            STATUS_REVIEWED_ATC_AMBIGUOUS,
        )

    def test_reviewed_atc_combination_is_not_single_identity_match(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            report = audit_identity_mapping(
                db,
                [SherkoScientificIdentity(8, 'Theta', ('F06FF06',))],
            )

        self.assertEqual(
            report.results[0].status,
            STATUS_REVIEWED_ATC_AMBIGUOUS,
        )

    def test_exact_name_without_reviewed_atc_is_review_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            report = audit_identity_mapping(
                db,
                [SherkoScientificIdentity(3, '  DELTA  ', ())],
            )

        self.assertEqual(
            report.results[0].status,
            STATUS_EXACT_NAME_CANDIDATE,
        )

    def test_exact_name_spanning_multiple_atc_codes_is_ambiguous(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            report = audit_identity_mapping(
                db,
                [SherkoScientificIdentity(4, 'Epsilon', ())],
            )

        self.assertEqual(
            report.results[0].status,
            STATUS_AMBIGUOUS_NAME_CANDIDATE,
        )

    def test_unmapped_remains_unmapped(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            report = audit_identity_mapping(
                db,
                [SherkoScientificIdentity(5, 'Zeta', ())],
            )

        self.assertEqual(report.results[0].status, STATUS_UNMAPPED)

    def test_name_normalization_is_equality_oriented_not_fuzzy(self) -> None:
        self.assertEqual(scientific_name_key('  Caféine  '), 'caféine')
        self.assertNotEqual(
            scientific_name_key('Caffeine'),
            scientific_name_key('Cafeine'),
        )

    def test_export_uses_only_reviewed_atc_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'identities.json'
            path.write_text(
                json.dumps(
                    {
                        'schema_version': 1,
                        'identities': [
                            {
                                'scientific_ingredient_id': 7,
                                'preferred_name': 'Alpha',
                                'reviewed_atc_codes': ['A01AA01'],
                            }
                        ],
                    }
                ),
                encoding='utf-8',
            )
            identities = load_identity_export(path)

        self.assertEqual(identities[0].reviewed_atc_codes, ('A01AA01',))

    def test_audit_rejects_incompatible_sdif_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / 'interactions.db'
            connection = sqlite3.connect(db)
            connection.execute('create table drugs(id integer)')
            connection.close()

            with self.assertRaisesRegex(
                SdifMappingAuditError,
                'SDIF contract validation failed',
            ):
                audit_identity_mapping(
                    db,
                    [SherkoScientificIdentity(9, 'Alpha', ())],
                )

    def test_audit_does_not_mutate_provider_database(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            before = db.read_bytes()
            audit_identity_mapping(
                db,
                [SherkoScientificIdentity(10, 'Alpha', ('A01AA01',))],
            )
            after = db.read_bytes()

        self.assertEqual(after, before)

    def test_aggregate_reports_atc_coverage_separately(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            report = audit_identity_mapping(
                db,
                [
                    SherkoScientificIdentity(1, 'Alpha', ('A01AA01',)),
                    SherkoScientificIdentity(2, 'Delta', ()),
                    SherkoScientificIdentity(3, 'Zeta', ()),
                ],
            )

        aggregate = report.aggregate_dict()
        self.assertEqual(aggregate['reviewed_atc_backed_mappings'], 1)
        self.assertEqual(
            aggregate['reviewed_atc_backed_coverage_percent'],
            33.33,
        )
        self.assertEqual(
            aggregate['counts'][STATUS_EXACT_NAME_CANDIDATE],
            1,
        )
        self.assertEqual(aggregate['counts'][STATUS_UNMAPPED], 1)


if __name__ == '__main__':
    unittest.main()
