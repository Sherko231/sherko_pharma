import 'sdif_models.dart';

enum SdifReviewedAtcResolutionStatus {
  resolved,
  unmapped,
  ambiguous,
}

class SdifReviewedScientificIdentity {
  const SdifReviewedScientificIdentity({
    required this.scientificIngredientId,
    required this.preferredName,
    required this.reviewedAtcCodes,
  });

  final int scientificIngredientId;
  final String preferredName;
  final List<String> reviewedAtcCodes;
}

class SdifProviderDrugSelection {
  const SdifProviderDrugSelection({
    required this.reviewedAtcCode,
    required this.brandName,
    required this.providerAtcCode,
    required this.substances,
  });

  final String reviewedAtcCode;
  final String brandName;
  final String providerAtcCode;
  final String substances;
}

class SdifReviewedAtcResolution {
  const SdifReviewedAtcResolution({
    required this.identity,
    required this.status,
    required this.candidates,
  });

  final SdifReviewedScientificIdentity identity;
  final SdifReviewedAtcResolutionStatus status;
  final List<SdifProviderDrugSelection> candidates;

  SdifResolvedScientificIdentity? get resolvedIdentity {
    if (status != SdifReviewedAtcResolutionStatus.resolved ||
        candidates.length != 1) {
      return null;
    }
    return SdifResolvedScientificIdentity(
      identity: identity,
      providerDrug: candidates.single,
    );
  }
}

class SdifResolvedScientificIdentity {
  const SdifResolvedScientificIdentity({
    required this.identity,
    required this.providerDrug,
  });

  final SdifReviewedScientificIdentity identity;
  final SdifProviderDrugSelection providerDrug;
}

class SdifReviewedIdentityCheckResult {
  const SdifReviewedIdentityCheckResult({
    required this.identities,
    required this.providerResult,
  });

  final List<SdifResolvedScientificIdentity> identities;
  final SdifCheckResult providerResult;
}
