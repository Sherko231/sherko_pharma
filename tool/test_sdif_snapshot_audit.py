from __future__ import annotations

import hashlib
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from sdif_contract import (
    REQUIRED_SCHEMA,
    SDIF_PINNED_COMMIT,
    SDIF_UPSTREAM_REPOSITORY,
)
from sdif_snapshot_audit import (
    PINNED_SOURCE_PATHS,
    PINNED_SOURCE_URLS,
    SdifSnapshotAuditError,
    audit_sdif_snapshot,
)


class SdifSnapshotAuditTest(unittest.TestCase):
    def _database(self, root: Path) -> Path:
        path = root / "interactions.db"
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
            connection.execute(
                "insert into drugs("
                "id, brand_name, atc_code, atc_class, active_substances, "
                "interactions_text, route, combo_hint"
                ") values (?, ?, ?, ?, ?, ?, ?, ?)",
                (1, "Alpha One", "A01AA01", "", "Alpha", "", "", ""),
            )
            connection.execute(
                "insert into substance_brand_map(substance, brand_name, route) "
                "values (?, ?, ?)",
                ("Alpha", "Alpha One", ""),
            )
            connection.commit()
        finally:
            connection.close()
        return path

    def _identity_export(self, root: Path) -> Path:
        path = root / "identities.json"
        path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "identities": [
                        {
                            "scientific_ingredient_id": 1,
                            "preferred_name": "Alpha",
                            "reviewed_atc_codes": ["A01AA01"],
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        return path

    def _source_root(self, root: Path) -> Path:
        checkout = root / "sdif"
        for url, relative_path in PINNED_SOURCE_PATHS.items():
            path = checkout / relative_path
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(("fixture:" + url).encode("utf-8"))
        return checkout

    def _provenance(self, root: Path, db: Path, source_root: Path) -> Path:
        source_hashes = {
            url: hashlib.sha256(
                (source_root / PINNED_SOURCE_PATHS[url]).read_bytes()
            ).hexdigest()
            for url in PINNED_SOURCE_URLS
        }
        path = root / "provenance.json"
        path.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "upstream_repository": SDIF_UPSTREAM_REPOSITORY,
                    "upstream_commit": SDIF_PINNED_COMMIT,
                    "artifact_sha256": hashlib.sha256(db.read_bytes()).hexdigest(),
                    "source_artifacts": [
                        {"url": url, "sha256": source_hashes[url]}
                        for url in PINNED_SOURCE_URLS
                    ],
                }
            ),
            encoding="utf-8",
        )
        return path

    def test_snapshot_report_is_aggregate_and_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = self._database(root)
            identities = self._identity_export(root)

            first = audit_sdif_snapshot(db, identity_export=identities)
            second = audit_sdif_snapshot(db, identity_export=identities)

        self.assertEqual(first.sha256, second.sha256)
        self.assertEqual(first.size_bytes, second.size_bytes)
        self.assertEqual(first.quick_check, "ok")
        self.assertEqual(first.table_row_counts["drugs"], 1)
        self.assertEqual(first.table_row_counts["interactions"], 0)
        self.assertEqual(first.mapping["reviewed_atc_backed_mappings"], 1)
        self.assertEqual(
            first.mapping["reviewed_atc_backed_coverage_percent"],
            100.0,
        )
        payload = json.dumps(first.as_dict())
        self.assertNotIn("Alpha One", payload)
        self.assertNotIn(str(db), payload)

    def test_snapshot_audit_does_not_mutate_provider_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = self._database(root)
            before = db.read_bytes()
            audit_sdif_snapshot(db, identity_export=self._identity_export(root))
            after = db.read_bytes()

        self.assertEqual(after, before)

    def test_incompatible_schema_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = Path(directory) / "interactions.db"
            connection = sqlite3.connect(db)
            try:
                connection.execute("create table drugs(id integer)")
                connection.commit()
            finally:
                connection.close()

            with self.assertRaisesRegex(
                SdifSnapshotAuditError,
                "SDIF contract validation failed",
            ):
                audit_sdif_snapshot(db)

    def test_non_ok_quick_check_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            with patch(
                "sdif_snapshot_audit._run_quick_check",
                return_value=("database disk image is malformed",),
            ):
                with self.assertRaisesRegex(
                    SdifSnapshotAuditError,
                    "quick_check did not return ok",
                ):
                    audit_sdif_snapshot(db)

    def test_provenance_manifest_binds_pinned_commit_sources_and_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = self._database(root)
            source_root = self._source_root(root)
            provenance = self._provenance(root, db, source_root)
            report = audit_sdif_snapshot(
                db,
                provenance_manifest=provenance,
                source_root=source_root,
            )

        self.assertTrue(report.provenance_verified)
        self.assertEqual(
            report.provenance_reason,
            "pinned_commit_artifact_and_source_files_match_manifest",
        )

    def test_wrong_artifact_hash_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = self._database(root)
            source_root = self._source_root(root)
            provenance = self._provenance(root, db, source_root)
            raw = json.loads(provenance.read_text(encoding="utf-8"))
            raw["artifact_sha256"] = "0" * 64
            provenance.write_text(json.dumps(raw), encoding="utf-8")

            with self.assertRaisesRegex(
                SdifSnapshotAuditError,
                "artifact_sha256 does not match",
            ):
                audit_sdif_snapshot(
                    db,
                    provenance_manifest=provenance,
                    source_root=source_root,
                )

    def test_missing_pinned_source_hash_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = self._database(root)
            source_root = self._source_root(root)
            provenance = self._provenance(root, db, source_root)
            raw = json.loads(provenance.read_text(encoding="utf-8"))
            raw["source_artifacts"] = raw["source_artifacts"][:-1]
            provenance.write_text(json.dumps(raw), encoding="utf-8")

            with self.assertRaisesRegex(
                SdifSnapshotAuditError,
                "source artifact set does not match",
            ):
                audit_sdif_snapshot(
                    db,
                    provenance_manifest=provenance,
                    source_root=source_root,
                )

    def test_source_file_hash_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = self._database(root)
            source_root = self._source_root(root)
            provenance = self._provenance(root, db, source_root)
            (source_root / PINNED_SOURCE_PATHS[PINNED_SOURCE_URLS[0]]).write_bytes(
                b"changed-after-manifest"
            )

            with self.assertRaisesRegex(
                SdifSnapshotAuditError,
                "source artifact hash does not match",
            ):
                audit_sdif_snapshot(
                    db,
                    provenance_manifest=provenance,
                    source_root=source_root,
                )

    def test_manifest_requires_source_root(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            db = self._database(root)
            source_root = self._source_root(root)
            provenance = self._provenance(root, db, source_root)

            with self.assertRaisesRegex(
                SdifSnapshotAuditError,
                "requires source_root",
            ):
                audit_sdif_snapshot(db, provenance_manifest=provenance)

    def test_missing_manifest_is_explicitly_unverified_not_assumed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            db = self._database(Path(directory))
            report = audit_sdif_snapshot(db)

        self.assertFalse(report.provenance_verified)
        self.assertEqual(
            report.provenance_reason,
            "provenance_manifest_not_supplied",
        )


if __name__ == "__main__":
    unittest.main()
