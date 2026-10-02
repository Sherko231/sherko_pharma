import 'sdif_reviewed_identity_models.dart';

enum SdifScientificCoverageStatus {
  complete,
  partial,
  unmapped,
  missing,
}

class SdifProductScientificIdentity {
  const SdifProductScientificIdentity({
    required this.scientificIngredientId,
    required this.preferredName,
    required this.reviewedAtcCodes,
  });

  final int scientificIngredientId;
  final String preferredName;
  final List<String> reviewedAtcCodes;

  SdifReviewedScientificIdentity toReviewedIdentity() {
    return SdifReviewedScientificIdentity(
      scientificIngredientId: scientificIngredientId,
      preferredName: preferredName,
      reviewedAtcCodes: reviewedAtcCodes,
    );
  }
}

class SdifProductScientificInput {
  const SdifProductScientificInput({
    required this.requestPosition,
    required this.productId,
    required this.productExists,
    required this.coverageStatus,
    required this.canonicalizationStatus,
    required this.ingredientCount,
    required this.trustedComponentCount,
    required this.atcCoveredComponentCount,
    required this.eligibleIdentityCount,
    required this.identities,
  });

  final int requestPosition;
  final String productId;
  final bool productExists;
  final SdifScientificCoverageStatus coverageStatus;
  final String? canonicalizationStatus;
  final int ingredientCount;
  final int trustedComponentCount;
  final int atcCoveredComponentCount;
  final int eligibleIdentityCount;
  final List<SdifProductScientificIdentity> identities;

  bool get hasEligibleIdentities => identities.isNotEmpty;
  bool get hasCompleteCoverage =>
      coverageStatus == SdifScientificCoverageStatus.complete;
}
