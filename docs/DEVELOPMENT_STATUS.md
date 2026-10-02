# Sherko Pharma — Development Status

Updated: 2026-10-03
Default branch: `main`

This document records the maintained current implementation state. For task execution, always refresh the live default branch, open Issues/PRs and the active Issue before relying on this summary.

## Product state

Sherko Pharma is an online-first Flutter application for Android and Windows. The authenticated owner works primarily in one compact Cart workspace that combines server-backed catalog search, Android camera scanning, customer-order lines, quantity controls, New Order and separate SYP/USD totals.

Implemented product behavior includes:

- owner email/password authentication with secure local session storage;
- bounded owner-authorized catalog search/detail/create/update;
- revision-based optimistic conflict handling;
- account-scoped persistent unfinished edit drafts with no automatic upload;
- exact-text dual-barcode lookup and Android continuous camera scanning;
- exact integer order arithmetic with separate SYP/USD totals;
- account-scoped active-order restoration;
- scoped current-data refresh with explicit price/currency adoption;
- compact unified Cart UI and ranked typo-tolerant search;
- normalized manufacturer/dosage-form references and typed currency;
- conservative ingredient/strength/equivalence derivation;
- bounded catalog alternatives groups and reusable alternatives UI;
- reviewed scientific canonicalization with deterministic parsing/curation and a versioned production backfill.

Windows external-reader integration remains deferred. Inventory, sales history, offline catalog replication, licensing, currency conversion, fractional-package sales, full Arabic localization and a separate administration application remain outside the current implemented scope.

## Catalog and backend state

The dedicated hosted environment contains the approved corrected source import with 23,750 source rows. The private source CSV is not committed.

Supabase remains authoritative for catalog data. Client catalog access uses bounded owner-authorized APIs rather than direct private-table access. Product edits use expected revisions and confirmed persistence; no offline pending-write queue exists.

The derived catalog stack preserves authoritative raw composition/strength fields while maintaining private lexical ingredient, ingredient-strength, pharmaceutical-equivalence and scientific canonicalization data.

The scientific canonicalization sequence SP-038–SP-044 is implemented. Production backfill version 1 completed with preservation and idempotence evidence recorded in `SCIENTIFIC_CANONICALIZATION_BACKFILL.md`. Normal client roles do not receive direct access to the private scientific tables/functions.

The repository migration numbering contains historical gaps where retired feature migrations were removed from the current tree. Do not infer a required migration from sequence numbering alone; inspect actual dependencies before any deployment. Production may contain retired schema objects from earlier revisions; deleting production objects is a separate destructive operation and is never implied by repository cleanup.

## Client state

The runtime requires only the configured Supabase URL and publishable key. Missing/invalid configuration fails closed.

The current client initialization wires authentication, catalog access, secure edit-draft storage and account-scoped application-session storage. The Cart UI contains catalog acquisition, order summary/lines, quantity/remove controls, price-change notices and scanner integration.

Release signing remains external: Android production builds require the owner's private signing configuration; Windows public distribution may require a separately chosen code-signing/distribution path.

## Scientific data state

The scientific layer is deliberately separate from source text and the SP-025 lexical ingredient registry.

Current reviewed capabilities include:

- stable private scientific identities and parent/form relationships;
- reviewed references and exact aliases with provenance;
- deterministic lexical cleanup candidates;
- embedded composition strength/presentation parsing;
- complex grouped/parenthesized composition parsing;
- versioned product canonicalization nodes/summaries;
- explicit trusted/high-confidence/needs-review/unresolved states;
- aggregate coverage and idempotence verification.

Deterministic cleanup, string similarity or parsing alone does not establish scientific truth. Ambiguous tokens, formulas, botanicals, structural syntax and context-dependent forms remain quarantined until reviewed evidence supports a mapping.

## Verification policy

Hosted GitHub Actions CI and Required verification are intentionally retired. `docs/QUALITY.md` lists optional local commands. Unrun local commands are not merge blockers unless the owner explicitly requires them for a task.

Owner real-device testing may occur after merge. A reproducible reported failure becomes a separate bounded fix task and should receive a focused regression test when practical.

## Production-sensitive boundary

Repository work must not silently perform production deployment or destructive cleanup. Explicit owner approval is required for a concrete production data deletion/transformation, access-policy broadening, privileged credential use or similarly sensitive action.

## Handoff rule

For every implementation task:

- one approved Issue;
- one focused branch;
- one PR;
- separate final diff review recorded honestly;
- merge only when scope is satisfied and GitHub permits it;
- verify the remote merge SHA;
- report what changed, checks actually run and limitations, then stop for the owner's next explicit instruction.
