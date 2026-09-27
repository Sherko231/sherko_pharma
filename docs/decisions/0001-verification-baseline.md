# ADR-001: Reproducible verification before feature development

Status: Superseded by OPS-001 / Issue #42 on 2026-09-27
Date: 2026-09-24
Task: [Issue #3](https://github.com/Sherko231/sherko_pharma/issues/3)

## Historical decision

SP-001 originally introduced a pinned Flutter baseline, shared verification helpers, hosted GitHub Actions and a required aggregate status. That policy was useful during the initial implementation phase and its historical evidence remains in Git history.

## Current decision

The owner later chose to retire hosted GitHub Actions and mandatory CI gates.

- Keep Flutter/toolchain pins and the committed lockfile.
- Keep `tool/verify.py`, tests and import helpers as optional local engineering tools.
- Do not require GitHub Actions, a Required verification status, or post-merge hosted checks.
- The owner may pull/test merged revisions locally and report problems for bounded follow-up fixes.
- Production secrets, privileged keys and the private source catalog remain excluded from Git.
- Real production signing remains owner-controlled.

This document is retained only to explain the historical bootstrap. [QUALITY.md](../QUALITY.md) owns the current no-CI verification policy.
