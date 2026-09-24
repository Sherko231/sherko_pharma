"""Shared, dependency-free verification entry point; Python 3.11 or newer."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def run(*args, capture=False):
    executable = shutil.which(args[0])
    if not executable:
        raise RuntimeError(f"Required executable is missing: {args[0]}")
    print("+ " + " ".join(args), flush=True)
    result = subprocess.run(
        [executable, *args[1:]], cwd=ROOT, check=True,
        stdout=subprocess.PIPE if capture else None, text=True,
    )
    return result.stdout or ""


def docs_only(paths):
    """Allow only known documentation locations; unknown paths need full CI."""
    return bool(paths) and all(
        path in {"README.md", "AGENTS.md", ".github/pull_request_template.md"}
        or (path.startswith("docs/") and path.endswith(".md"))
        for path in paths
    )


def scope():
    base = os.environ.get("BASE_SHA", "")
    if not re.fullmatch(r"[0-9a-f]{40}", base):
        raise RuntimeError("BASE_SHA must be a full commit SHA")
    paths = run("git", "diff", "--name-only", "--no-renames", "-z", base, "HEAD",
                capture=True).rstrip("\0").split("\0")
    value = "docs" if docs_only(paths) else "full"
    print(f"Verification scope: {value}")
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a", encoding="utf-8") as stream:
            stream.write(f"scope={value}\n")


def check_docs():
    """Check repository-relative inline Markdown file links, without networking."""
    files = [ROOT / "README.md", ROOT / "AGENTS.md", *sorted((ROOT / "docs").rglob("*.md"))]
    checked = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        for target in re.findall(r"\[[^\]\n]*\]\(([^\s)]+)\)", text):
            url = urlsplit(target.strip("<>"))
            if url.scheme or url.netloc or not url.path:
                continue
            destination = (path.parent / unquote(url.path)).resolve()
            if not destination.is_relative_to(ROOT) or not destination.exists():
                raise RuntimeError(f"Broken repository link in {path.relative_to(ROOT)}: {target}")
            checked += 1
    print(f"Documentation: {len(files)} files, {checked} relative file links checked.")
    print("External URLs, anchors, reference-style links, and semantic consistency require review.")


def dependencies():
    expected = (ROOT / ".flutter-version").read_text().strip()
    # Fresh Windows installs emit bootstrap/pub text on their first invocation.
    # Complete that checked invocation before requesting a clean JSON response.
    run("flutter", "--version")
    actual = json.loads(run("flutter", "--version", "--machine", capture=True))
    if actual["frameworkVersion"] != expected:
        raise RuntimeError(f"Use Flutter {expected}; found {actual['frameworkVersion']}")
    before = (ROOT / "pubspec.lock").read_bytes()
    run("flutter", "pub", "get", "--enforce-lockfile")
    if (ROOT / "pubspec.lock").read_bytes() != before:
        raise RuntimeError("Dependency resolution changed pubspec.lock; review and commit it explicitly")


def quick(test_path=None):
    dependencies()
    run("flutter", "analyze", "--no-pub", "--fatal-infos", "--fatal-warnings")
    args = ["flutter", "test", "--no-pub", "--reporter", "expanded"]
    if test_path:
        args.append(test_path)
    run(*args)


def gate(results):
    """Reject failed/cancelled/missing jobs; skipped builds need a docs exemption."""
    if results["scope"]["result"] != "success":
        raise RuntimeError("Scope job did not pass")
    classification = results["scope"]["outputs"].get("scope")
    if classification not in {"docs", "full"}:
        raise RuntimeError("Missing or invalid verification scope")
    expected = {"quality": "success", "android": "success", "windows": "success"}
    if classification == "docs":
        expected.update(android="skipped", windows="skipped")
    for job, result in expected.items():
        if results[job]["result"] != result:
            raise RuntimeError(f"{job}: expected {result}, got {results[job]['result']}")
    print(f"Required verification passed ({classification}).")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["docs", "scope", "quick", "android", "windows", "gate"])
    parser.add_argument("--test", help="Targeted feedback only; omit for the full regression suite")
    args = parser.parse_args()
    if args.test and args.mode != "quick":
        parser.error("--test is supported only with quick")
    if args.mode == "docs":
        check_docs()
    elif args.mode == "scope":
        scope()
    elif args.mode == "quick":
        quick(args.test)
    elif args.mode == "gate":
        gate(json.loads(os.environ["JOB_RESULTS"]))
    else:
        if args.mode == "windows" and sys.platform != "win32":
            raise RuntimeError("Windows builds require Windows and Visual Studio C++ desktop tools")
        dependencies()
        if args.mode == "android":
            run("flutter", "build", "apk", "--debug", "--no-pub")
        else:
            run("flutter", "config", "--enable-windows-desktop")
            run("flutter", "build", "windows", "--release", "--no-pub")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, KeyError, ValueError, OSError) as error:
        print(f"Verification failed: {error}", file=sys.stderr)
        sys.exit(1)
