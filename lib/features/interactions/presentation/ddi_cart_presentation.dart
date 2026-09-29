import '../domain/ddi_analysis_models.dart';
import '../domain/interaction_check_models.dart';

class DdiCartPresentation {
  const DdiCartPresentation({
    required this.rows,
    required this.pairCounts,
    required this.incompleteProductCount,
    required this.providerNotices,
  });

  final Map<String, DdiProductRowPresentation> rows;
  final Map<InteractionSeverity, int> pairCounts;
  final int incompleteProductCount;
  final List<DdiProviderNotice> providerNotices;

  int pairCount(InteractionSeverity severity) => pairCounts[severity] ?? 0;

  int get totalPairCount =>
      pairCounts.values.fold<int>(0, (total, count) => total + count);
}

class DdiProductRowPresentation {
  const DdiProductRowPresentation({
    required this.productId,
    required this.pairCount,
    required this.localCoverage,
    required this.providerUnresolved,
    required this.providerMappingIncomplete,
    this.severity,
  });

  final String productId;
  final InteractionSeverity? severity;
  final int pairCount;
  final DdiIngredientCoverageStatus localCoverage;
  final bool providerUnresolved;
  final bool providerMappingIncomplete;

  bool get localCoverageComplete =>
      localCoverage == DdiIngredientCoverageStatus.trusted;

  bool get incompleteCoverage =>
      !localCoverageComplete ||
      providerMappingIncomplete ||
      providerUnresolved ||
      pairCount == 0;
}

DdiCartPresentation buildDdiCartPresentation(
  DdiAnalysisResult analysis,
) {
  final productInputs = <String, DdiProductIngredientInput>{
    for (final product in analysis.products) product.productId: product,
  };
  final providerUnresolvedProducts = <String>{
    for (final unresolved in analysis.providerUnresolved)
      ...unresolved.productIds,
  };
  final providerMappingGapProducts = <String>{
    for (final gap in analysis.providerMappingGaps)
      ...gap.productIds,
  };
  final pairCounts = <InteractionSeverity, int>{
    for (final severity in InteractionSeverity.values) severity: 0,
  };
  final pairSeverityByProduct = <String, InteractionSeverity>{};
  final pairCountByProduct = <String, int>{};

  for (final pair in analysis.productPairs) {
    pairCounts[pair.severity] = (pairCounts[pair.severity] ?? 0) + 1;

    for (final productId in [pair.productAId, pair.productBId]) {
      final current = pairSeverityByProduct[productId];
      pairSeverityByProduct[productId] = current == null
          ? pair.severity
          : higherDdiSeverity(current, pair.severity);
      pairCountByProduct[productId] =
          (pairCountByProduct[productId] ?? 0) + 1;
    }
  }

  final rows = <String, DdiProductRowPresentation>{};
  var incompleteProductCount = 0;

  for (final entry in productInputs.entries) {
    final productId = entry.key;
    final row = DdiProductRowPresentation(
      productId: productId,
      severity: pairSeverityByProduct[productId],
      pairCount: pairCountByProduct[productId] ?? 0,
      localCoverage: entry.value.coverageStatus,
      providerUnresolved: providerUnresolvedProducts.contains(productId),
      providerMappingIncomplete:
          providerMappingGapProducts.contains(productId),
    );
    rows[productId] = row;
    if (row.incompleteCoverage) {
      incompleteProductCount += 1;
    }
  }

  return DdiCartPresentation(
    rows: Map.unmodifiable(rows),
    pairCounts: Map.unmodifiable(pairCounts),
    incompleteProductCount: incompleteProductCount,
    providerNotices: List.unmodifiable(
      _deduplicateCartProviderNotices(analysis.providerNotices),
    ),
  );
}

List<DdiProviderNotice> _deduplicateCartProviderNotices(
  List<DdiProviderNotice> notices,
) {
  final seen = <String>{};
  final result = <DdiProviderNotice>[];
  for (final notice in notices) {
    final key = [
      notice.disclaimer,
      notice.attribution.text ?? '',
      notice.attribution.url?.toString() ?? '',
      notice.attribution.license ?? '',
    ].join('\u0000');
    if (seen.add(key)) {
      result.add(notice);
    }
  }
  return result;
}
