# SDIF Reviewed Scientific Product Inputs

Status: SDIF-010 repository/runtime input bridge merged; SDIF-011 deployed migration 0024 to production and verified the live owner-only RPC contract.
Implementation task: Issue #142
Production deployment task: Issue #144
SDIF-010 branch-start SHA: `18b7dc6f1e3e05198b08f9b60ebbb77d4653d7b4`
SDIF-011 branch-start SHA: `b5c4af7e45f7fd450a9638efcfa455e37a18d09e`

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

## Production read-only baseline before deployment

Before implementing and deploying this RPC, SDIF-010 ran a read-only production query against the already-deployed SP-044/SDIF-003 derived data. No migration or data write was performed during that baseline measurement.

Observed on 2026-10-02:

```text
complete:   469 products
partial:    812 products
unmapped: 22469 products
```

These counts describe the current scientific/ATC curation coverage under the SDIF-010 rule. They do not establish SDIF provider interaction coverage for those products.

## SDIF-011 production deployment record

Owner authorization to deploy the reviewed read-only RPC was explicit on 2026-10-02 through the instruction to continue after SDIF-010, where migration 0024 deployment had been identified as the next bounded task.

Preflight confirmed:

- production did not already contain `catalog_sdif_scientific_identities(uuid[])`;
- production had one configured owner account;
- the latest recorded migration before this deployment was `sdif003_reviewed_atc_metadata`;
- reviewed scientific state contained 3 scientific identities, 3 reviewed ATC rows, 23,750 product canonicalization summaries, and 31,735 canonicalization nodes.

The exact SQL from repository migration `0024_sdif_scientific_identity_inputs_api.sql` was applied through the Supabase migration surface as:

```text
name:    sdif011_scientific_identity_inputs_api
version: 20261002115754
```

The migration history contains exactly one row with that name after deployment.

### Live authorization and function verification

Production inspection after deployment confirmed:

- function signature: `catalog_sdif_scientific_identities(uuid[])`;
- `SECURITY DEFINER = true`;
- function `search_path` is empty;
- `anon` has no EXECUTE privilege;
- `authenticated` has EXECUTE privilege;
- an authenticated non-owner call fails with PostgreSQL `42501 owner authorization required`;
- an authenticated owner call succeeds;
- normal authenticated clients still have no direct SELECT privilege on `scientific_ingredients`, `scientific_ingredient_atc_codes`, or `product_scientific_canonicalization_nodes`.

A live owner call covering current complete, partial, unmapped, and missing products returned the expected contract shape. The complete and partial examples exposed only reviewed Paracetamol identity metadata with reviewed ATC `N02BE01` where eligible; unmapped and missing examples exposed no scientific identity fields.

Input-bound behavior was also verified live:

- empty UUID array -> zero rows;
- null UUID array -> PostgreSQL `22023`;
- an array containing a null UUID -> PostgreSQL `22023`;
- 51 requested UUID entries -> PostgreSQL `22023`.

### Live whole-catalog RPC coverage

After deployment, all 23,750 current products were passed through the live production RPC in deterministic batches of at most 50 IDs. Product coverage remained:

```text
complete:   469 products
partial:    812 products
unmapped: 22469 products
```

This exactly matches the pre-deployment read-only baseline. These counts remain input-coverage measurements only; they do not mean that SDIF reports an interaction, no interaction, or safety for those products.

### Production state preservation

The deployment creates only the read function and its privileges. Pre/post aggregate counts and fingerprints were compared for the scientific derived state and were unchanged:

```text
scientific_ingredients:                    3
scientific_ingredient_atc_codes:           3
product_scientific_canonicalization:   23750
product_scientific_canonicalization_nodes: 31735

scientific_ingredients fingerprint:
16ad58a2cd1221dc9e3711391b68dc4d

reviewed ATC fingerprint:
163a030620532b6d3d911707404fd438

product canonicalization fingerprint:
a8a6dd2e7b7563471ca56605ca0628ea

canonicalization node fingerprint:
131f785ee77f91030f3f174cbf3d0714
```

No scientific identity, ATC metadata, product data, canonicalization row, or canonicalization node was mutated by SDIF-011.

The connected Supabase tool surface available during SDIF-011 did not expose a database-advisor action, so no Security/Performance Advisor result is claimed. Current Supabase database-function security guidance and breaking-change changelog were re-checked before deployment; the reviewed function still follows the documented `SECURITY DEFINER`/empty-`search_path` and explicit function-privilege requirements.

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

SDIF-010/011 do **not** call the repository from `DdiCartController`. The existing Interaction Checker Cart gateway remains deliberately unavailable under SDIF selection, as established by SDIF-009.

## Verification

Focused Flutter tests retained from SDIF-010:

```powershell
flutter test test/sdif_scientific_identity_repository_test.dart test/ddi_runtime_selection_test.dart
```

Backend regression source retained from SDIF-010:

```text
backend/tests/022_sdif_scientific_identity_inputs_api_test.sql
```

The SQL regression covers owner authorization, direct-private-table denial, complete/partial/unmapped/missing inputs, reviewed ATC preservation, repeated scientific identity deduplication, deterministic request ordering, bounded input validation, and non-leakage of identities without reviewed ATC metadata.

SDIF-011 verification was performed against production using read-only inspection plus the deployed read-only RPC. The repository SQL regression does not need to insert synthetic production fixtures to establish the deployment result above.

## Deployment boundary

Migration `0024_sdif_scientific_identity_inputs_api.sql` is deployed to the Sherko Pharma production Supabase project as migration `20261002115754 / sdif011_scientific_identity_inputs_api`.

The production client may now call `catalog_sdif_scientific_identities` when authenticated as the configured owner. This does not activate SDIF Cart analysis by itself; the Cart controller still does not invoke the repository under the SDIF runtime selection.

## Non-goals retained

SDIF-010/011 do not:

- add or infer scientific mappings or ATC codes;
- send product identities to SDIF yet;
- change the current Cart lifecycle or presentation;
- translate SDIF native severity to Interaction Checker severity;
- turn absent SDIF hits into `none`, `unknown`, or safe;
- remove Interaction Checker;
- bundle or redistribute SDIF source datasets;
- provide patient-specific treatment, dose, stop/start, or substitution advice.

## Next bounded task

With the production input RPC now deployed and verified, the next runtime task can combine:

```text
Cart products
  -> SDIF-010/011 reviewed scientific inputs
  -> SDIF-007 reviewed ATC provider resolution
  -> SDIF-008 provider-native aggregation
```

That later task must preserve partial/unmapped input coverage and same-product exclusion, and must define an SDIF-native lifecycle/presentation instead of reusing Interaction Checker severity semantics.
