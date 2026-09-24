"""Regression tests for decisions that could accidentally bypass merge gates."""

import copy
import unittest

from verify import docs_only, gate


class GateTests(unittest.TestCase):
    def setUp(self):
        self.results = {
            "scope": {"result": "success", "outputs": {"scope": "full"}},
            "quality": {"result": "success"},
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


if __name__ == "__main__":
    unittest.main()
