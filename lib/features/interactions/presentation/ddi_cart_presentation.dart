import '../domain/ddi_analysis_models.dart';
import '../domain/interaction_check_models.dart';

class DdiCartPresentation {
  const DdiCartPresentation({
    required this.rows,
    required this.pairCounts,
    required this.incompleteProductCount,
  });

  final Map<String, DdiProductRowPresentation> rows;
  final Map<InteractionSeverity, int> pairCounts;
  final int incompleteProductCount;

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
    this.severity,
  });

  final String productId;
  final InteractionSeverity? severity;
  final int pairCount;
  final DdiIngredientCoverageStatus localCoverage;
  final bool providerUnresolved;

  bool get localCoverageComplete =>
      localCoverage == DdiIngredientCoverageStatus.trusted;

  bool get incompleteCoverage =>
      !localCoverageComplete || providerUnresolved || pairCount == 0;
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
  );
}
