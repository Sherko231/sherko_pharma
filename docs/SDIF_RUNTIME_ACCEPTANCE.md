# SDIF Reviewed-ATC Runtime Acceptance

Status: SDIF-007 provider-specific bridge and owner-local acceptance harness. The active Cart DDI runtime remains Interaction Checker.
Task: Issue #132
Branch-start SHA: `335bc675478313f94bbb8b8592e6ac8d56174665`
Pinned upstream: `zdavatz/sdif@9f8f69519e4806d9e0e7021f403bdcb52ed77cc0`
Accepted owner-local snapshot SHA-256: `9e5498675acca91097899e66181a27b056cb2026f0d903e686da9cf5c62c3206`

## Purpose

SDIF-007 adds the first runtime identity bridge after SDIF-006's typed transport boundary. It does not switch the application to SDIF. Its purpose is to prove that an already-reviewed Sherko scientific identity can travel through reviewed ATC metadata to one provider-selected SDIF drug and then through `/api/check` without returning to raw Syrian brand-name or free-text identity guessing.

The bridge is intentionally provider-specific:

```text
reviewed Sherko scientific identity
  -> already-reviewed Sherko ATC code
  -> exact SDIF ATC lookup
  -> exact SDIF provider brand returned by that lookup
  -> SDIF /api/check
  -> basket identity integrity check
  -> provider-native SDIF interaction hits
```

The scientific preferred name is retained for Sherko identity/display context only. It is never sent to SDIF as a fallback lookup by this bridge.

## Current reviewed acceptance set

The live acceptance executable is deliberately limited to the three scientific identities already curated in production and audited against the accepted pinned snapshot:

| Scientific identity ID | Sherko preferred name | Reviewed ATC |
| ---: | --- | --- |
| 1 | Amoxicillin | `J01CA04` |
| 2 | Caffeine | `N06BC01` |
| 3 | Paracetamol | `N02BE01` |

The preceding snapshot audit measured reviewed-ATC-backed provider mapping coverage `3/3 (100%)` for these identities. This is provider lookup compatibility, not a clinical completeness claim.

## Runtime resolution contract

`SdifReviewedAtcBridge` consumes `SdifReviewedScientificIdentity` records containing:

- stable Sherko scientific ingredient ID;
- Sherko preferred scientific name;
- one or more already-reviewed ATC codes.

For every reviewed ATC code, the bridge calls only:

```text
GET /api/search-drugs?atc=<reviewed-code>
```

It does not perform:

- provider search by Sherko preferred name;
- raw composition lookup;
- Syrian/local brand lookup;
- fuzzy matching;
- transliteration;
- synonym inference;
- salt/base collapsing;
- ATC inference.

A returned provider row is accepted as a candidate only when the returned ATC exactly matches the reviewed requested ATC, provider brand/substance metadata is nonblank, and the provider row still collapses to exactly one active substance. A multi-substance/combination row fails closed instead of being promoted into one scientific identity.

Resolution outcomes are explicit:

- `resolved`: exactly one distinct provider candidate exists across the reviewed ATCs;
- `unmapped`: no provider candidate exists;
- `ambiguous`: more than one distinct provider candidate exists.

The bridge does not pick one candidate from an ambiguous result.

## Provider check integrity

A resolved selection carries the exact provider brand, provider ATC and substance display returned by SDIF.

Before `/api/check`, the bridge revalidates that:

- the selected reviewed ATC belongs to that Sherko scientific identity;
- provider ATC still equals the selected reviewed ATC;
- the provider selection still represents exactly one active substance;
- scientific identities in the basket are distinct;
- provider brands are distinct;
- provider brand/ATC/substance metadata is nonblank.

The check request sends only the exact provider brands returned by SDIF's reviewed-ATC lookup.

After `/api/check`, the returned `basket[]` must match the expected selections by position, exact provider brand, ATC and normalized active-substance set. Every returned interaction hit must also reference two distinct drugs that are present in that verified basket. Any mismatch fails closed instead of accepting provider substring-resolution or response-integrity drift.

Interaction hits remain the provider-native SDIF result. This bridge does not translate severity scores, merge interaction families, synthesize missing pairs, or interpret an empty interaction list as `none`, `safe`, or absence of clinical risk.

## Focused synthetic verification

Repository tests:

```powershell
flutter test test/sdif_reviewed_atc_bridge_test.dart test/sdif_reviewed_atc_bridge_integrity_test.dart
```

The focused fixture coverage includes:

- reviewed-ATC-only resolution;
- no preferred-name provider fallback;
- explicit unmapped result;
- explicit ambiguity across multiple reviewed ATCs;
- fail-closed provider ATC mismatch;
- rejection when a reviewed ATC lookup becomes multi-substance;
- rejection of a forged resolved selection outside the identity's reviewed ATCs;
- exact provider-brand submission;
- basket brand/ATC integrity failure;
- basket active-substance-set integrity failure;
- rejection of interaction hits that reference a drug outside the verified basket;
- empty provider interaction array remaining empty rather than becoming a safety classification;
- no-reviewed-ATC input rejection before provider access.

## Owner-local live acceptance

Prerequisites:

1. Pull the merged SDIF-007 revision.
2. The SDIF-005 bootstrap must already have completed successfully under:

```text
sdif_working_dir/sdif-pinned
```

3. The local `interactions.db` must still have SHA-256:

```text
9e5498675acca91097899e66181a27b056cb2026f0d903e686da9cf5c62c3206
```

4. Git, Cargo/Rust, Flutter and Dart must be available on PATH.

From the Sherko Pharma repository root, run one command:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\sdif_runtime_acceptance_windows.ps1
```

Optional port override:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\sdif_runtime_acceptance_windows.ps1 -Port 3010
```

The helper fails closed unless:

- the local SDIF checkout is exactly the pinned commit;
- the checkout has no tracked modifications;
- the actual `interactions.db` hash equals the accepted snapshot hash;
- the pinned SDIF release binary rebuilds successfully;
- the local server starts with `--epha` and answers the exact Amoxicillin ATC readiness probe;
- all three current reviewed identities resolve uniquely;
- the `/api/check` returned basket matches the selected provider identities.

The helper starts SDIF only on the owner's machine, runs the Dart acceptance executable against `127.0.0.1`, then stops the server. Server stdout/stderr stay under ignored `sdif_working_dir/`.

## Expected live output

A successful run prints aggregate JSON similar to:

```json
{
  "reviewed_identity_count": 3,
  "resolved_identity_count": 3,
  "resolution_status_counts": {
    "resolved": 3
  },
  "basket_integrity_verified": true,
  "basket_count": 3,
  "interaction_hit_count": 0,
  "interaction_family_counts": {
    "substance": 0,
    "classLevel": 0,
    "cyp": 0,
    "epha": 0
  },
  "provider_native_severity_score_counts": {},
  "absence_of_hits_is_not_a_safety_classification": true
}
```

The interaction counts above are examples only. The acceptance harness does not assert a clinical interaction count or expected severity for Amoxicillin/Caffeine/Paracetamol. Real provider-native hit counts are recorded from the local server run as observed evidence only.

## Privacy and data handling

The live acceptance request contains only SDIF provider brands selected from reviewed ATC lookups. It does not send:

- patient identity;
- Sherko account identity;
- Supabase credentials/tokens;
- Syrian product names;
- barcodes;
- prices;
- order quantities;
- notes;
- source CSV data.

The executable prints aggregate status/counts only. It does not print interaction descriptions or copy provider dataset rows into Git.

## What SDIF-007 still does not decide

SDIF-007 does not decide how SDIF results should appear in Cart. In particular it does not define:

- conversion from SDIF severity score/label to Interaction Checker `major|moderate|minor|none|unknown`;
- whether duplicate/asymmetric SDIF hits should be collapsed for presentation;
- whether an absent hit is shown at all;
- production hosting/service topology;
- Android access to a local or remote SDIF service;
- licensing/redistribution permission for a bundled database or public/commercial service.

Those are separate bounded decisions. The next task should first record the real owner-local live acceptance output, then define a provider-native comparison/presentation model before any Cart provider switch.
