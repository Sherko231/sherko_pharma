# SDIF Cart Analysis Lifecycle

Status: SDIF-012 provider-native runtime analysis behind the development-only SDIF selection. No SDIF-native Cart presentation is added by this task.
Task: Issue #146
Branch-start SHA: `35c7c9869dc4263353dc040003cb5cec47cb1482`

## Purpose

SDIF-012 connects the active Cart product set to the already-reviewed SDIF pipeline without translating SDIF into the existing Interaction Checker result model:

```text
Cart distinct product IDs
  -> production catalog_sdif_scientific_identities RPC
  -> reviewed Sherko scientific identities + reviewed ATC metadata
  -> SDIF reviewed-ATC provider resolution
  -> verified SDIF /api/check basket
  -> provider-native identity-pair aggregation
  -> affected Cart product pairs
```

The runtime remains development-only and requires the explicit SDIF provider selection introduced by SDIF-009.

## Product input coverage remains independent

Every requested Cart product retains the SDIF-010 input coverage state:

```text
complete
partial
unmapped
missing
```

The analysis engine does not upgrade partial or unmapped products. Eligible reviewed identities from a partial product may continue through SDIF, while the missing components remain represented by the product-level coverage counts.

Input coverage is not an interaction result or safety classification.

## Scientific identity ownership

The engine deduplicates reviewed scientific identities globally by stable Sherko `scientific_ingredient_id`.

If the same reviewed identity occurs in more than one Cart product, it is resolved against SDIF once and retains the set of owning product IDs. Repeated occurrences must have identical preferred name and reviewed ATC metadata; contradictory metadata fails closed.

This ownership map is what allows provider-native scientific identity pairs to be mapped back to one or more unordered Cart product pairs.

## Provider resolution gaps

Each unique reviewed identity is resolved through the existing reviewed-ATC bridge.

Provider resolution remains explicit:

```text
resolved
unmapped
ambiguous
```

`unmapped` and `ambiguous` become `SdifProviderResolutionGap` entries containing the reviewed Sherko scientific identity and every affected Cart product ID.

Distinct Sherko scientific identities are not allowed to collapse onto the same SDIF provider brand + ATC endpoint. Such a contradiction fails closed rather than silently deduplicating the identities.

## Cross-product comparison boundary

Only a scientific-identity pair that can connect two different Cart products is retained in the Cart analysis result.

For example:

```text
Product A: identity 1 + identity 2
Product B: identity 3
```

The retained product-vs-product scientific pairs are:

```text
1 x 3
2 x 3
```

`1 x 2` belongs only to Product A and is not returned as product-vs-product Cart evidence.

Provider batching may evaluate additional same-product identity pairs as unavoidable collateral when several identities share one SDIF request. Those observations are excluded from the Cart analysis result and its hit/finding counts.

## More than ten resolved identities

SDIF accepts at most ten provider drugs per `/api/check` call.

For more than ten participating resolved identities, SDIF-012 uses the same complete bounded grouping principle already proven by the Interaction Checker engine:

1. partition the deterministic identity list into groups of at most five;
2. submit every unordered pair of groups;
3. each request therefore contains at most ten identities;
4. every unordered identity pair appears in at least one request.

Overlapping requests intentionally repeat some within-group identity pairs. The engine deduplicates those pair observations by stable scientific identity pair.

If a repeated pair produces a different provider-native observation in another overlapping batch, the analysis fails closed. It does not pick one result or merge contradictory evidence.

## Provider-native result semantics

The engine reuses `SdifResultAggregator` unchanged.

Each retained scientific identity pair is still only:

```text
hitsObserved
noProviderHitReported
```

`noProviderHitReported` is not converted to `none`, `unknown`, safe, compatible, or clinically insignificant.

SDIF `severity_score`, `severity_label`, `severity_indicator`, interaction family, source, description, explanation and direction remain provider-native evidence.

No SDIF value is converted to Interaction Checker `major|moderate|minor|none|unknown` in SDIF-012.

## Product-pair output

`SdifCartAnalysisResult` contains every unordered requested Cart product pair in request order.

A product pair can therefore have:

- one or more checked scientific identity pairs;
- zero checked identity pairs because its scientific inputs are partial/unmapped/missing;
- zero checked identity pairs because both products share only the same scientific identity and SDIF has no distinct identity pair to compare.

Zero checked identity pairs is not a no-interaction result.

The analysis result separately reports:

```text
uniqueEligibleIdentityCount
providerResolvedIdentityCount
providerBatchCount
providerHitCount
retainedFindingCount
exactDuplicateHitCount
```

The hit/finding counts cover only retained cross-product scientific identity pairs.

## Stale-safe Cart lifecycle

`SdifCartController` is a separate runtime state machine from the existing `DdiCartController`.

It follows the same Cart identity lifecycle principles:

- requires authenticated owner + ready same-owner session;
- analyzes only when at least two distinct Cart products exist;
- debounces rapid distinct-product changes;
- quantity-only changes do not create a new product set and do not re-run analysis;
- removal, New Order/reset, sign-out, account/session replacement, runtime-provider change or newer Cart generation invalidate older work;
- late results cannot repaint a superseded product set;
- failed analysis is retryable only while the same owner/session/product set remains current.

The controller has SDIF-native failure classes for scientific-input, timeout, transport, provider, malformed-response and mapping failures.

## Runtime activation and current UI boundary

`AppBootstrap` activates the separate SDIF Cart lifecycle only when the configured runtime selection uses SDIF.

Interaction Checker remains the default. Under Interaction Checker selection, SDIF Cart analysis is idle and performs no SDIF work.

Under SDIF selection, the separate SDIF lifecycle runs, but the existing `DdiCartController` and current Cart DDI presentation are intentionally unchanged. The current Interaction Checker presentation therefore remains unavailable rather than receiving a coerced SDIF result.

SDIF-native Cart visuals and detail presentation belong to a later task.

## Focused verification

Engine regression:

```powershell
flutter test test/sdif_cart_analysis_engine_test.dart
```

It covers:

- partial/unmapped product coverage preservation;
- provider resolution gaps;
- shared scientific identity deduplication;
- same-product-only identity-pair exclusion;
- complete cross-product coverage with 11 resolved identities and every provider request <=10 drugs;
- overlapping-batch contradiction failure;
- stale-generation fail-closed behavior.

Cart lifecycle regression:

```powershell
flutter test test/sdif_cart_controller_test.dart
```

It covers:

- same-owner restored Cart analysis under SDIF selection;
- quantity-only no-recheck behavior;
- New Order/clear invalidation of in-flight results;
- no SDIF Cart analysis under the default Interaction Checker selection.

## Non-goals retained

SDIF-012 does not:

- add SDIF Cart badges, colors, summary text or detail sheet;
- translate SDIF severity into Interaction Checker severity;
- infer safety from absent provider hits;
- alter scientific mappings, reviewed ATC metadata or catalog data;
- deploy a database migration;
- start or install the SDIF local server automatically;
- enable SDIF in release mode;
- bundle or redistribute provider source datasets;
- provide patient-specific treatment, dose, stop/start or substitution advice.

## Next bounded task

The next task can add an SDIF-native Cart presentation/lifecycle adapter over `SdifCartState` and `SdifCartAnalysisResult` while preserving the distinct meanings of:

```text
input coverage gap
provider resolution gap
hitsObserved
noProviderHitReported
provider/runtime failure
```

That presentation must not reuse Interaction Checker severity colors/labels unless a separately reviewed mapping contract is explicitly approved.
