import 'sdif_models.dart';
import 'sdif_reviewed_identity_models.dart';

enum SdifPairObservationStatus {
  hitsObserved,
  noProviderHitReported,
}

class SdifProviderSeverityObservation {
  const SdifProviderSeverityObservation({
    required this.score,
    required this.label,
    required this.indicator,
    required this.source,
  });

  final int score;
  final String label;
  final String indicator;
  final String source;
}

class SdifPairFinding {
  const SdifPairFinding({
    required this.drugAIdentity,
    required this.drugBIdentity,
    required this.providerHit,
  });

  final SdifResolvedScientificIdentity drugAIdentity;
  final SdifResolvedScientificIdentity drugBIdentity;
  final SdifInteractionHit providerHit;

  bool get isDirectionalEvidence =>
      providerHit.family != SdifInteractionFamily.epha;
}

class SdifPairAssessment {
  const SdifPairAssessment({
    required this.identityA,
    required this.identityB,
    required this.observationStatus,
    required this.providerHitCount,
    required this.exactDuplicateHitCount,
    required this.findings,
    required this.observedFamilies,
    required this.maxProviderSeverityScore,
    required this.topSeverityObservations,
  });

  final SdifResolvedScientificIdentity identityA;
  final SdifResolvedScientificIdentity identityB;
  final SdifPairObservationStatus observationStatus;
  final int providerHitCount;
  final int exactDuplicateHitCount;
  final List<SdifPairFinding> findings;
  final List<SdifInteractionFamily> observedFamilies;
  final int? maxProviderSeverityScore;
  final List<SdifProviderSeverityObservation> topSeverityObservations;

  bool get hasObservedHits =>
      observationStatus == SdifPairObservationStatus.hitsObserved;
}

class SdifAggregatedResult {
  const SdifAggregatedResult({
    required this.pairs,
    required this.providerHitCount,
    required this.retainedFindingCount,
    required this.exactDuplicateHitCount,
  });

  final List<SdifPairAssessment> pairs;
  final int providerHitCount;
  final int retainedFindingCount;
  final int exactDuplicateHitCount;
}
