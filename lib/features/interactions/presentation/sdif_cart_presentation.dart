import '../domain/sdif_cart_analysis_models.dart';
import '../domain/sdif_product_scientific_models.dart';

class SdifCartPresentation {
  const SdifCartPresentation({
    required this.rows,
    required this.productPairsWithFindings,
    required this.productPairsWithNoProviderHit,
    required this.uncheckedProductPairCount,
    required this.incompleteProductCount,
    required this.providerResolutionGapCount,
  });

  final Map<String, SdifProductRowPresentation> rows;
  final int productPairsWithFindings;
  final int productPairsWithNoProviderHit;
  final int uncheckedProductPairCount;
  final int incompleteProductCount;
  final int providerResolutionGapCount;

  int get totalProductPairCount =>
      productPairsWithFindings +
      productPairsWithNoProviderHit +
      uncheckedProductPairCount;
}

class SdifProductRowPresentation {
  const SdifProductRowPresentation({
    required this.productId,
    required this.coverageStatus,
    required this.relatedProductPairCount,
    required this.findingProductPairCount,
    required this.noProviderHitProductPairCount,
    required this.uncheckedProductPairCount,
    required this.providerResolutionIncomplete,
  });

  final String productId;
  final SdifScientificCoverageStatus coverageStatus;
  final int relatedProductPairCount;
  final int findingProductPairCount;
  final int noProviderHitProductPairCount;
  final int uncheckedProductPairCount;
  final bool providerResolutionIncomplete;

  int get checkedProductPairCount =>
      findingProductPairCount + noProviderHitProductPairCount;

  bool get hasProviderFindings => findingProductPairCount > 0;

  bool get hasProviderCheckedPairs => checkedProductPairCount > 0;

  bool get scientificCoverageComplete =>
      coverageStatus == SdifScientificCoverageStatus.complete;

  bool get incompleteCoverage =>
      !scientificCoverageComplete ||
      providerResolutionIncomplete ||
      uncheckedProductPairCount > 0;
}

SdifCartPresentation buildSdifCartPresentation(
  SdifCartAnalysisResult analysis,
) {
  final productInputs = <String, SdifProductScientificInput>{};
  for (final product in analysis.products) {
    if (productInputs.containsKey(product.productId)) {
      throw StateError(
        'SDIF Cart presentation received duplicate product inputs.',
      );
    }
    productInputs[product.productId] = product;
  }

  final providerGapProducts = <String>{};
  for (final gap in analysis.providerResolutionGaps) {
    for (final productId in gap.productIds) {
      if (!productInputs.containsKey(productId)) {
        throw StateError(
          'SDIF provider-resolution gap referenced an unknown product.',
        );
      }
      providerGapProducts.add(productId);
    }
  }

  final relatedPairCount = <String, int>{};
  final findingPairCount = <String, int>{};
  final noHitPairCount = <String, int>{};
  final uncheckedPairCount = <String, int>{};

  var productPairsWithFindings = 0;
  var productPairsWithNoProviderHit = 0;
  var uncheckedProductPairCount = 0;

  for (final pair in analysis.productPairs) {
    final productIds = [pair.productAId, pair.productBId];
    if (pair.productAId == pair.productBId ||
        productIds.any((productId) => !productInputs.containsKey(productId))) {
      throw StateError(
        'SDIF product-pair presentation referenced invalid product inputs.',
      );
    }

    for (final productId in productIds) {
      relatedPairCount[productId] = (relatedPairCount[productId] ?? 0) + 1;
    }

    if (pair.identityPairs.isEmpty) {
      uncheckedProductPairCount += 1;
      for (final productId in productIds) {
        uncheckedPairCount[productId] =
            (uncheckedPairCount[productId] ?? 0) + 1;
      }
      continue;
    }

    final hasFindings = pair.identityPairs.any(
      (identityPair) => identityPair.hasObservedHits,
    );
    if (hasFindings) {
      productPairsWithFindings += 1;
      for (final productId in productIds) {
        findingPairCount[productId] =
            (findingPairCount[productId] ?? 0) + 1;
      }
    } else {
      productPairsWithNoProviderHit += 1;
      for (final productId in productIds) {
        noHitPairCount[productId] = (noHitPairCount[productId] ?? 0) + 1;
      }
    }
  }

  final rows = <String, SdifProductRowPresentation>{};
  var incompleteProductCount = 0;
  for (final product in analysis.products) {
    final row = SdifProductRowPresentation(
      productId: product.productId,
      coverageStatus: product.coverageStatus,
      relatedProductPairCount: relatedPairCount[product.productId] ?? 0,
      findingProductPairCount: findingPairCount[product.productId] ?? 0,
      noProviderHitProductPairCount: noHitPairCount[product.productId] ?? 0,
      uncheckedProductPairCount: uncheckedPairCount[product.productId] ?? 0,
      providerResolutionIncomplete:
          providerGapProducts.contains(product.productId),
    );
    rows[product.productId] = row;
    if (row.incompleteCoverage) {
      incompleteProductCount += 1;
    }
  }

  return SdifCartPresentation(
    rows: Map.unmodifiable(rows),
    productPairsWithFindings: productPairsWithFindings,
    productPairsWithNoProviderHit: productPairsWithNoProviderHit,
    uncheckedProductPairCount: uncheckedProductPairCount,
    incompleteProductCount: incompleteProductCount,
    providerResolutionGapCount: analysis.providerResolutionGaps.length,
  );
}
