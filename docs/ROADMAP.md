# Sherko Pharma — Roadmap

Status: Maintained task-order summary. New implementation still requires explicit owner authorization through one bounded Issue/branch/PR.
Updated: 2026-10-03

## Completed foundation

- SP-000–SP-007: product contract, schema/source mapping, owner-only catalog boundary, controlled import, authentication/session handling and server-backed catalog search/detail.
- SP-008–SP-012: product create/edit, account-scoped edit drafts, manual order calculator, session restoration and scoped catalog/price refresh.
- SP-013 and SP-016–SP-020: Android barcode scanning, compact continuous scanning, deduplication/feedback and whole-amount formatting.
- SP-015: release-mode delivery preparation; Windows external-reader task SP-014 remains deferred.
- SP-021–SP-023: single compact Cart workspace, POS-style adaptive layout and ranked typo-tolerant server search.
- SP-024: normalized manufacturer/dosage-form references and typed SYP/USD currency.

## Completed product relationship work

- SP-025: conservative lexical ingredient normalization without rewriting raw composition.
- SP-026: deterministic ingredient-strength normalization without rewriting raw strength.
- SP-027: conservative pharmaceutical-equivalence metadata with explicit route/form/release completeness requirements.
- SP-028: bounded owner-only alternatives relationship RPC.
- SP-029: reusable Product/Cart alternatives presentation with current-product revalidation before Add-to-cart.

## Completed scientific canonicalization work

- SP-038: production composition-quality audit and scientific canonicalization contract.
- SP-039: private scientific ingredient identity schema.
- SP-040: deterministic lexical cleanup candidates and quarantine rules.
- SP-041: reviewed scientific aliases and exact resolution with provenance/collision guards.
- SP-042: deterministic embedded composition strength/presentation parsing.
- SP-043: complex composition parsing with preserved grouping provenance and separate structure/identity status.
- SP-044: versioned production scientific canonicalization backfill, preservation verification and idempotence evidence.

## Deferred / separately authorized work

The following items are not authorized merely by appearing here:

- Windows external barcode-reader integration after hardware selection.
- Full Arabic interface localization.
- Inventory quantities/stock movement.
- Completed sales/history and historical sale editing/cancellation.
- Fractional-package sales.
- Currency conversion/exchange-rate management.
- Full offline catalog replication, offline pending writes and cloud draft/order synchronization.
- Licensing/activation.
- Separate administration application.
- Further scientific curation/backfill expansion beyond the reviewed current version.
- Public store submission, production signing and distribution-channel work.

## Execution rule

Before implementing any next item:

1. inspect `AGENTS.md` and the live repository state;
2. create or use one owner-approved bounded Issue;
3. create one focused branch from the refreshed default branch;
4. preserve existing catalog/order/session/security contracts;
5. review the final diff separately;
6. merge only when the Issue scope is satisfied and GitHub permits it;
7. verify the remote merge result and stop for the owner's next instruction.
