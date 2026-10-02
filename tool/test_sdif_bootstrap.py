from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from sdif_bootstrap import (
    CURRENT_REVIEWED_IDENTITIES,
    SdifBootstrapError,
    _download,
    _require_commands,
    _safe_extract_zip,
    _transport_urls,
    identity_export_payload,
    provenance_payload,
)
from sdif_snapshot_audit import PINNED_SOURCE_PATHS


class SdifBootstrapTest(unittest.TestCase):
    def test_identity_export_is_current_and_minimal(self) -> None:
        payload = identity_export_payload()
        self.assertEqual(payload["schema_version"], 1)
        self.assertEqual(
            payload["identities"],
            [dict(item) for item in CURRENT_REVIEWED_IDENTITIES],
        )
        self.assertEqual(
            [item["preferred_name"] for item in payload["identities"]],
            ["Amoxicillin", "Caffeine", "Paracetamol"],
        )
        self.assertEqual(
            [item["reviewed_atc_codes"] for item in payload["identities"]],
            [["J01CA04"], ["N06BC01"], ["N02BE01"]],
        )
        for item in payload["identities"]:
            self.assertEqual(
                set(item),
                {
                    "scientific_ingredient_id",
                    "preferred_name",
                    "reviewed_atc_codes",
                },
            )

    def test_provenance_hashes_actual_database_and_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source_root = root / "sdif"
            source_root.mkdir()
            for index, relative_path in enumerate(PINNED_SOURCE_PATHS.values()):
                path = source_root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(f"source-{index}".encode("utf-8"))
            database = source_root / "db" / "interactions.db"
            database.write_bytes(b"provider-db")

            payload = provenance_payload(database, source_root)

        self.assertEqual(
            payload["artifact_sha256"],
            hashlib.sha256(b"provider-db").hexdigest(),
        )
        by_url = {item["url"]: item["sha256"] for item in payload["source_artifacts"]}
        self.assertEqual(set(by_url), set(PINNED_SOURCE_PATHS))
        for index, url in enumerate(PINNED_SOURCE_PATHS):
            self.assertEqual(
                by_url[url],
                hashlib.sha256(f"source-{index}".encode("utf-8")).hexdigest(),
            )

    def test_provenance_rejects_missing_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            database = root / "interactions.db"
            database.write_bytes(b"db")
            with self.assertRaisesRegex(
                SdifBootstrapError,
                "Pinned source artifact is missing",
            ):
                provenance_payload(database, root)

    def test_http_sources_try_canonical_then_https(self) -> None:
        self.assertEqual(
            _transport_urls("http://pillbox.oddb.org/atc.csv"),
            (
                "http://pillbox.oddb.org/atc.csv",
                "https://pillbox.oddb.org/atc.csv",
            ),
        )
        self.assertEqual(
            _transport_urls("https://example.test/source"),
            ("https://example.test/source",),
        )

    def test_existing_download_is_reused_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "source.zip"
            destination.write_bytes(b"existing")
            with patch("sdif_bootstrap.urllib.request.urlopen") as urlopen:
                transport = _download(
                    "http://pillbox.oddb.org/source.zip",
                    destination,
                    refresh=False,
                )
        self.assertEqual(transport, "existing")
        urlopen.assert_not_called()

    def test_safe_zip_extract_rejects_path_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "bad.zip"
            with zipfile.ZipFile(archive, "w") as handle:
                handle.writestr("../outside.txt", "unsafe")
            with self.assertRaisesRegex(SdifBootstrapError, "Unsafe path"):
                _safe_extract_zip(archive, root / "out")
        self.assertFalse((root / "outside.txt").exists())

    def test_safe_zip_extract_accepts_normal_member(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "good.zip"
            with zipfile.ZipFile(archive, "w") as handle:
                handle.writestr("nested/file.txt", "ok")
            _safe_extract_zip(archive, root / "out")
            self.assertEqual((root / "out" / "nested" / "file.txt").read_text(), "ok")

    def test_missing_required_command_fails_closed(self) -> None:
        with patch("sdif_bootstrap.shutil.which", return_value=None):
            with self.assertRaisesRegex(
                SdifBootstrapError,
                "Missing required command",
            ):
                _require_commands(("git", "cargo"))


if __name__ == "__main__":
    unittest.main()
