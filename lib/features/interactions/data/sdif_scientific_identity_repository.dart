import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/sdif_product_scientific_models.dart';

abstract interface class SdifScientificIdentityRpcClient {
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  });
}

class SupabaseSdifScientificIdentityRpcClient
    implements SdifScientificIdentityRpcClient {
  SupabaseSdifScientificIdentityRpcClient(this.client);

  final SupabaseClient client;

  @override
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    return await client.rpc(functionName, params: params);
  }
}

abstract interface class SdifScientificIdentityRepository {
  Future<List<SdifProductScientificInput>> resolveProducts(
    List<String> productIds,
  );
}

class SupabaseSdifScientificIdentityRepository
    implements SdifScientificIdentityRepository {
  SupabaseSdifScientificIdentityRepository(this.rpcClient);

  factory SupabaseSdifScientificIdentityRepository.fromClient(
    SupabaseClient client,
  ) {
    return SupabaseSdifScientificIdentityRepository(
      SupabaseSdifScientificIdentityRpcClient(client),
    );
  }

  static const int maxProductIdsPerRequest = 50;

  final SdifScientificIdentityRpcClient rpcClient;

  @override
  Future<List<SdifProductScientificInput>> resolveProducts(
    List<String> productIds,
  ) async {
    final requested = _distinctProductIds(productIds);
    if (requested.isEmpty) {
      return const [];
    }
    if (requested.length > maxProductIdsPerRequest) {
      throw const SdifScientificIdentityRequestException(
        'At most 50 distinct product IDs may be resolved per request.',
      );
    }

    late final dynamic response;
    try {
      response = await rpcClient.call(
        'catalog_sdif_scientific_identities',
        params: {'requested_product_ids': requested},
      );
    } catch (_) {
      throw const SdifScientificIdentityTransportException();
    }

    if (response is! List) {
      throw const SdifScientificIdentityResponseException();
    }

    final rows = response.map((value) {
      if (value is! Map) {
        throw const SdifScientificIdentityResponseException();
      }
      return Map<String, dynamic>.from(value);
    }).toList(growable: false);

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final productId = _requiredString(row, 'product_id');
      grouped.putIfAbsent(productId, () => []).add(row);
    }

    final results = <SdifProductScientificInput>[];
    for (var index = 0; index < requested.length; index++) {
      final productId = requested[index];
      final productRows = grouped[productId];
      if (productRows == null || productRows.isEmpty) {
        throw const SdifScientificIdentityResponseException();
      }
      final parsed = _parseProductRows(productId, productRows);
      if (parsed.requestPosition != index + 1) {
        throw const SdifScientificIdentityResponseException();
      }
      results.add(parsed);
    }

    if (grouped.length != requested.length) {
      throw const SdifScientificIdentityResponseException();
    }

    return List.unmodifiable(results);
  }

  SdifProductScientificInput _parseProductRows(
    String productId,
    List<Map<String, dynamic>> rows,
  ) {
    final first = rows.first;
    final requestPosition = _requiredInt(first, 'request_position');
    final productExists = _requiredBool(first, 'product_exists');
    final coverageStatus = _coverageStatus(
      _requiredString(first, 'coverage_status'),
    );
    final canonicalizationStatus = _optionalString(
      first,
      'canonicalization_status',
    );
    final ingredientCount = _requiredNonNegativeInt(first, 'ingredient_count');
    final trustedComponentCount = _requiredNonNegativeInt(
      first,
      'trusted_component_count',
    );
    final atcCoveredComponentCount = _requiredNonNegativeInt(
      first,
      'atc_covered_component_count',
    );
    final eligibleIdentityCount = _requiredNonNegativeInt(
      first,
      'eligible_identity_count',
    );

    if (trustedComponentCount > ingredientCount ||
        atcCoveredComponentCount > trustedComponentCount ||
        eligibleIdentityCount > atcCoveredComponentCount) {
      throw const SdifScientificIdentityResponseException();
    }

    for (final row in rows.skip(1)) {
      if (_requiredInt(row, 'request_position') != requestPosition ||
          _requiredString(row, 'product_id') != productId ||
          _requiredBool(row, 'product_exists') != productExists ||
          _coverageStatus(_requiredString(row, 'coverage_status')) !=
              coverageStatus ||
          _optionalString(row, 'canonicalization_status') !=
              canonicalizationStatus ||
          _requiredNonNegativeInt(row, 'ingredient_count') !=
              ingredientCount ||
          _requiredNonNegativeInt(row, 'trusted_component_count') !=
              trustedComponentCount ||
          _requiredNonNegativeInt(row, 'atc_covered_component_count') !=
              atcCoveredComponentCount ||
          _requiredNonNegativeInt(row, 'eligible_identity_count') !=
              eligibleIdentityCount) {
        throw const SdifScientificIdentityResponseException();
      }
    }

    final identityRows = rows.where(
      (row) => row['scientific_ingredient_id'] != null,
    ).toList(growable: false)
      ..sort(
        (left, right) => _requiredInt(left, 'identity_position').compareTo(
          _requiredInt(right, 'identity_position'),
        ),
      );

    if (identityRows.length != eligibleIdentityCount) {
      throw const SdifScientificIdentityResponseException();
    }

    final identities = <SdifProductScientificIdentity>[];
    final seenIds = <int>{};
    for (var index = 0; index < identityRows.length; index++) {
      final row = identityRows[index];
      final identityPosition = _requiredInt(row, 'identity_position');
      if (identityPosition != index + 1) {
        throw const SdifScientificIdentityResponseException();
      }
      final scientificId = _requiredPositiveInt(
        row,
        'scientific_ingredient_id',
      );
      if (!seenIds.add(scientificId)) {
        throw const SdifScientificIdentityResponseException();
      }

      identities.add(
        SdifProductScientificIdentity(
          scientificIngredientId: scientificId,
          preferredName: _requiredString(row, 'preferred_name'),
          reviewedAtcCodes: _requiredAtcCodes(row, 'reviewed_atc_codes'),
        ),
      );
    }

    final nullIdentityRows = rows.length - identityRows.length;
    if (eligibleIdentityCount == 0) {
      if (rows.length != 1 || nullIdentityRows != 1 ||
          first['identity_position'] != null ||
          first['preferred_name'] != null ||
          first['reviewed_atc_codes'] != null) {
        throw const SdifScientificIdentityResponseException();
      }
    } else if (nullIdentityRows != 0) {
      throw const SdifScientificIdentityResponseException();
    }

    _validateCoverage(
      productExists: productExists,
      coverageStatus: coverageStatus,
      canonicalizationStatus: canonicalizationStatus,
      ingredientCount: ingredientCount,
      trustedComponentCount: trustedComponentCount,
      atcCoveredComponentCount: atcCoveredComponentCount,
      eligibleIdentityCount: eligibleIdentityCount,
    );

    return SdifProductScientificInput(
      requestPosition: requestPosition,
      productId: productId,
      productExists: productExists,
      coverageStatus: coverageStatus,
      canonicalizationStatus: canonicalizationStatus,
      ingredientCount: ingredientCount,
      trustedComponentCount: trustedComponentCount,
      atcCoveredComponentCount: atcCoveredComponentCount,
      eligibleIdentityCount: eligibleIdentityCount,
      identities: List.unmodifiable(identities),
    );
  }

  static void _validateCoverage({
    required bool productExists,
    required SdifScientificCoverageStatus coverageStatus,
    required String? canonicalizationStatus,
    required int ingredientCount,
    required int trustedComponentCount,
    required int atcCoveredComponentCount,
    required int eligibleIdentityCount,
  }) {
    switch (coverageStatus) {
      case SdifScientificCoverageStatus.missing:
        if (productExists || canonicalizationStatus != null ||
            ingredientCount != 0 || trustedComponentCount != 0 ||
            atcCoveredComponentCount != 0 || eligibleIdentityCount != 0) {
          throw const SdifScientificIdentityResponseException();
        }
      case SdifScientificCoverageStatus.complete:
        if (!productExists || ingredientCount <= 0 ||
            atcCoveredComponentCount != ingredientCount ||
            eligibleIdentityCount <= 0) {
          throw const SdifScientificIdentityResponseException();
        }
      case SdifScientificCoverageStatus.partial:
        if (!productExists || ingredientCount <= 0 ||
            atcCoveredComponentCount <= 0 ||
            atcCoveredComponentCount >= ingredientCount ||
            eligibleIdentityCount <= 0) {
          throw const SdifScientificIdentityResponseException();
        }
      case SdifScientificCoverageStatus.unmapped:
        if (!productExists || atcCoveredComponentCount != 0 ||
            eligibleIdentityCount != 0) {
          throw const SdifScientificIdentityResponseException();
        }
    }
  }

  static List<String> _distinctProductIds(List<String> productIds) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in productIds) {
      final productId = raw.trim();
      if (productId.isEmpty) {
        throw const SdifScientificIdentityRequestException(
          'Product IDs must not be blank.',
        );
      }
      if (seen.add(productId)) {
        result.add(productId);
      }
    }
    return result;
  }

  static SdifScientificCoverageStatus _coverageStatus(String value) {
    return switch (value) {
      'complete' => SdifScientificCoverageStatus.complete,
      'partial' => SdifScientificCoverageStatus.partial,
      'unmapped' => SdifScientificCoverageStatus.unmapped,
      'missing' => SdifScientificCoverageStatus.missing,
      _ => throw const SdifScientificIdentityResponseException(),
    };
  }

  static List<String> _requiredAtcCodes(
    Map<String, dynamic> row,
    String key,
  ) {
    final value = row[key];
    if (value is! List || value.isEmpty) {
      throw const SdifScientificIdentityResponseException();
    }

    final result = <String>[];
    final seen = <String>{};
    for (final item in value) {
      if (item is! String) {
        throw const SdifScientificIdentityResponseException();
      }
      final code = item.trim();
      if (code.isEmpty || code.length > 32 || code != code.toUpperCase() ||
          !seen.add(code)) {
        throw const SdifScientificIdentityResponseException();
      }
      result.add(code);
    }

    final sorted = [...result]..sort();
    for (var index = 0; index < result.length; index++) {
      if (result[index] != sorted[index]) {
        throw const SdifScientificIdentityResponseException();
      }
    }
    return List.unmodifiable(result);
  }

  static int _requiredPositiveInt(Map<String, dynamic> row, String key) {
    final value = _requiredInt(row, key);
    if (value <= 0) {
      throw const SdifScientificIdentityResponseException();
    }
    return value;
  }

  static int _requiredNonNegativeInt(Map<String, dynamic> row, String key) {
    final value = _requiredInt(row, key);
    if (value < 0) {
      throw const SdifScientificIdentityResponseException();
    }
    return value;
  }

  static int _requiredInt(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! int) {
      throw const SdifScientificIdentityResponseException();
    }
    return value;
  }

  static bool _requiredBool(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! bool) {
      throw const SdifScientificIdentityResponseException();
    }
    return value;
  }

  static String _requiredString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw const SdifScientificIdentityResponseException();
    }
    return value.trim();
  }

  static String? _optionalString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) {
      return null;
    }
    if (value is! String || value.trim().isEmpty) {
      throw const SdifScientificIdentityResponseException();
    }
    return value.trim();
  }
}

sealed class SdifScientificIdentityRepositoryException implements Exception {
  const SdifScientificIdentityRepositoryException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class SdifScientificIdentityRequestException
    extends SdifScientificIdentityRepositoryException {
  const SdifScientificIdentityRequestException(super.message);
}

class SdifScientificIdentityTransportException
    extends SdifScientificIdentityRepositoryException {
  const SdifScientificIdentityTransportException()
      : super('Unable to load reviewed scientific identities.');
}

class SdifScientificIdentityResponseException
    extends SdifScientificIdentityRepositoryException {
  const SdifScientificIdentityResponseException()
      : super('Reviewed scientific identity response was malformed.');
}
