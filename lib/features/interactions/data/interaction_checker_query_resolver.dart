import '../domain/ddi_analysis_models.dart';

typedef DdiProviderQueryResolver = String Function(
  DdiIngredientIdentity ingredient,
);

String resolveInteractionCheckerQuery(
  DdiIngredientIdentity ingredient,
) {
  final normalizedName = ingredient.normalizedName.trim().toLowerCase();
  final alias = _interactionCheckerAliases[normalizedName];
  return (alias ?? ingredient.name).trim();
}

const Map<String, String> _interactionCheckerAliases = {
  'acetylsalicylic acid': 'aspirin',
};
