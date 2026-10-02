# SDIF Development Runtime Selection

Status: SDIF-009 development wiring only. Interaction Checker remains the default Cart DDI provider.
Task: Issue #140
Branch-start SHA: `628f43be84009679390226d39c9c940acba8124f`
Pinned SDIF upstream: `zdavatz/sdif@9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`
Accepted local snapshot SHA-256: `9e5498675acca91097899e66181a27b056cb2026f0d903e686da9cf5c62c3206`

## Purpose

SDIF-009 adds one explicit build-time provider boundary without pretending that SDIF and Interaction Checker return the same clinical/evidence model.

The supported runtime selections are:

```text
interaction_checker
sdif
```

No `DDI_PROVIDER` define means `interaction_checker`.

## Interaction Checker default

The normal runtime remains unchanged:

```text
Cart product IDs
  -> catalog DDI ingredient repository
  -> DdiAnalysisEngine
  -> Interaction Checker client
  -> DdiAnalysisResult
  -> existing Cart DDI presentation
```

This is the only path connected to the current Cart DDI presentation in SDIF-009.

## SDIF development selection

A development build may use:

```text
--dart-define=DDI_PROVIDER=sdif
--dart-define=SDIF_BASE_URI=http://127.0.0.1:3000/
```

That selection wires these typed components into Riverpod:

```text
SdifClient
  -> SdifReviewedAtcBridge
  -> SdifResultAggregator
```

It deliberately does **not** return a `DdiAnalysisGateway` to the current Cart controller. With two or more Cart products, the existing Cart DDI surface therefore enters its already-defined `unavailable` state rather than translating SDIF data into Interaction Checker severities.

This fail-closed state is temporary and intentional. A later bounded task must provide the product-to-reviewed-scientific-identity runtime bridge and an SDIF-native Cart presentation contract before Cart can render SDIF results.

## Configuration validation

`AppRuntimeConfig` validates DDI provider configuration before Supabase initialization.

Rules:

- `DDI_PROVIDER` must be `interaction_checker` or `sdif`.
- `interaction_checker` requires no SDIF URL.
- `sdif` requires an HTTP(S) `SDIF_BASE_URI` with a host and without embedded credentials, query, or fragment.
- SDIF is development-only. Release-mode `DDI_PROVIDER=sdif` is rejected during configuration.
- Invalid configuration blocks application runtime instead of silently falling back to another DDI provider.

The release guard is deliberate. SDIF hosting, provider/source-data distribution rights, snapshot update policy, Android topology, and public/commercial release permission have not been approved by this task.

## Windows development run

First make sure the accepted pinned snapshot already exists by running the bootstrap at least once:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\sdif_bootstrap_windows.ps1
```

Start the pinned SDIF server in a separate PowerShell window:

```powershell
cd .\sdif_working_dir\sdif-pinned
.\target\release\sdif.exe serve --epha --port 3000
```

Then, from the Sherko Pharma repository root in another PowerShell window, run the app with the normal Supabase client-safe defines plus the SDIF development selection:

```powershell
flutter run -d windows `
  --dart-define=SUPABASE_URL=https://PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=CLIENT_SAFE_KEY `
  --dart-define=DDI_PROVIDER=sdif `
  --dart-define=SDIF_BASE_URI=http://127.0.0.1:3000/
```

Do not place service-role/secret keys in this command.

At SDIF-009 the current Cart DDI strip showing `Interaction checking unavailable.` under this selection is expected. It proves the old presentation is not being reused for SDIF; it is not the final SDIF UI.

To return to the existing provider, omit both SDIF defines or explicitly use:

```text
--dart-define=DDI_PROVIDER=interaction_checker
```

## Verification

Focused repository test:

```powershell
flutter test test/ddi_runtime_selection_test.dart test/app_runtime_config_test.dart
```

The test contract covers:

- Interaction Checker default selection;
- valid development SDIF selection;
- release-mode SDIF rejection;
- invalid provider/base-URI rejection;
- AppRuntime configuration propagation;
- Interaction Checker Cart analysis availability under the default selection;
- isolated SDIF client/bridge/aggregator construction;
- current Cart `DdiAnalysisGateway` remaining unavailable under SDIF selection.

The existing real provider acceptance remains separate:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\sdif_runtime_acceptance_windows.ps1
```

## Non-goals retained

SDIF-009 does not:

- resolve arbitrary Cart products to reviewed scientific identities at runtime;
- run SDIF automatically from the current Cart controller;
- define SDIF-native Cart row colors, labels, details, warnings, or notices;
- convert SDIF score/labels to Interaction Checker severity;
- convert `noProviderHitReported` into `none`, `unknown`, or safe;
- modify Supabase schema/data/RPCs;
- remove Interaction Checker;
- choose production/Android SDIF hosting;
- bundle or redistribute SDIF source datasets;
- provide patient-specific recommendations, dose changes, treatment changes, or substitution advice.

## Next bounded task

The next task should add the runtime data bridge from current Cart product IDs to reviewed scientific identities + reviewed ATC metadata, with explicit unmapped/partial coverage. It must remain read-only and conservative.

Only after that data bridge exists should a separate task build an SDIF-native Cart lifecycle/presentation around `hitsObserved` and `noProviderHitReported`.
