# ADR-0007: Idempotent manual product creation

Status: Accepted
Date: 2026-09-25
Task: [SP-008 / Issue #19](https://github.com/Sherko231/sherko_pharma/issues/19), [PR #20](https://github.com/Sherko231/sherko_pharma/pull/20)

## Context

SP-008 adds product creation through the online owner-only catalog API. The SP-004 `catalog_create` function generates the product UUID inside PostgreSQL. If PostgreSQL commits a create but the client loses the response, the client does not know that UUID and cannot distinguish a failed create from a committed create. Blindly repeating the request could therefore create a duplicate product, which violates the confirmed-write and uncertain-retry rules in `PRODUCT.md`, `ARCHITECTURE.md`, and `QUALITY.md`.

## Options and tradeoffs

1. Keep server-generated identity and allow retry after a transport failure.
   - Smallest change, but cannot prevent duplicate products when the original commit succeeded and only the response was lost.
2. Keep server-generated identity and add a private idempotency-receipt table keyed by a separate operation token.
   - Strong and extensible, but adds another persistent server table and receipt lifecycle that the single-owner current product does not otherwise need.
3. Generate the product UUID once in the client and add an owner-only idempotent create RPC keyed by that UUID.
   - Uses the existing stable UUID identity directly, needs no extra dependency/table, and lets a retry/read reconcile one known product identity.
   - The client becomes responsible for generating a collision-resistant UUID.
4. Never retry uncertain creates.
   - Avoids automatic duplicates but leaves the owner unable to determine whether the product exists without a reliable identity to reconcile.

## Decision and consequences

Use option 3.

- A new-product form generates one RFC4122 version-4-shaped UUID from `Random.secure()`.
- That UUID is retained for the form and reused across reconciliation/safe retry.
- Additive `catalog_create_idempotent` performs the same owner check and canonical insert rules as the existing API.
- First use of the UUID creates exactly one row.
- Exact replay of the same UUID and canonical values returns the existing row.
- Reuse of that UUID with different canonical values raises SQLSTATE `40001`; it never silently changes the existing row.
- Source provenance remains server-owned and null for manual creation.
- The legacy SP-004 `catalog_create` function remains unchanged for compatibility, but the SP-008 client does not use it.
- After an uncertain response, the client reads that UUID through `catalog_get`: matching data confirms success; definite absence makes retry safe; an unreadable result remains uncertain and blocks blind create retry.

This does not broaden catalog access: only the existing authenticated owner role receives execute permission and direct table access remains denied. A future multi-user/offline mutation system may justify a separate operation-receipt model; that remains outside current scope.

## References

- [Product requirements](../PRODUCT.md)
- [Architecture](../ARCHITECTURE.md)
- [Quality gates](../QUALITY.md)
- [Data rules](../DATA_MODEL.md)
- [Owner catalog API decision](0004-owner-catalog-api.md)
- Supabase/PostgREST error handling: https://supabase.com/docs/guides/api/handling-errors-in-supabase-js
