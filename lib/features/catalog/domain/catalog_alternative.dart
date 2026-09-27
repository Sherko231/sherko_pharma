import 'catalog_product.dart';

enum CatalogAlternativeGroup {
  exact('exact'),
  sameIngredientsDifferentStrength('same_ingredients_different_strength'),
  sameIngredientsDifferentForm('same_ingredients_different_form');

  const CatalogAlternativeGroup(this.rpcValue);

  final String rpcValue;

  static CatalogAlternativeGroup fromRpcValue(Object? value) {
    if (value is! String) {
      throw const FormatException(
        'Catalog alternative relationship_group must be text.',
      );
    }

    for (final group in values) {
      if (group.rpcValue == value) {
        return group;
      }
    }

    throw FormatException(
      'Unsupported catalog alternative relationship_group: ' + value,
    );
  }
}

enum CatalogNormalizationStatus {
  autoVerified('auto_verified'),
  highConfidence('high_confidence');

  const CatalogNormalizationStatus(this.rpcValue);

  final String rpcValue;

  static CatalogNormalizationStatus fromRpcValue(Object? value) {
    if (value is! String) {
      throw const FormatException(
        'Catalog alternative normalization_status must be text.',
      );
    }

    for (final status in values) {
      if (status.rpcValue == value) {
        return status;
      }
    }

    throw FormatException(
      'Unsupported catalog alternative normalization_status: ' + value,
    );
  }
}

class CatalogAlternative {
  const CatalogAlternative({
    required this.group,
    required this.groupPosition,
    required this.normalizationStatus,
    required this.product,
  });

  final CatalogAlternativeGroup group;
  final int groupPosition;
  final CatalogNormalizationStatus normalizationStatus;
  final CatalogProduct product;

  factory CatalogAlternative.fromRpcRow(Map<String, dynamic> row) {
    final groupPosition = row['group_position'];
    if (groupPosition is! int || groupPosition < 1) {
      throw const FormatException(
        'Catalog alternative group_position must be a positive integer.',
      );
    }

    return CatalogAlternative(
      group: CatalogAlternativeGroup.fromRpcValue(
        row['relationship_group'],
      ),
      groupPosition: groupPosition,
      normalizationStatus: CatalogNormalizationStatus.fromRpcValue(
        row['normalization_status'],
      ),
      product: CatalogProduct.fromRpcRow(row),
    );
  }
}
