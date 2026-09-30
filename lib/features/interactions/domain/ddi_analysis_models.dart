import 'interaction_check_models.dart';

enum DdiIngredientCoverageStatus {
  trusted,
  needsReview,
  unresolved,
  missing,
}

enum DdiProviderMappingStatus {
  mapped,
  ambiguous,
  unmapped,
}

class DdiIngredientIdentity {
  const DdiIngredientIdentity({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.providerMappingStatus = DdiProviderMappingStatus.mapped,
    this.providerSubstanceId,
    this.providerSubstanceName,
    this.providerSubstanceKind,
    this.providerMappingMethod,
  });

  final int id;
  final String name;
  final String normalizedName;
  final DdiProviderMappingStatus providerMappingStatus;
  final String? providerSubstanceId;
  final String? providerSubstanceName;
  final String? providerSubstanceKind;
  final String? providerMappingMethod;
}

class DdiProductIngredientInput {
  const DdiProductIngredientInput({
    required this.productId,
    required this.requestPosition,
    required this.coverageStatus,
    required this.productExists,
    required this.ingredients,
    this.normalizationStatus,
    this.componentCount,
    this.resolvedComponentCount,
  });

  final String productId;
  final int requestPosition;
  final DdiIngredientCoverageStatus coverageStatus;
  final bool productExists;
  final String? normalizationStatus;
  final int? componentCount;
  final int? resolvedComponentCount;
  final List<DdiIngredientIdentity> ingredients;

  bool get isTrusted =>
      coverageStatus == DdiIngredientCoverageStatus.trusted;
}

class DdiProviderMappingGap {
  const DdiProviderMappingGap({
    required this.ingredient,
    required this.status,
    required this.productIds,
  });

  final DdiIngredientIdentity ingredient;
  final DdiProviderMappingStatus status;
  final List<String> productIds;
}

class DdiProviderUnresolvedIngredient {
  const DdiProviderUnresolvedIngredient({
    required this.ingredient,
    required this.query,
    required this.productIds,
    required this.suggestions,
  });

  final DdiIngredientIdentity ingredient;
  final String query;
  final List<String> productIds;
  final List<InteractionSubstance> suggestions;
}

class DdiIngredientInteraction {
  const DdiIngredientInteraction({
    required this.ingredientA,
    required this.ingredientB,
    required this.severity,
    required this.severityLabel,
    required this.evidence,
    required this.interactionUrl,
    this.detailPage,
  });

  final DdiIngredientIdentity ingredientA;
  final DdiIngredientIdentity ingredientB;
  final InteractionSeverity severity;
  final String severityLabel;
  final List<InteractionEvidence> evidence;
  final Uri interactionUrl;
  final Uri? detailPage;
}

class DdiProductPairInteraction {
  const DdiProductPairInteraction({
    required this.productAId,
    required this.productBId,
    required this.severity,
    required this.ingredientInteractions,
  });

  final String productAId;
  final String productBId;
  final InteractionSeverity severity;
  final List<DdiIngredientInteraction> ingredientInteractions;
}

class DdiProviderNotice {
  const DdiProviderNotice({
    required this.data,
    required this.disclaimer,
    required this.attribution,
  });

  final InteractionCheckData data;
  final String disclaimer;
  final InteractionAttribution attribution;
}

class DdiAnalysisResult {
  const DdiAnalysisResult({
    required this.products,
    required this.providerUnresolved,
    required this.productPairs,
    required this.providerNotices,
    required this.uniqueIngredientCount,
    required this.providerBatchCount,
    this.providerMappingGaps = const [],
  });

  final List<DdiProductIngredientInput> products;
  final List<DdiProviderUnresolvedIngredient> providerUnresolved;
  final List<DdiProviderMappingGap> providerMappingGaps;
  final List<DdiProductPairInteraction> productPairs;
  final List<DdiProviderNotice> providerNotices;
  final int uniqueIngredientCount;
  final int providerBatchCount;
}

int ddiSeverityRank(InteractionSeverity severity) {
  return switch (severity) {
    InteractionSeverity.major => 5,
    InteractionSeverity.moderate => 4,
    InteractionSeverity.minor => 3,
    InteractionSeverity.unknown => 2,
    InteractionSeverity.none => 1,
  };
}

InteractionSeverity higherDdiSeverity(
  InteractionSeverity left,
  InteractionSeverity right,
) {
  return ddiSeverityRank(left) >= ddiSeverityRank(right) ? left : right;
}
