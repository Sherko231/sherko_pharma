# Sherko Pharma — Development Status

Updated: 2026-09-24
Active task: [SP-006 / Issue #15](https://github.com/Sherko231/sherko_pharma/issues/15).
Branch: `feat/sp-006-owner-auth`.
PR: [#16](https://github.com/Sherko231/sherko_pharma/pull/16).
Status: Client owner-authentication/session implementation passes all repository gates. A dedicated Free hosted Sherko Pharma Supabase environment exists, SP-003/SP-004 are deployed, and the single confirmed password user is linked as the private owner. Real Windows acceptance passed on 2026-09-24. The owner explicitly deferred physical Android acceptance; Android remains covered by automated tests/builds but is not claimed as physically verified.

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

Hosted Windows acceptance passed: owner sign-in succeeded, a real session restored after process restart, explicit sign-out returned to the login gate, and a subsequent restart did not restore protected UI. The owner explicitly changed the acceptance contract on 2026-09-24 to defer physical Android acceptance. Android login/session behavior is therefore not claimed as physically verified; only automated widget/unit coverage and the hosted Android build are recorded for this task.
