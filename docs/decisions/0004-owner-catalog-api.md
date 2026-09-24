# Decision 0004 — Owner-only bounded catalog RPCs

Status: Accepted for SP-004
Date: 2026-09-24

## Context

The application is owner-only and the catalog must not be downloadable through normal client credentials. A UI result limit is not a security boundary if an authenticated client can still query `products` directly. SP-004 also needs exact barcode ambiguity, bounded search, canonical-only mutations, and atomic expected-revision updates.

There is not yet a dedicated hosted Supabase project for Sherko Pharma, so this decision defines the versioned database/auth contract and isolated verification without claiming remote deployment or owner provisioning.

## Decision

- Store the authorized Supabase Auth user UUID in a private singleton server table provisioned per environment.
- Revoke normal `anon` and `authenticated` access to `public.products` and keep RLS enabled as defense in depth.
- Expose only explicit `public.catalog_*` database functions to the `authenticated` role.
- Each catalog function performs a server-side `auth.uid()` owner check before accessing product data.
- Use `SECURITY DEFINER` functions with a fixed `search_path`; keep the private authorization helper and owner mapping unavailable to client roles.
- Bound search and barcode responses server-side. Search has a hard 50-row cap and treats caller text literally.
- Expose only approved canonical fields through create/update functions. Source provenance and revision remain server-owned.
- Apply updates with both product UUID and expected revision in the same SQL statement; stale revisions raise a conflict.
- Disable general, anonymous, email, and SMS signup in versioned Supabase Auth configuration. Hosted application of those settings is a later environment provisioning step.
- Never place service-role/admin keys, database passwords, the real owner UUID, or owner credentials in the client or repository.

## Consequences

Normal application credentials cannot bypass the API result bounds with direct table queries. Barcode ambiguity and optimistic concurrency remain database-enforced. The API surface is deliberately small and can be consumed later by the Flutter repository layer.

`SECURITY DEFINER` functions are privileged code and therefore require fixed search paths, narrow grants, complete permission regression tests, and review whenever changed.

This does not provide an anti-scraping guarantee to an authorized owner, add rate limiting, or prove hosted Supabase configuration. Production provisioning/deployment evidence is separate from this repository implementation.
