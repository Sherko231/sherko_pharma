import 'sdif_product_scientific_models.dart';
import 'sdif_result_models.dart';
import 'sdif_reviewed_identity_models.dart';

enum SdifProviderResolutionGapStatus {
  unmapped,
  ambiguous,
}

class SdifProviderResolutionGap {
  const SdifProviderResolutionGap({
    required this.identity,
    required this.status,
    required this.productIds,
  });

  final SdifReviewedScientificIdentity identity;
  final SdifProviderResolutionGapStatus status;
  final List<String> productIds;
}

class SdifProductPairAnalysis {
  const SdifProductPairAnalysis({
    required this.productAId,
    required this.productBId,
    required this.identityPairs,
  });

  final String productAId;
  final String productBId;
  final List<SdifPairAssessment> identityPairs;

  bool get hasProviderCheckedIdentityPairs => identityPairs.isNotEmpty;

  bool get hasObservedHits =>
      identityPairs.any((pair) => pair.hasObservedHits);
}

class SdifCartAnalysisResult {
  const SdifCartAnalysisResult({
    required this.products,
    required this.providerResolutionGaps,
    required this.identityPairs,
    required this.productPairs,
    required this.uniqueEligibleIdentityCount,
    required this.providerResolvedIdentityCount,
    required this.providerBatchCount,
    required this.providerHitCount,
    required this.retainedFindingCount,
    required this.exactDuplicateHitCount,
  });

  final List<SdifProductScientificInput> products;
  final List<SdifProviderResolutionGap> providerResolutionGaps;
  final List<SdifPairAssessment> identityPairs;
  final List<SdifProductPairAnalysis> productPairs;
  final int uniqueEligibleIdentityCount;
  final int providerResolvedIdentityCount;
  final int providerBatchCount;
  final int providerHitCount;
  final int retainedFindingCount;
  final int exactDuplicateHitCount;
}
