# SDIF Cart Presentation

Status: SDIF-013 provider-native Cart presentation for the development-only SDIF runtime.
Task: Issue #148
Functional tree baseline: SDIF-012 merge `0ae5ac7451bb6dbdcf01c157a51c1b70b3aae02f`
Branch-start SHA: `2affeb060eb8fdb7b25c318e9bf89af3434651fd` (same tree as the functional baseline; see Issue #148 for the temporary no-op cleanup history).

## Purpose

SDIF-013 exposes the already-running SDIF Cart analysis from SDIF-012 without translating it into the Interaction Checker result model.

When the explicit development runtime selects SDIF, the Cart presents:

- SDIF loading, ready, failure and unavailable lifecycle states;
- product-pair observations with provider findings;
- product-pair observations where no provider hit was reported;
- unchecked product pairs caused by scientific/provider coverage gaps;
- per-product scientific input coverage and provider-resolution gaps;
- provider-native finding details.

Interaction Checker remains the default runtime and its existing Cart presentation is unchanged.

## No severity conversion

SDIF provider-native severity is not mapped to Interaction Checker:

```text
major
moderate
minor
none
unknown
```

The Cart-level SDIF presentation distinguishes only:

```text
provider findings observed
no provider hit reported
unchecked / incomplete coverage
runtime failure
```

A row with provider findings may receive one neutral attention treatment. That treatment represents the presence of provider findings, not a converted clinical severity class.

Raw SDIF severity score, label and indicator remain visible only inside the SDIF detail surface as provider-native metadata.

## No-hit semantics

The exact compact row wording is:

```text
No provider hit
```

Ready presentation also states:

```text
No provider hit is not a safety classification.
```

The presentation never renders SDIF no-hit as:

- no interaction;
- safe;
- compatible;
- clinically insignificant;
- Interaction Checker `none` or `unknown`.

## Product-pair accounting

Each unordered Cart product pair belongs to one presentation bucket.

### Findings

At least one provider-checked scientific identity pair has `hitsObserved`.

### No provider hit

The product pair has at least one provider-checked scientific identity pair and none of those checked pairs has provider findings.

### Unchecked

The product pair has zero provider-checked scientific identity pairs.

Unchecked does not mean a negative interaction result. It can result from partial/unmapped/missing scientific inputs, provider-resolution gaps, or products that expose no distinct eligible scientific identity pair.

A product pair can have checked observations while one of its products still has incomplete coverage. Coverage remains an independent dimension and is never hidden by a findings/no-hit observation.

## Product-row presentation

Each row can show a compact primary SDIF badge:

- `SDIF findings · N pair(s)` when at least one related product pair has findings;
- `No provider hit · N pair(s)` when checked related pairs exist and none has findings.

Rows can additionally show explicit coverage badges:

- `Partial scientific coverage`;
- `Scientific identity unmapped`;
- `Product mapping missing`;
- `SDIF mapping incomplete`;
- `Unchecked pairs · N`.

A complete row with provider-checked no-hit observations stays visually neutral. A row receives the SDIF attention treatment only when provider findings are observed.

Quantity, price, remove, New Order, scanner and captured-total behavior are unchanged.

## Ready summary

The SDIF Cart status surface uses provider-neutral pair counts:

```text
N findings
N no provider hit
N unchecked
N incomplete
```

No provider-native score is promoted into a Cart-level severity rank.

The no-hit safety clarification remains visible directly below the ready summary.

## Detail sheet

A tappable SDIF row badge opens an informational detail sheet for that Cart product without starting a new provider/backend request.

For each related product pair it shows:

- both current Cart product display names;
- every provider-checked scientific identity pair;
- `Provider findings observed` or `No provider hit reported` per scientific pair;
- interaction family;
- provider-native severity score, label and indicator;
- source;
- direction for directional SDIF evidence;
- keyword, description, explanation and combination hint when supplied;
- explicit unchecked wording when no scientific identity pair could be provider-checked.

The sheet also reports the focused product's scientific-input coverage and relevant provider-resolution gaps.

The detail header states that the evidence is provider-native and informational, and that no provider hit is not a safety classification or patient-specific recommendation.

No treatment, dose, stop/start or substitution recommendation is generated.

## Failure presentation

SDIF failure remains non-destructive. The Cart distinguishes broad failure categories without exposing medication/provider payloads:

- scientific-input failure;
- timeout;
- transport/provider unavailable;
- provider HTTP failure;
- malformed provider response;
- mapping/integrity failure;
- unknown failure.

Retry reuses the SDIF-012 stale-safe lifecycle. Cart membership, quantities, prices and totals remain unchanged.

## Runtime boundary

`OrderScreen` selects presentation by `DdiRuntimeSelection`:

```text
interaction_checker -> existing DDI presentation
sdif                -> SDIF-native presentation
```

The `DdiCartController` and `SdifCartController` remain separate. SDIF results are never converted into `DdiAnalysisResult` merely for display.

SDIF remains development-only under the existing runtime configuration guard.

## Focused verification

Pure presentation regression:

```powershell
flutter test test/sdif_cart_presentation_test.dart
```

Widget regression:

```powershell
flutter test test/sdif_cart_visuals_test.dart
```

Detail regression:

```powershell
flutter test test/sdif_interaction_detail_sheet_test.dart
```

Existing Interaction Checker visual regression should also remain green:

```powershell
flutter test test/ddi_cart_visuals_test.dart
```

The focused SDIF tests verify no-hit wording, incomplete coverage, provider-native finding metadata, Retry behavior, unchanged Cart totals and absence of Interaction Checker severity labels as SDIF classifications.

## Non-goals retained

SDIF-013 does not:

- change SDIF scientific/provider resolution or batching;
- infer scientific identities or ATC codes;
- change production schema/data;
- convert SDIF severity into Interaction Checker severity;
- enable SDIF in release mode;
- start or install the local SDIF server;
- bundle or redistribute provider datasets;
- define patient-specific clinical recommendations.
