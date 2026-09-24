# Sherko Pharma — Development Status

Updated: 2026-09-24
Active task: [SP-007 / Issue #17](https://github.com/Sherko231/sherko_pharma/issues/17).
Branch: `feat/sp-007-catalog-search`.
PR: [#18](https://github.com/Sherko231/sherko_pharma/pull/18).
Status: Catalog search/detail implementation and requirement-derived regressions are on the task branch. Final current-revision CI and separate review remain pending.

## Verified baseline

- Protected `main` was `ce62ec623242fb41c3eb46b07997ed501ffbccde` when SP-007 started.
- SP-000 through SP-006 and CI-001 are merged.
- SP-006 post-merge run 36055954368 passed Change scope, Quality, Schema, Android build, Windows build, and Required verification.
- No open Issue or PR existed before SP-007 was authorized.
- The dedicated Sherko Pharma Supabase project remains on the Free plan in `eu-central-1`; SP-003/SP-004 are deployed and the owner mapping is provisioned.
- The hosted catalog currently has 0 products because the real corrected SP-005 source has not been imported. SP-007 does not perform that production import.

## SP-007 implementation

- `SupabaseCatalogRepository` calls only the existing owner-authorized `catalog_search` and `catalog_get` RPCs.
- Search requests are client-bounded to 25 results; the server still enforces its independent maximum of 50.
- Blank search makes no repository call. Typing is debounced by 300 ms and explicit submit runs immediately.
- Search distinguishes initial, loading, results, successful-empty, and retryable error states.
- A monotonically increasing request generation prevents late older search responses/errors from replacing a newer query.
- Selecting a result refreshes the product through `catalog_get` by UUID instead of treating the search row as current detail.
- Product detail has separate loading, not-found, error, and loaded states with equivalent stale-response protection.
- Results/detail display the approved SP-004 fields only; source provenance/internal IDs are not shown as product metadata.
- Arabic values use direction-aware text inside the otherwise English UI.
- Catalog responses are memory-only. No full catalog download, local catalog persistence, create/edit action, order mutation, scanner flow, or new dependency was added.
- Catalog controllers observe authenticated identity changes so protected catalog state resets with the auth boundary.

## Verification in progress

Requirement-derived automated coverage includes:

- exact RPC function/parameter mapping and malformed-response handling;
- client result-limit clamping;
- blank query/no-call behavior;
- successful empty vs server/network error behavior;
- exact Arabic/query forwarding;
- stale search and stale detail response protection;
- detail not-found vs generic error;
- narrow phone Arabic rendering and product detail;
- desktop responsive rendering;
- existing SP-006 auth/shell regressions with catalog repository injection.

Early CI findings were test/analysis harness issues only: callback lint naming was corrected; the Arabic widget assertion was scoped to the result card because the query also appears in the search field; and the missing-value assertion now uses a visible optional detail field because Flutter lazily builds off-screen ListView rows. No product requirement was weakened.

No hardware acceptance applies. The final branch revision must still pass the full Quality, Schema, Android, Windows, and Required verification gates plus separate diff review before merge.
