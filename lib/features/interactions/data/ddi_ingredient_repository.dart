import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/ddi_analysis_models.dart';

abstract interface class DdiIngredientRpcClient {
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  });
}

class SupabaseDdiIngredientRpcClient implements DdiIngredientRpcClient {
  SupabaseDdiIngredientRpcClient(this.client);

  final SupabaseClient client;

  @override
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    return await client.rpc(functionName, params: params);
  }
}

abstract interface class DdiIngredientRepository {
  Future<List<DdiProductIngredientInput>> resolveProducts(
    List<String> productIds,
  );
}

class SupabaseDdiIngredientRepository implements DdiIngredientRepository {
  SupabaseDdiIngredientRepository(this.rpcClient);

  factory SupabaseDdiIngredientRepository.fromClient(
    SupabaseClient client,
  ) {
    return SupabaseDdiIngredientRepository(
      SupabaseDdiIngredientRpcClient(client),
    );
  }

  static const int maxProductIdsPerRequest = 50;

  final DdiIngredientRpcClient rpcClient;

  @override
  Future<List<DdiProductIngredientInput>> resolveProducts(
    List<String> productIds,
  ) async {
    final requested = _distinctProductIds(productIds);
    if (requested.isEmpty) {
      return const [];
    }
    if (requested.length > maxProductIdsPerRequest) {
      throw const DdiIngredientRequestException(
        'At most 50 distinct product IDs may be resolved per request.',
      );
    }

    late final dynamic response;
    try {
      response = await rpcClient.call(
        'catalog_ddi_ingredients',
        params: {'requested_product_ids': requested},
      );
    } catch (_) {
      throw const DdiIngredientTransportException();
    }

    if (response is! List) {
      throw const DdiIngredientResponseException();
    }

    final rows = response.map((value) {
      if (value is! Map) {
        throw const DdiIngredientResponseException();
      }
      return Map<String, dynamic>.from(value);
    }).toList(growable: false);

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final productId = _requiredString(row, 'product_id');
      grouped.putIfAbsent(productId, () => []).add(row);
    }

    final results = <DdiProductIngredientInput>[];
    for (var index = 0; index < requested.length; index++) {
      final productId = requested[index];
      final productRows = grouped[productId];
      if (productRows == null || productRows.isEmpty) {
        throw const DdiIngredientResponseException();
      }
      final parsed = _parseProductRows(productId, productRows);
      if (parsed.requestPosition != index + 1) {
        throw const DdiIngredientResponseException();
      }
      results.add(parsed);
    }

    if (grouped.keys.any((id) => !requested.contains(id))) {
      throw const DdiIngredientResponseException();
    }

    return List.unmodifiable(results);
  }

  DdiProductIngredientInput _parseProductRows(
    String productId,
    List<Map<String, dynamic>> rows,
  ) {
    final first = rows.first;
    final requestPosition = _requiredInt(first, 'request_position');
    final productExists = _requiredBool(first, 'product_exists');
    final coverageStatus = _parseCoverageStatus(
      _requiredString(first, 'coverage_status'),
    );
    final normalizationStatus = _optionalString(
      first,
      'normalization_status',
    );
    final componentCount = _optionalInt(first, 'component_count');
    final resolvedComponentCount = _optionalInt(
      first,
      'resolved_component_count',
    );

    final orderedIngredients = <MapEntry<int, DdiIngredientIdentity>>[];
    for (final row in rows) {
      if (_requiredInt(row, 'request_position') != requestPosition ||
          _requiredBool(row, 'product_exists') != productExists ||
          _parseCoverageStatus(_requiredString(row, 'coverage_status')) !=
              coverageStatus ||
          _optionalString(row, 'normalization_status') !=
              normalizationStatus ||
          _optionalInt(row, 'component_count') != componentCount ||
          _optionalInt(row, 'resolved_component_count') !=
              resolvedComponentCount) {
        throw const DdiIngredientResponseException();
      }

      if (coverageStatus == DdiIngredientCoverageStatus.trusted) {
        final providerStatusValue = _optionalString(
          row,
          'provider_mapping_status',
        );
        final providerStatus = providerStatusValue == null
            ? DdiProviderMappingStatus.mapped
            : _parseProviderMappingStatus(providerStatusValue);
        final providerSubstanceId = _optionalString(
          row,
          'provider_substance_id',
        );
        final providerSubstanceName = _optionalString(
          row,
          'provider_substance_name',
        );
        final providerSubstanceKind = _optionalString(
          row,
          'provider_substance_kind',
        );
        final providerMappingMethod = _optionalString(
          row,
          'provider_mapping_method',
        );

        if (providerStatusValue != null) {
          if (providerStatus == DdiProviderMappingStatus.mapped) {
            if (providerSubstanceId == null ||
                providerSubstanceName == null ||
                providerSubstanceKind == null ||
                providerMappingMethod == null) {
              throw const DdiIngredientResponseException();
            }
          } else if (providerSubstanceId != null ||
              providerSubstanceName != null ||
              providerSubstanceKind != null) {
            throw const DdiIngredientResponseException();
          }
        }

        orderedIngredients.add(
          MapEntry(
            _requiredInt(row, 'component_index'),
            DdiIngredientIdentity(
              id: _requiredInt(row, 'ingredient_id'),
              name: _requiredString(row, 'ingredient_name'),
              normalizedName: _requiredString(
                row,
                'normalized_ingredient_name',
              ),
              providerMappingStatus: providerStatus,
              providerSubstanceId: providerSubstanceId,
              providerSubstanceName: providerSubstanceName,
              providerSubstanceKind: providerSubstanceKind,
              providerMappingMethod: providerMappingMethod,
            ),
          ),
        );
      } else if (row['ingredient_id'] != null ||
          row['ingredient_name'] != null ||
          row['normalized_ingredient_name'] != null ||
          row['component_index'] != null ||
          row['provider_mapping_status'] != null ||
          row['provider_substance_id'] != null ||
          row['provider_substance_name'] != null ||
          row['provider_substance_kind'] != null ||
          row['provider_mapping_method'] != null) {
        throw const DdiIngredientResponseException();
      }
    }

    orderedIngredients.sort(
      (left, right) => left.key.compareTo(right.key),
    );
    final ingredients = orderedIngredients
        .map((entry) => entry.value)
        .toList(growable: false);

    if (coverageStatus == DdiIngredientCoverageStatus.trusted &&
        ingredients.isEmpty) {
      throw const DdiIngredientResponseException();
    }

    _validateCoverage(
      coverageStatus: coverageStatus,
      productExists: productExists,
      normalizationStatus: normalizationStatus,
      componentCount: componentCount,
      resolvedComponentCount: resolvedComponentCount,
      ingredientCount: ingredients.length,
    );

    return DdiProductIngredientInput(
      productId: productId,
      requestPosition: requestPosition,
      coverageStatus: coverageStatus,
      productExists: productExists,
      normalizationStatus: normalizationStatus,
      componentCount: componentCount,
      resolvedComponentCount: resolvedComponentCount,
      ingredients: List.unmodifiable(ingredients),
    );
  }

  List<String> _distinctProductIds(List<String> productIds) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in productIds) {
      final productId = raw.trim();
      if (productId.isEmpty) {
        throw const DdiIngredientRequestException(
          'Product IDs must not be blank.',
        );
      }
      if (seen.add(productId)) {
        result.add(productId);
      }
    }
    return result;
  }
}

sealed class DdiIngredientRepositoryException implements Exception {
  const DdiIngredientRepositoryException();
}

class DdiIngredientTransportException
    extends DdiIngredientRepositoryException {
  const DdiIngredientTransportException();
}

class DdiIngredientRequestException
    extends DdiIngredientRepositoryException {
  const DdiIngredientRequestException(this.message);

  final String message;
}

class DdiIngredientResponseException
    extends DdiIngredientRepositoryException {
  const DdiIngredientResponseException();
}

void _validateCoverage({
  required DdiIngredientCoverageStatus coverageStatus,
  required bool productExists,
  required String? normalizationStatus,
  required int? componentCount,
  required int? resolvedComponentCount,
  required int ingredientCount,
}) {
  switch (coverageStatus) {
    case DdiIngredientCoverageStatus.trusted:
      if (!productExists ||
          (normalizationStatus != 'auto_verified' &&
              normalizationStatus != 'high_confidence') ||
          componentCount == null ||
          componentCount < 1 ||
          resolvedComponentCount != componentCount ||
          ingredientCount != componentCount) {
        throw const DdiIngredientResponseException();
      }
      break;
    case DdiIngredientCoverageStatus.needsReview:
      if (!productExists ||
          normalizationStatus != 'needs_review' ||
          ingredientCount != 0) {
        throw const DdiIngredientResponseException();
      }
      break;
    case DdiIngredientCoverageStatus.unresolved:
      if (!productExists ||
          (normalizationStatus != null &&
              normalizationStatus != 'unresolved') ||
          ingredientCount != 0) {
        throw const DdiIngredientResponseException();
      }
      break;
    case DdiIngredientCoverageStatus.missing:
      if (productExists ||
          normalizationStatus != null ||
          ingredientCount != 0) {
        throw const DdiIngredientResponseException();
      }
      break;
  }
}

DdiProviderMappingStatus _parseProviderMappingStatus(
  String value,
) {
  return switch (value) {
    'mapped' => DdiProviderMappingStatus.mapped,
    'ambiguous' => DdiProviderMappingStatus.ambiguous,
    'unmapped' => DdiProviderMappingStatus.unmapped,
    _ => throw const DdiIngredientResponseException(),
  };
}

DdiIngredientCoverageStatus _parseCoverageStatus(String value) {
  return switch (value) {
    'trusted' => DdiIngredientCoverageStatus.trusted,
    'needs_review' => DdiIngredientCoverageStatus.needsReview,
    'unresolved' => DdiIngredientCoverageStatus.unresolved,
    'missing' => DdiIngredientCoverageStatus.missing,
    _ => throw const DdiIngredientResponseException(),
  };
}

String _requiredString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || value.isEmpty) {
    throw const DdiIngredientResponseException();
  }
  return value;
}

String? _optionalString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const DdiIngredientResponseException();
  }
  return value;
}

int _requiredInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! int) {
    throw const DdiIngredientResponseException();
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value == null) {
    return null;
  }
  if (value is! int) {
    throw const DdiIngredientResponseException();
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! bool) {
    throw const DdiIngredientResponseException();
  }
  return value;
}
