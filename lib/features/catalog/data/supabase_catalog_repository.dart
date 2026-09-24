import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/catalog_product.dart';
import 'catalog_repository.dart';

abstract interface class CatalogRpcClient {
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  });
}

class SupabaseCatalogRpcClient implements CatalogRpcClient {
  SupabaseCatalogRpcClient(this.client);

  final SupabaseClient client;

  @override
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  }) {
    return client.rpc(functionName, params: params);
  }
}

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this.rpcClient);

  factory SupabaseCatalogRepository.fromClient(SupabaseClient client) {
    return SupabaseCatalogRepository(
      SupabaseCatalogRpcClient(client),
    );
  }

  static const int maxClientSearchResults = 25;

  final CatalogRpcClient rpcClient;

  @override
  Future<List<CatalogProduct>> search(
    String query, {
    int limit = maxClientSearchResults,
  }) async {
    final boundedLimit = limit.clamp(1, maxClientSearchResults);

    try {
      final response = await rpcClient.call(
        'catalog_search',
        params: {
          'search_text': query,
          'requested_limit': boundedLimit,
        },
      );

      final rows = _rowsFromResponse(response);
      return rows.map(CatalogProduct.fromRpcRow).toList(growable: false);
    } on CatalogRepositoryException {
      rethrow;
    } on FormatException {
      throw const CatalogResponseException();
    } catch (_) {
      throw const CatalogRepositoryException();
    }
  }

  @override
  Future<CatalogProduct> getById(String productId) async {
    try {
      final response = await rpcClient.call(
        'catalog_get',
        params: {
          'product_id': productId,
        },
      );

      final rows = _rowsFromResponse(response);
      if (rows.isEmpty) {
        throw const CatalogNotFoundException();
      }
      if (rows.length != 1) {
        throw const CatalogResponseException();
      }
      return CatalogProduct.fromRpcRow(rows.single);
    } on CatalogRepositoryException {
      rethrow;
    } on FormatException {
      throw const CatalogResponseException();
    } catch (_) {
      throw const CatalogRepositoryException();
    }
  }

  List<Map<String, dynamic>> _rowsFromResponse(dynamic response) {
    if (response is! List) {
      throw const CatalogResponseException();
    }

    return response.map((row) {
      if (row is! Map) {
        throw const CatalogResponseException();
      }
      return Map<String, dynamic>.from(row);
    }).toList(growable: false);
  }
}
