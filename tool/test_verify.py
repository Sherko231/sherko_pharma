"""Regression tests for decisions that could accidentally bypass merge gates."""

import copy
import unittest
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from verify import dependencies, docs_only, gate, platform_build, quick


class GateTests(unittest.TestCase):
    def setUp(self):
        self.results = {
            "scope": {"result": "success", "outputs": {"scope": "full"}},
            "quality": {"result": "success"},
            "schema": {"result": "success"},
            "android": {"result": "success"},
            "windows": {"result": "success"},
        }

    def test_all_required_jobs_must_succeed(self):
        gate(self.results)
        for job in self.results:
            for status in ("failure", "cancelled", "skipped", ""):
                with self.subTest(job=job, status=status):
                    changed = copy.deepcopy(self.results)
                    changed[job]["result"] = status
                    with self.assertRaises(RuntimeError):
                        gate(changed)

    def test_docs_exemption_still_requires_quality(self):
        self.results["scope"]["outputs"]["scope"] = "docs"
        self.results["schema"]["result"] = "skipped"
        self.results["android"]["result"] = "skipped"
        self.results["windows"]["result"] = "skipped"
        gate(self.results)
        self.results["quality"]["result"] = "skipped"
        with self.assertRaises(RuntimeError):
            gate(self.results)

    def test_invalid_scope_and_missing_jobs_cannot_pass(self):
        self.results["scope"]["outputs"]["scope"] = "unknown"
        with self.assertRaises(RuntimeError):
            gate(self.results)
        self.results["scope"]["outputs"]["scope"] = "full"
        del self.results["windows"]
        with self.assertRaises(KeyError):
            gate(self.results)

    def test_only_known_documentation_is_exempt(self):
        self.assertTrue(docs_only(["README.md", "docs/QUALITY.md"]))
        for paths in ([], ["lib/example.md"], ["docs/script.py"],
                      ["README.md", "lib/main.dart"], [".github/workflows/ci.yml"],
                      ["tool/verify.py"], ["pubspec.lock"], [".flutter-version"]):
            with self.subTest(paths=paths):
                self.assertFalse(docs_only(paths))


class QuickVerificationTests(unittest.TestCase):
    def test_quick_analyzes_and_tests_without_forcing_dart_format(self):
        with patch("verify.dependencies") as dependency_check, patch(
            "verify.run"
        ) as run_command:
            quick()

        dependency_check.assert_called_once_with()
        commands = [call.args for call in run_command.call_args_list]

        self.assertIn(
            (
                "flutter",
                "analyze",
                "--no-pub",
                "--fatal-infos",
                "--fatal-warnings",
            ),
            commands,
        )
        self.assertIn(
            ("flutter", "test", "--no-pub", "--reporter", "expanded"),
            commands,
        )
        self.assertFalse(
            any(command[:2] == ("dart", "format") for command in commands)
        )



class PlatformBuildTests(unittest.TestCase):
    def test_android_gate_builds_release_apk(self):
        with patch("verify.dependencies") as dependency_check, patch(
            "verify.run"
        ) as run_command:
            platform_build("android")

        dependency_check.assert_called_once_with()
        run_command.assert_called_once_with(
            "flutter", "build", "apk", "--release", "--no-pub"
        )

    def test_windows_gate_builds_release_bundle(self):
        with patch("verify.sys.platform", "win32"), patch(
            "verify.dependencies"
        ) as dependency_check, patch("verify.run") as run_command:
            platform_build("windows")

        dependency_check.assert_called_once_with()
        self.assertEqual(
            [call.args for call in run_command.call_args_list],
            [
                ("flutter", "config", "--enable-windows-desktop"),
                ("flutter", "build", "windows", "--release", "--no-pub"),
            ],
        )

    def test_windows_gate_rejects_non_windows_host(self):
        with patch("verify.sys.platform", "linux"):
            with self.assertRaises(RuntimeError):
                platform_build("windows")


class DependencyTests(unittest.TestCase):
    def test_bootstrap_output_is_not_parsed_as_machine_json(self):
        # A fresh Windows SDK can print pub/bootstrap messages before its JSON.
        bootstrapped = False

        def fake_run(*args, capture=False):
            nonlocal bootstrapped
            if args == ("flutter", "--version"):
                bootstrapped = True
                return "Building flutter tool...\nResolving dependencies...\n"
            if args == ("flutter", "--version", "--machine"):
                version = json.dumps({"frameworkVersion": "3.38.7"})
                return version if bootstrapped else "Resolving dependencies...\n" + version
            return ""

        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".flutter-version").write_text("3.38.7\n")
            (root / "pubspec.lock").write_text("synthetic lockfile\n")
            with patch("verify.ROOT", root), patch("verify.run", side_effect=fake_run):
                dependencies()
            self.assertTrue(bootstrapped)


if __name__ == "__main__":
    unittest.main()
