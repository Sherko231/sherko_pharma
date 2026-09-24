# SP-006 hosted authentication acceptance

The repository implementation is complete. Windows real-environment acceptance passed. The owner explicitly deferred physical Android acceptance for this task; Android remains an explicit follow-up rather than a merge blocker.

## Hosted environment

A dedicated Sherko Pharma Supabase project has been provisioned on the Free plan. The SP-003 schema and SP-004 owner-only catalog API have been applied, and the single confirmed password user has been linked to the private owner mapping.

Do not commit the real project URL, publishable key, owner email, or password.

## Prepare local runtime values

Copy the Project URL and the modern publishable key (`sb_publishable_...`) from the Supabase Dashboard into temporary shell environment variables. Do not use the legacy service-role/secret key.

PowerShell example:

```powershell
$env:SHERKO_SUPABASE_URL = "<project URL>"
$env:SHERKO_SUPABASE_PUBLISHABLE_KEY = "<sb_publishable_...>"
```

## Windows acceptance

Run:

```powershell
flutter run -d windows `
  --dart-define=SUPABASE_URL="$env:SHERKO_SUPABASE_URL" `
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$env:SHERKO_SUPABASE_PUBLISHABLE_KEY"
```

Verify:

1. Login screen appears and there is no registration control.
2. Sign in with the pre-provisioned owner email/password.
3. The protected Sherko Pharma shell appears.
4. Close the application completely and launch the same configured command again.
5. The protected shell restores without re-entering the password.
6. Sign out.
7. The login screen appears immediately.
8. Close/reopen again and confirm the protected shell does not restore.

Never paste the owner password into GitHub, terminal history, logs, screenshots, or ChatGPT.

## Android acceptance — deferred by owner

Connect/select an Android device, find its device ID with `flutter devices`, then run:

```powershell
flutter run -d <ANDROID_DEVICE_ID> `
  --dart-define=SUPABASE_URL="$env:SHERKO_SUPABASE_URL" `
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$env:SHERKO_SUPABASE_PUBLISHABLE_KEY"
```

Repeat the same eight checks from the Windows acceptance section when Android physical acceptance is resumed. Until then, do not claim Android real sign-in/session persistence as verified.

## Evidence to record

Recorded for SP-006:

- Windows login: PASS
- Windows restart session restore: PASS
- Windows sign-out persistence: PASS
- Android login: DEFERRED
- Android restart session restore: DEFERRED
- Android sign-out persistence: DEFERRED

Do not record credentials, tokens, session blobs, or screenshots containing secrets.

Owner acceptance change: physical Android verification is explicitly deferred and is not a requirement for merging SP-006. Automated Android build/tests remain required and already pass.
