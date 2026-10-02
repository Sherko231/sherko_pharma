# SDIF Provider-Native Result Semantics

Status: SDIF-008 provider-native aggregation only. The active Cart DDI runtime remains Interaction Checker.
Task: Issue #134
Branch-start SHA: `62a7280306c8b826b3d0207cce180df82f1289ef`
Pinned upstream: `zdavatz/sdif@9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`
Accepted owner-local snapshot SHA-256: `9e5498675acca91097899e66181a27b056cb2026f0d903e686da9cf5c62c3206`

## Purpose

SDIF-008 defines how Sherko Pharma represents a validated SDIF `/api/check` result before any Cart/provider switch.

The layer sits after SDIF-007:

```text
reviewed Sherko scientific identities
  -> reviewed ATC lookup
  -> exact SDIF provider selections
  -> verified SDIF basket/check result
  -> SDIF-008 provider-native pair aggregation
```

It does not translate SDIF into the current Interaction Checker result model.

## Pinned provider behavior

The pinned SDIF source constrains this aggregation model.

For each unordered basket pair, `src/web.rs` performs:

1. substance matching from A's Swissmedic FI toward B;
2. substance matching from B's Swissmedic FI toward A;
3. class-level matching from A toward B;
4. class-level matching from B toward A;
5. CYP matching from A toward B;
6. CYP matching from B toward A;
7. optional EPha lookup by the unordered ATC pair.

Therefore `substance`, `class-level`, and `CYP` hits can be directional/asymmetric evidence. An A -> B hit and a B -> A hit are not duplicates merely because they belong to the same unordered pair.

EPha is queried by `(atc1 = A AND atc2 = B) OR reversed` with `LIMIT 1`, so its returned hit is pair-level rather than evidence extracted independently from both drug labels.

The provider sorts returned hits by `severity_score` descending.

## Provider-native severity

Pinned SDIF exposes one numeric field plus raw provider labels:

```text
severity_score
severity_label
severity_indicator
source
```

Swissmedic FI text is keyword-scored by SDIF on a 0..3 scale:

- 3: `Kontraindiziert`
- 2: `Schwerwiegend`
- 1: `Vorsicht`
- 0: `Keine Einstufung`

EPha risk classes are mapped by the pinned SDIF implementation into the same numeric field:

- X -> 3
- D -> 2
- C/B -> 1
- A -> 0

This numeric scale is therefore safe to use for deterministic ordering and summary **inside this pinned SDIF provider contract only**.

It is not converted to Interaction Checker:

```text
major
moderate
minor
none
unknown
```

A pair can also have multiple top-score raw labels/sources. SDIF-008 retains all distinct top-score `(score, label, indicator, source)` observations instead of selecting one label as universal truth.

## Pair observation state

Every unordered checked scientific-identity pair exists exactly once in `SdifAggregatedResult.pairs`, even if SDIF emitted no hit for that pair.

The only observation states are:

```text
hitsObserved
noProviderHitReported
```

`noProviderHitReported` means only that the pinned SDIF check returned no interaction hit for that pair in this request/snapshot/configuration.

It does **not** mean:

- no interaction exists;
- clinically insignificant;
- `none`;
- `unknown` under Interaction Checker semantics;
- safe to combine;
- suitable for a specific patient.

## Finding identity and exact deduplication

Each retained `SdifPairFinding` keeps:

- mapped Sherko scientific identity for provider `drug_a`;
- mapped Sherko scientific identity for provider `drug_b`;
- provider drug names and ATCs;
- both provider routes;
- interaction family;
- severity score/label/indicator;
- keyword;
- description;
- explanation;
- source;
- combo hint.

An exact duplicate is collapsed only when the direction/endpoints and every retained provider-native field are identical.

Consequences:

- repeated byte-equivalent A -> B evidence collapses;
- A -> B and B -> A remain separate findings;
- different families remain separate;
- different descriptions/explanations remain separate;
- different severity labels/sources remain separate;
- EPha and Swissmedic FI evidence are never merged merely because their numeric scores match.

The aggregate reports both the raw provider hit count and retained finding count so exact duplicate collapse stays auditable.

## Deterministic ordering

Pair order follows the validated resolved-identity input order:

```text
identity 0 x identity 1
identity 0 x identity 2
...
identity n-2 x identity n-1
```

Findings inside a pair are ordered by:

1. provider-native severity score descending;
2. interaction-family enum order;
3. source;
4. provider direction through Sherko scientific IDs;
5. stable provider evidence fields.

This ordering is for reproducibility/presentation preparation only. It is not a cross-provider clinical ranking.

## Integrity boundary

`SdifResultAggregator` expects the validated output of `SdifReviewedAtcBridge.checkResolvedIdentities()`.

It still fails closed if:

- fewer than two resolved identities are supplied;
- two resolved identities share the same provider endpoint;
- a returned hit cannot be mapped to two distinct resolved endpoints;
- a hit references an unexpected pair.

This defensive check does not replace the stricter basket-integrity checks in SDIF-007.

## Real owner-local baseline

The owner ran SDIF-007 live acceptance successfully on 2026-10-02 against the accepted snapshot.

Observed input/result:

```text
reviewed identities: 3
resolved identities: 3
basket integrity: verified
raw interaction hits: 0
```

Under SDIF-008 semantics, that real result produces three unordered pair observations:

```text
aggregated pairs: 3
pairs with hitsObserved: 0
pairs with noProviderHitReported: 3
```

This is a provider observation only. It is not a safety conclusion for Amoxicillin, Caffeine, or Paracetamol.

## Focused verification

Repository test:

```powershell
flutter test test/sdif_result_aggregator_test.dart
```

The synthetic fixture covers:

- deterministic three-identity pair coverage with zero hits;
- all four SDIF interaction families;
- provider-native severity ordering without Interaction Checker conversion;
- exact same-direction duplicate collapse;
- opposite-direction evidence preservation;
- multiple distinct raw top-score labels/sources;
- mixed hit/no-hit pair observations;
- fail-closed unmappable provider endpoints.

Owner-local real acceptance remains:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\sdif_runtime_acceptance_windows.ps1
```

SDIF-008 extends its aggregate output with:

```text
aggregated_pair_count
pairs_with_hits_observed
pairs_with_no_provider_hit_reported
retained_finding_count
exact_duplicate_hit_count
```

The harness still prints no provider descriptions or dataset rows.

## Non-goals retained

SDIF-008 does not:

- switch Cart or Riverpod to SDIF;
- modify `DdiAnalysisEngine`;
- define final user-facing colors or warning wording;
- translate SDIF into Interaction Checker severity;
- infer safety from no-hit pairs;
- change Supabase schema/data;
- expand scientific curation coverage;
- decide Android/production SDIF hosting;
- bundle or redistribute provider datasets;
- provide patient-specific recommendations, dosing advice, treatment changes, or substitution guidance.

## Next bounded runtime task

After owner-local verification of this aggregate model, the next task should add a development-only provider selection/wiring boundary that can run the existing Interaction Checker path unchanged or the new SDIF path behind an explicit configuration switch.

That wiring task must not reuse the current Interaction Checker Cart presentation until a separate SDIF-native presentation contract can represent `hitsObserved` versus `noProviderHitReported` without inventing `none`/safe semantics.
