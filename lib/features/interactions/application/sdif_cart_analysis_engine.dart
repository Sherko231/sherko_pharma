import 'dart:convert';

import '../data/sdif_scientific_identity_repository.dart';
import '../domain/sdif_cart_analysis_models.dart';
import '../domain/sdif_product_scientific_models.dart';
import '../domain/sdif_result_models.dart';
import '../domain/sdif_reviewed_identity_models.dart';
import 'sdif_result_aggregator.dart';
import 'sdif_reviewed_atc_bridge.dart';

abstract interface class SdifCartAnalysisGateway {
  Future<SdifCartAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  });
}

class SdifCartAnalysisEngine implements SdifCartAnalysisGateway {
  SdifCartAnalysisEngine({
    required this.scientificIdentityRepository,
    required this.reviewedAtcBridge,
    required this.resultAggregator,
  });

  final SdifScientificIdentityRepository scientificIdentityRepository;
  final SdifReviewedAtcBridge reviewedAtcBridge;
  final SdifResultAggregator resultAggregator;

  @override
  Future<SdifCartAnalysisResult> analyzeProductIds(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) async {
    final requestedProductIds = _distinctProductIds(productIds);
    _ensureCurrent(isCurrent);

    final products = await _resolveProducts(
      requestedProductIds,
      isCurrent: isCurrent,
    );
    _ensureCurrent(isCurrent);

    final nodes = _buildScientificNodes(products);
    final orderedNodes = nodes.values.toList(growable: false)
      ..sort(
        (left, right) => left.identity.scientificIngredientId.compareTo(
          right.identity.scientificIngredientId,
        ),
      );

    final resolvedNodes = <_ResolvedScientificNode>[];
    final resolutionGaps = <SdifProviderResolutionGap>[];
    final providerEndpoints = <String, int>{};

    for (final node in orderedNodes) {
      _ensureCurrent(isCurrent);
      final resolution = await reviewedAtcBridge.resolveIdentity(node.identity);
      _ensureCurrent(isCurrent);

      switch (resolution.status) {
        case SdifReviewedAtcResolutionStatus.resolved:
          final resolved = resolution.resolvedIdentity;
          if (resolved == null) {
            throw const SdifCartAnalysisMappingException(
              'Resolved SDIF identity did not contain exactly one provider selection.',
            );
          }
          final endpointKey = _providerEndpointKey(resolved);
          final previousIdentity = providerEndpoints[endpointKey];
          if (previousIdentity != null &&
              previousIdentity != resolved.identity.scientificIngredientId) {
            throw const SdifCartAnalysisMappingException(
              'Distinct reviewed scientific identities resolved to the same SDIF provider endpoint.',
            );
          }
          providerEndpoints[endpointKey] =
              resolved.identity.scientificIngredientId;
          resolvedNodes.add(
            _ResolvedScientificNode(
              source: node,
              resolvedIdentity: resolved,
            ),
          );
        case SdifReviewedAtcResolutionStatus.unmapped:
          resolutionGaps.add(
            SdifProviderResolutionGap(
              identity: resolution.identity,
              status: SdifProviderResolutionGapStatus.unmapped,
              productIds: List.unmodifiable(node.productIds),
            ),
          );
        case SdifReviewedAtcResolutionStatus.ambiguous:
          resolutionGaps.add(
            SdifProviderResolutionGap(
              identity: resolution.identity,
              status: SdifProviderResolutionGapStatus.ambiguous,
              productIds: List.unmodifiable(node.productIds),
            ),
          );
      }
    }

    final expectedCrossPairKeys = <String>[];
    final participatingScientificIds = <int>{};
    for (var left = 0; left < resolvedNodes.length; left++) {
      for (var right = left + 1; right < resolvedNodes.length; right++) {
        final a = resolvedNodes[left];
        final b = resolvedNodes[right];
        if (!_hasCrossProductOwnership(a.source, b.source)) {
          continue;
        }
        expectedCrossPairKeys.add(
          _scientificPairKey(
            a.resolvedIdentity.identity.scientificIngredientId,
            b.resolvedIdentity.identity.scientificIngredientId,
          ),
        );
        participatingScientificIds
          ..add(a.resolvedIdentity.identity.scientificIngredientId)
          ..add(b.resolvedIdentity.identity.scientificIngredientId);
      }
    }

    final participatingNodes = resolvedNodes
        .where(
          (node) => participatingScientificIds.contains(
            node.resolvedIdentity.identity.scientificIngredientId,
          ),
        )
        .toList(growable: false);
    final batches = _buildProviderBatches(participatingNodes);
    final observedPairs = <String, SdifPairAssessment>{};
    final observedFingerprints = <String, String>{};

    for (final batch in batches) {
      _ensureCurrent(isCurrent);
      final checked = await reviewedAtcBridge.checkResolvedIdentities(
        batch
            .map((node) => node.resolvedIdentity)
            .toList(growable: false),
      );
      _ensureCurrent(isCurrent);

      final aggregated = resultAggregator.aggregate(checked);
      for (final pair in aggregated.pairs) {
        final key = _scientificPairKey(
          pair.identityA.identity.scientificIngredientId,
          pair.identityB.identity.scientificIngredientId,
        );
        final fingerprint = _pairObservationFingerprint(pair);
        final previousFingerprint = observedFingerprints[key];
        if (previousFingerprint != null && previousFingerprint != fingerprint) {
          throw const SdifCartAnalysisMappingException(
            'SDIF pair observation changed across overlapping provider batches.',
          );
        }
        observedFingerprints[key] = fingerprint;
        observedPairs.putIfAbsent(key, () => pair);
      }
    }

    final crossIdentityPairs = <SdifPairAssessment>[];
    for (final key in expectedCrossPairKeys) {
      final pair = observedPairs[key];
      if (pair == null) {
        throw const SdifCartAnalysisMappingException(
          'SDIF batching omitted a required cross-product scientific identity pair.',
        );
      }
      crossIdentityPairs.add(pair);
    }

    final productPairs = _buildProductPairs(
      productIds: requestedProductIds,
      nodes: nodes,
      identityPairs: crossIdentityPairs,
    );

    return SdifCartAnalysisResult(
      products: List.unmodifiable(products),
      providerResolutionGaps: List.unmodifiable(resolutionGaps),
      identityPairs: List.unmodifiable(crossIdentityPairs),
      productPairs: List.unmodifiable(productPairs),
      uniqueEligibleIdentityCount: orderedNodes.length,
      providerResolvedIdentityCount: resolvedNodes.length,
      providerBatchCount: batches.length,
      providerHitCount: crossIdentityPairs.fold(
        0,
        (sum, pair) => sum + pair.providerHitCount,
      ),
      retainedFindingCount: crossIdentityPairs.fold(
        0,
        (sum, pair) => sum + pair.findings.length,
      ),
      exactDuplicateHitCount: crossIdentityPairs.fold(
        0,
        (sum, pair) => sum + pair.exactDuplicateHitCount,
      ),
    );
  }

  Future<List<SdifProductScientificInput>> _resolveProducts(
    List<String> productIds, {
    bool Function()? isCurrent,
  }) async {
    final results = <SdifProductScientificInput>[];
    for (var offset = 0; offset < productIds.length; offset += 50) {
      _ensureCurrent(isCurrent);
      final end = offset + 50 < productIds.length
          ? offset + 50
          : productIds.length;
      final chunk = productIds.sublist(offset, end);
      final resolved = await scientificIdentityRepository.resolveProducts(chunk);
      _ensureCurrent(isCurrent);

      if (resolved.length != chunk.length) {
        throw const SdifCartAnalysisMappingException(
          'Scientific identity repository did not return one product result per requested ID.',
        );
      }
      final byId = <String, SdifProductScientificInput>{
        for (final product in resolved) product.productId: product,
      };
      if (byId.length != resolved.length) {
        throw const SdifCartAnalysisMappingException(
          'Scientific identity repository returned duplicate product results.',
        );
      }

      for (var index = 0; index < chunk.length; index++) {
        final product = byId[chunk[index]];
        if (product == null) {
          throw const SdifCartAnalysisMappingException(
            'Scientific identity repository omitted a requested product.',
          );
        }
        results.add(
          SdifProductScientificInput(
            requestPosition: offset + index + 1,
            productId: product.productId,
            productExists: product.productExists,
            coverageStatus: product.coverageStatus,
            canonicalizationStatus: product.canonicalizationStatus,
            ingredientCount: product.ingredientCount,
            trustedComponentCount: product.trustedComponentCount,
            atcCoveredComponentCount: product.atcCoveredComponentCount,
            eligibleIdentityCount: product.eligibleIdentityCount,
            identities: product.identities,
          ),
        );
      }
    }
    return results;
  }

  Map<int, _ScientificIdentityNode> _buildScientificNodes(
    List<SdifProductScientificInput> products,
  ) {
    final nodes = <int, _ScientificIdentityNode>{};
    for (final product in products) {
      for (final productIdentity in product.identities) {
        final identity = productIdentity.toReviewedIdentity();
        final existing = nodes[identity.scientificIngredientId];
        if (existing == null) {
          nodes[identity.scientificIngredientId] = _ScientificIdentityNode(
            identity: identity,
            productIds: <String>{product.productId},
          );
          continue;
        }

        if (existing.identity.preferredName != identity.preferredName ||
            !_sameStrings(
              existing.identity.reviewedAtcCodes,
              identity.reviewedAtcCodes,
            )) {
          throw const SdifCartAnalysisMappingException(
            'Repeated scientific ingredient ID had contradictory reviewed metadata.',
          );
        }
        existing.productIds.add(product.productId);
      }
    }
    return nodes;
  }

  List<List<_ResolvedScientificNode>> _buildProviderBatches(
    List<_ResolvedScientificNode> identities,
  ) {
    if (identities.length < 2) {
      return const [];
    }
    if (identities.length <= 10) {
      return [List.unmodifiable(identities)];
    }

    final groups = <List<_ResolvedScientificNode>>[];
    for (var offset = 0; offset < identities.length; offset += 5) {
      final end = offset + 5 < identities.length
          ? offset + 5
          : identities.length;
      groups.add(List.unmodifiable(identities.sublist(offset, end)));
    }

    final batches = <List<_ResolvedScientificNode>>[];
    for (var left = 0; left < groups.length; left++) {
      for (var right = left + 1; right < groups.length; right++) {
        batches.add(
          List.unmodifiable([...groups[left], ...groups[right]]),
        );
      }
    }
    return batches;
  }

  List<SdifProductPairAnalysis> _buildProductPairs({
    required List<String> productIds,
    required Map<int, _ScientificIdentityNode> nodes,
    required List<SdifPairAssessment> identityPairs,
  }) {
    final productIndex = <String, int>{
      for (var index = 0; index < productIds.length; index++)
        productIds[index]: index,
    };
    final accumulators = <String, _ProductPairAccumulator>{};
    final pairOrder = <String>[];

    for (var left = 0; left < productIds.length; left++) {
      for (var right = left + 1; right < productIds.length; right++) {
        final key = _indexPairKey(left, right);
        pairOrder.add(key);
        accumulators[key] = _ProductPairAccumulator(
          productAId: productIds[left],
          productBId: productIds[right],
        );
      }
    }

    for (final identityPair in identityPairs) {
      final scientificA =
          identityPair.identityA.identity.scientificIngredientId;
      final scientificB =
          identityPair.identityB.identity.scientificIngredientId;
      final nodeA = nodes[scientificA];
      final nodeB = nodes[scientificB];
      if (nodeA == null || nodeB == null) {
        throw const SdifCartAnalysisMappingException(
          'Aggregated SDIF pair referenced a scientific identity outside Cart inputs.',
        );
      }
      final identityPairKey = _scientificPairKey(scientificA, scientificB);

      for (final productAId in nodeA.productIds) {
        for (final productBId in nodeB.productIds) {
          if (productAId == productBId) {
            continue;
          }
          final aIndex = productIndex[productAId];
          final bIndex = productIndex[productBId];
          if (aIndex == null || bIndex == null) {
            throw const SdifCartAnalysisMappingException(
              'Scientific identity ownership referenced an unexpected Cart product.',
            );
          }
          final left = aIndex < bIndex ? aIndex : bIndex;
          final right = aIndex < bIndex ? bIndex : aIndex;
          accumulators[_indexPairKey(left, right)]?.identityPairs.putIfAbsent(
                identityPairKey,
                () => identityPair,
              );
        }
      }
    }

    return pairOrder.map((key) {
      final accumulator = accumulators[key]!;
      return SdifProductPairAnalysis(
        productAId: accumulator.productAId,
        productBId: accumulator.productBId,
        identityPairs: List.unmodifiable(accumulator.identityPairs.values),
      );
    }).toList(growable: false);
  }

  static bool _hasCrossProductOwnership(
    _ScientificIdentityNode a,
    _ScientificIdentityNode b,
  ) {
    for (final productA in a.productIds) {
      for (final productB in b.productIds) {
        if (productA != productB) {
          return true;
        }
      }
    }
    return false;
  }

  static List<String> _distinctProductIds(List<String> productIds) {
    final seen = <String>{};
    final result = <String>[];
    for (final rawProductId in productIds) {
      final productId = rawProductId.trim();
      if (productId.isEmpty) {
        throw const SdifCartAnalysisInvalidRequestException(
          'Cart product IDs must not be blank.',
        );
      }
      if (seen.add(productId)) {
        result.add(productId);
      }
    }
    return result;
  }

  static void _ensureCurrent(bool Function()? isCurrent) {
    if (isCurrent != null && !isCurrent()) {
      throw const SdifCartAnalysisSupersededException();
    }
  }

  static String _providerEndpointKey(SdifResolvedScientificIdentity resolved) {
    return jsonEncode([
      resolved.providerDrug.brandName.trim(),
      resolved.providerDrug.providerAtcCode.trim(),
    ]);
  }

  static String _scientificPairKey(int a, int b) {
    return a <= b ? '$a:$b' : '$b:$a';
  }

  static String _indexPairKey(int left, int right) => '$left:$right';

  static String _pairObservationFingerprint(SdifPairAssessment pair) {
    return jsonEncode([
      pair.identityA.identity.scientificIngredientId,
      pair.identityB.identity.scientificIngredientId,
      pair.observationStatus.name,
      pair.providerHitCount,
      pair.exactDuplicateHitCount,
      [
        for (final finding in pair.findings)
          [
            finding.drugAIdentity.identity.scientificIngredientId,
            finding.drugBIdentity.identity.scientificIngredientId,
            finding.providerHit.drugA,
            finding.providerHit.drugAAtc,
            finding.providerHit.drugARoute,
            finding.providerHit.drugB,
            finding.providerHit.drugBAtc,
            finding.providerHit.drugBRoute,
            finding.providerHit.family.name,
            finding.providerHit.severityScore,
            finding.providerHit.severityLabel,
            finding.providerHit.severityIndicator,
            finding.providerHit.keyword,
            finding.providerHit.description,
            finding.providerHit.explanation,
            finding.providerHit.source,
            finding.providerHit.comboHint,
          ],
      ],
    ]);
  }

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}

class _ScientificIdentityNode {
  _ScientificIdentityNode({
    required this.identity,
    required this.productIds,
  });

  final SdifReviewedScientificIdentity identity;
  final Set<String> productIds;
}

class _ResolvedScientificNode {
  const _ResolvedScientificNode({
    required this.source,
    required this.resolvedIdentity,
  });

  final _ScientificIdentityNode source;
  final SdifResolvedScientificIdentity resolvedIdentity;
}

class _ProductPairAccumulator {
  _ProductPairAccumulator({
    required this.productAId,
    required this.productBId,
  });

  final String productAId;
  final String productBId;
  final Map<String, SdifPairAssessment> identityPairs = {};
}

sealed class SdifCartAnalysisException implements Exception {
  const SdifCartAnalysisException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class SdifCartAnalysisInvalidRequestException
    extends SdifCartAnalysisException {
  const SdifCartAnalysisInvalidRequestException(super.message);
}

class SdifCartAnalysisMappingException extends SdifCartAnalysisException {
  const SdifCartAnalysisMappingException(super.message);
}

class SdifCartAnalysisSupersededException extends SdifCartAnalysisException {
  const SdifCartAnalysisSupersededException()
      : super('SDIF Cart analysis was superseded by newer Cart state.');
}
