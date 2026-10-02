# SDIF Runtime Transport Boundary

Status: SDIF-006 typed transport only. The active Cart DDI runtime remains Interaction Checker.
Task: Issue #130
Branch-start SHA: `0a3109c81d26a79cd7f2b76cd0c862639a1291c1`
Pinned upstream: `zdavatz/sdif@9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`

## Purpose

SDIF-005 proved on the owner's Windows machine that the pinned SDIF source can build a real provider snapshot and that Sherko Pharma's three currently reviewed scientific identities have reviewed-ATC-backed provider coverage `3/3 (100%)` against that snapshot.

SDIF-006 begins runtime work by adding only the provider-specific HTTP transport boundary. It deliberately does not replace the existing `InteractionCheckerClient`, does not change Riverpod wiring, does not change Cart presentation, and does not convert SDIF severity into Sherko Pharma's current Interaction Checker severity model.

## Why SDIF is not plugged into `InteractionCheckGateway`

The existing `InteractionCheckGateway` returns `InteractionCheckResult`, whose contract is built around Interaction Checker:

- every submitted query is explicitly resolved or unresolved;
- every resolved unordered pair must be returned exactly once;
- every pair has one of `major|moderate|minor|none|unknown`;
- pair counts are checked against the provider summary;
- provider-specific evidence/source/disclaimer fields are carried through the current UI.

Pinned SDIF `/api/check` has a materially different contract:

```json
{"drugs":["Ponstan","Marcoumar"]}
```

and returns:

```text
basket[]
interactions[]
```

`basket[]` contains resolved provider drug records. `interactions[]` contains detected hits only. SDIF does not return a normalized row for every resolved pair and does not define an Interaction-Checker-style `none` or `unknown` result when no hit is emitted.

Treating an omitted SDIF pair as `none` or `unknown` would therefore be an invented clinical semantic. SDIF-006 does not do that.

## Provider-native model

The repository now models SDIF independently through:

```text
lib/features/interactions/domain/sdif_models.dart
lib/features/interactions/data/sdif_client.dart
```

The model preserves these pinned provider fields without converting them into the current app severity model.

### Exact ATC lookup

`GET /api/search-drugs?atc=<code>` parses:

- `brand_name`;
- `atc_code`;
- `substances`.

This transport accepts a reviewed ATC code as input. It does not infer an ATC code from a Syrian brand or raw composition.

### Basket check

`POST /api/check` parses:

- `basket[].brand`;
- `basket[].atc_code`;
- `basket[].substances`;
- `interactions[].drug_a`;
- `interactions[].drug_a_atc`;
- `interactions[].drug_a_route`;
- `interactions[].drug_b`;
- `interactions[].drug_b_atc`;
- `interactions[].drug_b_route`;
- `interactions[].interaction_type`;
- `interactions[].severity_score`;
- `interactions[].severity_label`;
- `interactions[].severity_indicator`;
- `interactions[].keyword`;
- `interactions[].description`;
- `interactions[].explanation`;
- `interactions[].source`;
- `interactions[].combo_hint`.

Interaction families remain provider-native:

- `substance`;
- `class-level`;
- `CYP`;
- `epha`.

A future unknown interaction family fails explicitly instead of being silently flattened into one of these four.

## Severity boundary

`severity_score`, `severity_label`, and `severity_indicator` are preserved exactly as SDIF response fields.

They are **not** translated to:

```text
major
moderate
minor
none
unknown
```

The pinned SDIF implementation combines several evidence paths, including Swiss-label keyword scoring and optional EPha risk-class data. A later bounded semantics task must decide how Sherko Pharma presents those provider-native values and how duplicate/asymmetric hits are aggregated. That task must be based on real result comparison rather than numeric-name similarity.

An empty SDIF `interactions` array is valid transport data. SDIF-006 represents it as an empty list only. It is not converted to a safety claim.

## Transport behavior

`SdifClient` requires an explicit absolute HTTP(S) base URI. There is intentionally no hidden production default.

Example local development construction:

```dart
final client = SdifClient(
  baseUri: Uri.parse('http://127.0.0.1:3000/'),
);
```

This example is a transport configuration only. It is not wired into the application providers by SDIF-006.

The client applies local defensive bounds:

- ATC lookup input must be nonblank and at most 32 characters;
- basket checks require 2–10 nonblank provider inputs;
- each basket input is at most 80 characters;
- leading/trailing whitespace is removed before transport.

The 2–10 basket limit is a Sherko Pharma local guard for this first adapter. It is not claimed as an upstream SDIF API limit.

The client distinguishes:

- invalid local request;
- timeout;
- HTTP transport failure;
- non-2xx API response;
- malformed success JSON/schema;
- unsupported provider interaction family.

Additive unknown JSON fields are ignored.

## No runtime switch in this task

SDIF-006 does not modify:

```text
interactionCheckGatewayProvider
DdiAnalysisEngine
DdiCartController
Cart DDI UI
```

The app therefore continues to use Interaction Checker exactly as before this task.

No Supabase migration, data write, scientific mapping mutation, provider database bundling, or source-dataset redistribution is part of SDIF-006.

## Focused verification

Repository test:

```text
flutter test test/sdif_client_test.dart
```

The HTTP fixture coverage verifies:

- exact reviewed-ATC request shape;
- `/api/check` request shape;
- all four pinned SDIF interaction families;
- provider-native severity score/label/indicator preservation;
- empty interaction-list behavior;
- additive unknown fields;
- invalid-request fail-closed behavior;
- malformed JSON/required-field handling;
- unsupported interaction-family handling;
- non-2xx API status;
- timeout versus transport failure;
- absolute HTTP(S) base URI validation.

These are synthetic transport tests and make no new claim about clinical completeness.

## Next bounded runtime task

The next task should use the real owner-local SDIF server and the reviewed Sherko identity bridge to compare provider-native results for a small acceptance set before any Cart switch.

That task should decide, with explicit tests:

1. how a reviewed scientific identity plus reviewed ATC selects an SDIF provider drug deterministically;
2. how multiple SDIF hits for one product pair are retained/deduplicated;
3. what provider-native severity/risk presentation is appropriate;
4. how absence of hits is described without inventing `none`/`safe` semantics;
5. whether SDIF runs locally, behind a controlled service, or another deployment boundary before Android use.
