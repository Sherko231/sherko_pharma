import 'dart:convert';

import '../domain/sdif_models.dart';
import '../domain/sdif_result_models.dart';
import '../domain/sdif_reviewed_identity_models.dart';

class SdifResultAggregator {
  const SdifResultAggregator();

  SdifAggregatedResult aggregate(SdifReviewedIdentityCheckResult checked) {
    final identities = checked.identities;
    if (identities.length < 2) {
      throw const SdifResultAggregationException(
        'SDIF aggregation requires at least two resolved scientific identities.',
      );
    }

    final endpointIndexes = <String, int>{};
    for (var index = 0; index < identities.length; index++) {
      final identity = identities[index];
      final endpointKey = _endpointKey(
        identity.providerDrug.brandName,
        identity.providerDrug.providerAtcCode,
      );
      if (endpointIndexes.containsKey(endpointKey)) {
        throw const SdifResultAggregationException(
          'Resolved SDIF identities contain a duplicate provider endpoint.',
        );
      }
      endpointIndexes[endpointKey] = index;
    }

    final accumulators = <String, _PairAccumulator>{};
    final pairOrder = <String>[];
    for (var left = 0; left < identities.length; left++) {
      for (var right = left + 1; right < identities.length; right++) {
        final key = _pairKey(left, right);
        pairOrder.add(key);
        accumulators[key] = _PairAccumulator(
          identityA: identities[left],
          identityB: identities[right],
        );
      }
    }

    for (final hit in checked.providerResult.interactions) {
      final aIndex = endpointIndexes[_endpointKey(hit.drugA, hit.drugAAtc)];
      final bIndex = endpointIndexes[_endpointKey(hit.drugB, hit.drugBAtc)];
      if (aIndex == null || bIndex == null || aIndex == bIndex) {
        throw const SdifResultAggregationException(
          'SDIF interaction hit could not be mapped to two distinct resolved identities.',
        );
      }

      final left = aIndex < bIndex ? aIndex : bIndex;
      final right = aIndex < bIndex ? bIndex : aIndex;
      final accumulator = accumulators[_pairKey(left, right)];
      if (accumulator == null) {
        throw const SdifResultAggregationException(
          'SDIF interaction hit referenced an unexpected resolved pair.',
        );
      }

      accumulator.providerHitCount += 1;
      final finding = SdifPairFinding(
        drugAIdentity: identities[aIndex],
        drugBIdentity: identities[bIndex],
        providerHit: hit,
      );
      accumulator.findingsByExactKey.putIfAbsent(
        _exactFindingKey(finding),
        () => finding,
      );
    }

    final pairs = <SdifPairAssessment>[];
    var retainedFindingCount = 0;
    var duplicateHitCount = 0;

    for (final pairKey in pairOrder) {
      final accumulator = accumulators[pairKey]!;
      final findings = accumulator.findingsByExactKey.values.toList(growable: false)
        ..sort(_compareFindings);
      final exactDuplicateHitCount =
          accumulator.providerHitCount - findings.length;
      retainedFindingCount += findings.length;
      duplicateHitCount += exactDuplicateHitCount;

      final families = <SdifInteractionFamily>{
        for (final finding in findings) finding.providerHit.family,
      }.toList(growable: false)
        ..sort((left, right) => left.index.compareTo(right.index));

      final maxScore = findings.isEmpty
          ? null
          : findings
              .map((finding) => finding.providerHit.severityScore)
              .reduce((left, right) => left > right ? left : right);
      final topSeverityObservations = maxScore == null
          ? const <SdifProviderSeverityObservation>[]
          : _topSeverityObservations(findings, maxScore);

      pairs.add(
        SdifPairAssessment(
          identityA: accumulator.identityA,
          identityB: accumulator.identityB,
          observationStatus: findings.isEmpty
              ? SdifPairObservationStatus.noProviderHitReported
              : SdifPairObservationStatus.hitsObserved,
          providerHitCount: accumulator.providerHitCount,
          exactDuplicateHitCount: exactDuplicateHitCount,
          findings: List.unmodifiable(findings),
          observedFamilies: List.unmodifiable(families),
          maxProviderSeverityScore: maxScore,
          topSeverityObservations: topSeverityObservations,
        ),
      );
    }

    return SdifAggregatedResult(
      pairs: List.unmodifiable(pairs),
      providerHitCount: checked.providerResult.interactions.length,
      retainedFindingCount: retainedFindingCount,
      exactDuplicateHitCount: duplicateHitCount,
    );
  }

  static List<SdifProviderSeverityObservation> _topSeverityObservations(
    List<SdifPairFinding> findings,
    int maxScore,
  ) {
    final observations = <String, SdifProviderSeverityObservation>{};
    for (final finding in findings) {
      final hit = finding.providerHit;
      if (hit.severityScore != maxScore) {
        continue;
      }
      final observation = SdifProviderSeverityObservation(
        score: hit.severityScore,
        label: hit.severityLabel,
        indicator: hit.severityIndicator,
        source: hit.source,
      );
      observations.putIfAbsent(
        jsonEncode([
          observation.score,
          observation.label,
          observation.indicator,
          observation.source,
        ]),
        () => observation,
      );
    }

    final result = observations.values.toList(growable: false)
      ..sort((left, right) {
        var compared = left.source.compareTo(right.source);
        if (compared != 0) return compared;
        compared = left.label.compareTo(right.label);
        if (compared != 0) return compared;
        return left.indicator.compareTo(right.indicator);
      });
    return List.unmodifiable(result);
  }

  static int _compareFindings(SdifPairFinding left, SdifPairFinding right) {
    final a = left.providerHit;
    final b = right.providerHit;
    var compared = b.severityScore.compareTo(a.severityScore);
    if (compared != 0) return compared;
    compared = a.family.index.compareTo(b.family.index);
    if (compared != 0) return compared;
    compared = a.source.compareTo(b.source);
    if (compared != 0) return compared;
    compared = left.drugAIdentity.identity.scientificIngredientId.compareTo(
      right.drugAIdentity.identity.scientificIngredientId,
    );
    if (compared != 0) return compared;
    compared = left.drugBIdentity.identity.scientificIngredientId.compareTo(
      right.drugBIdentity.identity.scientificIngredientId,
    );
    if (compared != 0) return compared;
    compared = a.keyword.compareTo(b.keyword);
    if (compared != 0) return compared;
    compared = a.description.compareTo(b.description);
    if (compared != 0) return compared;
    compared = a.explanation.compareTo(b.explanation);
    if (compared != 0) return compared;
    compared = a.severityLabel.compareTo(b.severityLabel);
    if (compared != 0) return compared;
    return a.severityIndicator.compareTo(b.severityIndicator);
  }

  static String _endpointKey(String brand, String atcCode) {
    return jsonEncode([brand.trim(), atcCode.trim()]);
  }

  static String _pairKey(int left, int right) => '$left:$right';

  static String _exactFindingKey(SdifPairFinding finding) {
    final hit = finding.providerHit;
    return jsonEncode([
      finding.drugAIdentity.identity.scientificIngredientId,
      finding.drugBIdentity.identity.scientificIngredientId,
      hit.drugA,
      hit.drugAAtc,
      hit.drugARoute,
      hit.drugB,
      hit.drugBAtc,
      hit.drugBRoute,
      hit.family.name,
      hit.severityScore,
      hit.severityLabel,
      hit.severityIndicator,
      hit.keyword,
      hit.description,
      hit.explanation,
      hit.source,
      hit.comboHint,
    ]);
  }
}

class _PairAccumulator {
  _PairAccumulator({
    required this.identityA,
    required this.identityB,
  });

  final SdifResolvedScientificIdentity identityA;
  final SdifResolvedScientificIdentity identityB;
  int providerHitCount = 0;
  final Map<String, SdifPairFinding> findingsByExactKey = {};
}

class SdifResultAggregationException implements Exception {
  const SdifResultAggregationException(this.message);

  final String message;

  @override
  String toString() => 'SdifResultAggregationException: $message';
}
