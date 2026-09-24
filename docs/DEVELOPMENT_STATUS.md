# Sherko Pharma — Development Status

Updated: 2026-09-24
Active task: [SP-006 / Issue #15](https://github.com/Sherko231/sherko_pharma/issues/15).
Branch: `feat/sp-006-owner-auth`.
PR: [#16](https://github.com/Sherko231/sherko_pharma/pull/16).
Status: Client owner-authentication/session implementation passes all repository gates. A dedicated Free hosted Sherko Pharma Supabase environment now exists, SP-003/SP-004 are deployed, and the single confirmed password user is linked as the private owner. Real owner sign-in/session restoration on Android and Windows remains the only acceptance blocker.

## Verified baseline

- Protected `main` was `9838bff5e517ea8d0f211997d4d820b2dced3752` when SP-006 started.
- SP-000 through SP-005 and CI-001 are merged.
- SP-005 post-merge run 36045162705 passed all required gates.
- No open Issue or PR existed before SP-006 was authorized.
- The SP-004 server contract already denies anonymous/non-owner catalog access and disables public signup in versioned configuration.

## SP-006 implementation

- `supabase_flutter 2.17.2` and `flutter_secure_storage 11.2.0` were resolved under Flutter 3.38.7 / Dart 3.10.7 and committed through `pubspec.lock`.
- Android minimum SDK is 23 for the selected secure-storage implementation; Android also explicitly requests Internet permission.
- Supabase URL and client-safe publishable key come from `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` Dart defines. No real project value is committed.
- Missing/invalid configuration fails closed before protected UI appears.
- The Supabase session blob is persisted through custom secure storage rather than default ordinary preferences.
- Secure-storage read/decryption failure returns no session and attempts cleanup; protected UI is not restored from an unreadable value.
- Email/password is the only sign-in flow. No registration/sign-up UI or client sign-up operation exists.
- Protected UI is driven by authenticated, non-expired Supabase session state. Auth signed-out/expired events remove it.
- Sign-out hides protected UI immediately and uses local Supabase sign-out scope; it does not implement catalog/order/draft mutation behavior.
- Password text is cleared from the UI controller before awaiting authentication. Errors are generic and do not echo credentials or tokens.
- Concurrent sign-in submissions are blocked while authentication is in flight.

## Automated verification

Requirement-derived tests cover configuration blocking, signed-out UI, successful/failed sign-in, password clearing, duplicate-submit prevention, immediate sign-out hiding, auth-state sign-out, restored identity, secure-session persistence/removal, and fail-closed unreadable storage.

Android and Windows hosted builds are required on the final revision to establish package/platform compilation. These builds do not substitute for signing in to a real Supabase project.

## External acceptance blocker

A dedicated Free hosted Sherko Pharma Supabase project and owner account now exist and the owner mapping is provisioned. The connected tooling cannot safely supply the owner's password or drive a real Android/Windows GUI login. Therefore:

- real owner email/password sign-in on Android is unverified;
- real owner email/password sign-in on Windows is unverified;
- persisted real Supabase session restoration/refresh across process restarts is unverified end-to-end.

Do not merge/close SP-006 as complete until that environment exists and the required real-platform acceptance is recorded, unless the owner explicitly changes the Issue acceptance contract.
