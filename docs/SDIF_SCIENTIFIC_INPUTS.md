# SDIF Reviewed Scientific Product Inputs

Status: SDIF-010 repository/runtime input bridge only. The migration in this task is **not deployed** to production.
Task: Issue #142
Branch-start SHA: `18b7dc6f1e3e05198b08f9b60ebbb77d4653d7b4`

## Purpose

SDIF-010 defines the read-only bridge from current Sherko Pharma product IDs to the reviewed scientific identities and reviewed ATC metadata that the SDIF runtime may use later.

The bridge is deliberately separate from both raw catalog composition and Interaction Checker provider mappings:

```text
Cart product IDs
  -> private SP-044 product scientific canonicalization
  -> trusted reviewed scientific identities
  -> reviewed ATC metadata
  -> SDIF-010 typed product input
```

Flutter does not reparse Syrian brand names or raw composition text and does not infer scientific identity or ATC metadata.

## Bounded owner-only RPC

Repository migration `0024_sdif_scientific_identity_inputs_api.sql` adds:

```text
public.catalog_sdif_scientific_identities(uuid[])
```

The function:

- requires `app_private.require_owner()`;
- accepts at most 50 requested UUIDs;
- rejects null arrays and null elements;
- returns zero rows for an empty request;
- deduplicates repeated product IDs by first request position;
- uses `SECURITY DEFINER` with an empty `search_path` and schema-qualified relations;
- revokes default/public/anonymous/authenticated execution before granting only `authenticated` execution;
- does not grant direct access to the private scientific tables.

Authentication alone is not authorization: the function still requires the configured owner account before reading the private derived data.

## Eligible scientific identities

Only ingredient nodes from `app_private.product_scientific_canonicalization_nodes` are eligible when all of these are true:

1. `node_kind = ingredient`;
2. `identity_status = trusted`;
3. `scientific_ingredient_id` is present;
4. the scientific identity has at least one row in `scientific_ingredient_atc_codes`.

Repeated occurrences of the same scientific identity inside one product are returned once, ordered by the first canonicalization node where that identity appeared.

Every exposed identity includes only:

- stable Sherko scientific ingredient ID;
- reviewed preferred scientific name;
- sorted reviewed ATC codes.

ATC remains classification metadata. It is not used to create or prove scientific identity.

## Product coverage states

Every distinct requested product is represented.

### `complete`

Every scientific ingredient component in the product is trusted and has reviewed ATC metadata.

### `partial`

At least one component is eligible for SDIF, but one or more other ingredient components are not eligible.

Eligible reviewed identities are still returned. The missing components are represented only through aggregate counts; their unreviewed names or candidate identities are not exposed.

### `unmapped`

The product exists, but none of its ingredient components currently has an SDIF-eligible reviewed scientific identity plus reviewed ATC metadata.

### `missing`

The requested product UUID does not exist.

`complete`, `partial`, `unmapped`, and `missing` are input-coverage states only. They are not interaction severities or safety classifications.

## Coverage counts

Each product result carries:

```text
ingredient_count
trusted_component_count
atc_covered_component_count
eligible_identity_count
```

`atc_covered_component_count` counts component occurrences, while `eligible_identity_count` counts distinct reviewed identities. Therefore a product containing the same reviewed identity twice can have two ATC-covered components but one eligible identity.

## Production read-only baseline

Before implementing this repository migration, SDIF-010 ran a read-only production query against the already-deployed SP-044/SDIF-003 derived data. No migration or data write was performed.

Observed on 2026-10-02:

```text
complete:   469 products
partial:    812 products
unmapped: 22469 products
```

These counts describe the current scientific/ATC curation coverage under the SDIF-010 rule. They do not establish SDIF provider interaction coverage for those products.

## Flutter repository boundary

`SupabaseSdifScientificIdentityRepository` maps the RPC into typed `SdifProductScientificInput` objects and fails closed on malformed output.

It verifies:

- every requested product is represented exactly once as a product group;
- no unexpected product group is returned;
- request positions remain deterministic;
- summary fields are consistent across identity rows;
- count relationships are internally valid;
- coverage status matches the returned counts;
- eligible identity positions are contiguous and deterministic;
- scientific IDs are positive and unique within a product;
- preferred names are nonblank;
- reviewed ATC lists are nonempty, uppercase, unique, and sorted.

The repository converts an eligible product identity directly into the existing `SdifReviewedScientificIdentity` contract used by the reviewed-ATC provider bridge.

## Runtime wiring

The repository is instantiated by `AppRuntime` only when the development runtime selects SDIF:

```text
DDI_PROVIDER=sdif
```

`AppBootstrap` exposes it through `sdifScientificIdentityRepositoryProvider`.

Interaction Checker selection does not instantiate or expose the SDIF scientific repository.

SDIF-010 does **not** call the repository from `DdiCartController`. The existing Interaction Checker Cart gateway remains deliberately unavailable under SDIF selection, as established by SDIF-009.

## Verification

Focused Flutter tests:

```powershell
flutter test test/sdif_scientific_identity_repository_test.dart test/ddi_runtime_selection_test.dart
```

Backend regression source:

```text
backend/tests/022_sdif_scientific_identity_inputs_api_test.sql
```

The SQL regression covers owner authorization, direct-private-table denial, complete/partial/unmapped/missing inputs, reviewed ATC preservation, repeated scientific identity deduplication, deterministic request ordering, bounded input validation, and non-leakage of identities without reviewed ATC metadata.

## Deployment boundary

Migration `0024_sdif_scientific_identity_inputs_api.sql` is repository-only in SDIF-010. It is not deployed by this task.

Until a later owner-authorized production deployment applies the migration, a real configured app must not be expected to call `catalog_sdif_scientific_identities` successfully against production.

## Non-goals retained

SDIF-010 does not:

- deploy or mutate production data;
- add or infer scientific mappings or ATC codes;
- send product identities to SDIF yet;
- change the current Cart lifecycle or presentation;
- translate SDIF native severity to Interaction Checker severity;
- turn absent SDIF hits into `none`, `unknown`, or safe;
- remove Interaction Checker;
- bundle or redistribute SDIF source datasets;
- provide patient-specific treatment, dose, stop/start, or substitution advice.

## Next bounded task

After explicit owner authorization to deploy the read-only RPC, the next runtime task can combine:

```text
Cart products
  -> SDIF-010 reviewed scientific inputs
  -> SDIF-007 reviewed ATC provider resolution
  -> SDIF-008 provider-native aggregation
```

That later task must preserve partial/unmapped input coverage and same-product exclusion, and must define an SDIF-native lifecycle/presentation instead of reusing Interaction Checker severity semantics.
