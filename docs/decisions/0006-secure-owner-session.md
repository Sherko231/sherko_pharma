# Decision 0006 — Supabase owner session in platform secure storage

Status: Accepted for SP-006 repository implementation
Date: 2026-09-24

## Context

Sherko Pharma is an owner-only online application. The Supabase client needs a persisted refreshable session across restarts on Android and Windows, while passwords and privileged server credentials must never be stored by application code. The default Supabase Flutter persistence uses ordinary application preferences, which is not the chosen storage boundary for this project.

No dedicated hosted Sherko Pharma Supabase project/account is currently provisioned, so this decision covers the client implementation and automated platform compilation without claiming real-environment sign-in acceptance.

## Decision

- Use `supabase_flutter 2.17.2` for the client and let its auth client own token refresh/rotation and auth-state events.
- Use `flutter_secure_storage 11.2.0` behind a custom Supabase `LocalStorage` implementation so the persisted Supabase session blob is stored in platform secure storage.
- Require Android minimum SDK 23, matching the selected secure-storage package.
- Supply only the client-safe Supabase project URL and publishable key through Dart defines. Never embed a service-role/secret key, database password, owner password, or real environment values in Git.
- Treat missing/invalid configuration or secure-storage initialization/read failure as signed-out/configuration-blocked. Protected UI must fail closed.
- Use email/password sign-in only; public signup remains disabled server-side and no sign-up UI/call is implemented.
- Clear password input before awaiting sign-in. Do not persist the password.
- Gate the protected shell on an authenticated, non-expired session and auth-state stream events.
- On explicit sign-out, hide protected UI first and use Supabase local sign-out scope so signing out one device does not intentionally revoke the owner's other device sessions.
- Do not make sign-out a catalog save, order reset, or draft mutation. Those data-retention/account-isolation behaviors remain owned by their later tasks.

## Consequences

Authentication/session state is separated from catalog/order persistence and from privileged backend administration. A stolen publishable key is not treated as an authorization secret; SP-004 server checks remain the authorization boundary.

Automated widget/unit tests can prove UI gating and storage-adapter behavior, and hosted builds can prove package compilation. They cannot prove a real Supabase login, OS secure-store durability, network/token refresh, or owner-account provisioning. SP-006 remains incomplete until those real-environment acceptance checks are recorded unless the owner explicitly changes that requirement.
