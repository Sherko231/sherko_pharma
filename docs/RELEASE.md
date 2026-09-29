# Sherko Pharma — Delivery and release procedure

This document defines how to build and package the current initial-delivery scope. It does not publish the application, create store listings, or store production secrets in Git.

## Release identity

- Product/display name: `Sherko Pharma`.
- Flutter package: `sherko_pharma`.
- Current version: `0.1.0`.
- Android application ID and namespace: `com.samo.sherkopharma`.
- Windows executable: `sherko_pharma.exe`; file metadata and window title use `Sherko Pharma`.
- SP-014 Windows external-reader integration is deferred and is not part of this delivery.

Changing the Android application ID after public store distribution creates a different application identity. Verify store-name/package availability before any public submission.

## Runtime configuration

The application requires the dedicated Supabase project URL and modern publishable key at build/run time. Keep repository policy unchanged: do not commit the real URL/key even though the publishable key is intended for client use, and never use a service-role/secret key in the application.

PowerShell:

```powershell
$env:SHERKO_SUPABASE_URL = "<project URL>"
$env:SHERKO_SUPABASE_PUBLISHABLE_KEY = "<sb_publishable_...>"
```

Bash:

```bash
export SHERKO_SUPABASE_URL="<project URL>"
export SHERKO_SUPABASE_PUBLISHABLE_KEY="<sb_publishable_...>"
```

## Android production signing

Release builds intentionally do not fall back to the Flutter debug key. `android/key.properties` and keystore files are ignored by Git and must remain private.

Generate or obtain the owner's long-lived upload/signing key outside the repository. Then create `android/key.properties` locally:

```properties
storePassword=<private store password>
keyPassword=<private key password>
keyAlias=<private key alias>
storeFile=<absolute path to the private .jks/.keystore file>
```

A release build fails if `android/key.properties` is absent or required properties are empty. Use only the owner's external release/upload keystore for a distributable Android build.

Build a configured signed APK from the repository root:

```powershell
flutter build apk --release `
  --dart-define=SUPABASE_URL="$env:SHERKO_SUPABASE_URL" `
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$env:SHERKO_SUPABASE_PUBLISHABLE_KEY"
```

The expected APK is `build/app/outputs/flutter-apk/app-release.apk`. Keep the private keystore and `key.properties` separate from the APK and never commit or distribute the signing material.

For Play Store publication, use the store's current signing/upload-key process and build the requested artifact type with the same external signing configuration. Store submission is outside SP-015.

## Windows release bundle

Build on Windows with Visual Studio 2022 Desktop development with C++ installed:

```powershell
flutter build windows --release `
  --dart-define=SUPABASE_URL="$env:SHERKO_SUPABASE_URL" `
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$env:SHERKO_SUPABASE_PUBLISHABLE_KEY"
```

With the current x64 target, the runnable bundle is under `build\windows\x64\runner\Release\`. Distribute the complete Release directory, not only `sherko_pharma.exe`, because Flutter and plugin DLLs/data are required beside the executable.

A convenient private handoff archive can be created with:

```powershell
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath sherko-pharma-windows-x64-0.1.0.zip
```

The repository does not configure a Windows code-signing certificate. A successful Windows release build is therefore a technical delivery candidate, not evidence of a trusted production-signed executable. Obtain and apply an appropriate code-signing certificate before public distribution if required by the chosen distribution channel.

## Owner-controlled artifacts

Hosted CI is not used. Build and package release candidates locally under owner control.

For an owner-controlled delivery:

1. Build from the reviewed/merged commit.
2. Supply only the client runtime configuration and external signing material required for that platform.
3. Record the exact Git commit and application version.
4. Hash the final artifact/archive locally (for example SHA-256) and record the checksum with the handoff.
5. Keep Android signing keys and any Windows signing certificate/backups in owner-controlled secure storage separate from source control.
6. Do not include the source catalog CSV, generated import SQL, passwords, service-role keys, database URLs, or logs containing tokens.

## Recovery and data boundaries

- Supabase remains authoritative for catalog data. Reinstalling the client does not replace confirmed server edits with the source CSV.
- The controlled source import is insert-only for its approved dataset identity; future reruns use [IMPORT.md](IMPORT.md) and must target an explicitly selected environment.
- Active order state and unfinished edit drafts are device-local, account-scoped session data. Device loss, application-data clearing, or uninstall can remove that local-only state; there is no cloud order/draft backup in the current scope.
- Authentication sessions are stored through platform secure storage. A lost/cleared session requires sign-in again.
- No release procedure should modify production catalog rows merely to prove that a client build starts.

## DDI deployment and distribution gate

The repository contains the SP-030–SP-037 DDI implementation, but that does not by itself activate the feature in the hosted environment or authorize distribution of the provider output.

Before enabling DDI for a hosted/release candidate:

1. Separately authorize and deploy the required repository backend migrations. The current documented hosted baseline is through SP-024; SP-025–SP-028 and SP-031 migration `0013_ddi_ingredient_inputs_api.sql` are not deployed by SP-037.
2. Verify the deployed owner-only DDI ingredient RPC and normalization coverage using non-destructive acceptance checks. Do not use service-role credentials in the app.
3. Build/run the configured Android and Windows candidate and have the owner verify Cart severity states, incomplete/failure states, detail evidence, disclaimer/attribution and browser-link behavior. Repository synthetic tests are not real-device acceptance.
4. Re-check the external provider terms for the intended release. As of the 2026-09-29 re-check, Interaction Checker requires its disclaimer and backlink with displayed output and its September 2026 terms prohibit using the API/output to build or sell a clinical decision-support product.
5. Do not distribute a public/commercial DDI-enabled artifact unless compatible permission/license has been obtained or the provider has been replaced with a source whose terms permit the intended use. Do not silently scrape the website or ship an unlicensed copied dataset as a fallback.

The DDI path sends only trusted normalized ingredient query names to the external provider. Product brand names, barcodes, prices, account/session identity and raw composition are not intended provider inputs, and interaction results are not persisted as medication history.

## Before public/commercial distribution

Do not call an artifact publicly production-ready until all of the following are true for that exact revision/artifact:

- the owner has tested the intended artifact to the level appropriate for the release;
- Android is signed with the owner's real release/upload key;
- Windows code-signing requirements for the chosen channel are resolved if applicable;
- runtime configuration points to the intended hosted environment;
- package/store identity availability and store-specific metadata are confirmed;
- the final artifact checksum and source commit are recorded.
