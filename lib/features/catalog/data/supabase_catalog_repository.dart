import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/catalog_product.dart';
import '../domain/catalog_product_input.dart';
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
  }) async {
    try {
      return await client.rpc(functionName, params: params);
    } catch (error) {
      throw CatalogRpcException(
        code: _readErrorCode(error),
      );
    }
  }

  String? _readErrorCode(Object error) {
    try {
      final dynamic dynamicError = error;
      final dynamic code = dynamicError.code;
      return code is String ? code : null;
    } catch (_) {
      return null;
    }
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
  Future<List<CatalogProduct>> lookupBarcode(String code) async {
    if (code.isEmpty) {
      return const [];
    }
    try {
      final response = await rpcClient.call(
        'catalog_lookup_barcode',
        params: {'code': code},
      );
      final rows = _rowsFromResponse(response);
      final products = <String, CatalogProduct>{};
      for (final row in rows) {
        final product = CatalogProduct.fromRpcRow(row);
        products[product.id] = product;
      }
      return products.values.toList(growable: false);
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

  @override
  Future<CatalogSaveResult> create({
    required String productId,
    required CatalogProductInput input,
  }) async {
    try {
      final response = await rpcClient.call(
        'catalog_create_idempotent',
        params: {
          'product_id': productId,
          ..._inputParams(input),
        },
      );
      return CatalogSaveConfirmed(_singleMutationRow(response));
    } on CatalogRpcException catch (error) {
      if (error.code == '40001') {
        return CatalogSaveConflict(await _latestOrNull(productId));
      }
      return reconcileCreate(
        productId: productId,
        input: input,
      );
    } catch (_) {
      return reconcileCreate(
        productId: productId,
        input: input,
      );
    }
  }

  @override
  Future<CatalogSaveResult> update({
    required CatalogProduct original,
    required CatalogProductInput input,
  }) async {
    try {
      final response = await rpcClient.call(
        'catalog_update',
        params: {
          'product_id': original.id,
          'expected_revision': original.revision,
          ..._inputParams(input),
        },
      );
      return CatalogSaveConfirmed(_singleMutationRow(response));
    } on CatalogRpcException catch (error) {
      if (error.code == '40001') {
        return CatalogSaveConflict(await _latestOrNull(original.id));
      }
      if (error.code == 'P0002') {
        return const CatalogSaveMissing();
      }
      return reconcileUpdate(
        original: original,
        input: input,
      );
    } catch (_) {
      return reconcileUpdate(
        original: original,
        input: input,
      );
    }
  }

  @override
  Future<CatalogSaveResult> reconcileCreate({
    required String productId,
    required CatalogProductInput input,
  }) async {
    try {
      final product = await getById(productId);
      return input.matchesProduct(product)
          ? CatalogSaveConfirmed(product)
          : CatalogSaveConflict(product);
    } on CatalogNotFoundException {
      return const CatalogSaveRejected();
    } catch (_) {
      return const CatalogSaveUncertain();
    }
  }

  @override
  Future<CatalogSaveResult> reconcileUpdate({
    required CatalogProduct original,
    required CatalogProductInput input,
  }) async {
    try {
      final latest = await getById(original.id);

      if (latest.revision > original.revision &&
          input.matchesProduct(latest)) {
        return CatalogSaveConfirmed(latest);
      }

      if (latest.revision == original.revision &&
          CatalogProductInput.fromProduct(original).matchesProduct(latest)) {
        return const CatalogSaveRejected();
      }

      return CatalogSaveConflict(latest);
    } on CatalogNotFoundException {
      return const CatalogSaveMissing();
    } catch (_) {
      return const CatalogSaveUncertain();
    }
  }

  Map<String, dynamic> _inputParams(CatalogProductInput input) {
    return {
      'product_name_en': _rpcText(input.nameEn),
      'product_name_ar': _rpcText(input.nameAr),
      'product_composition': _rpcText(input.composition),
      'product_manufacturer': _rpcText(input.manufacturer),
      'product_strength': _rpcText(input.strength),
      'product_dosage_form': _rpcText(input.dosageForm),
      'product_package_description': _rpcText(input.packageDescription),
      'product_barcode': _rpcText(input.barcode),
      'product_barcode2': _rpcText(input.barcode2),
      'product_selling_amount': input.sellingAmount,
      'product_currency': input.currency,
      'product_notes': _rpcText(input.notes),
    };
  }

  String? _rpcText(String value) {
    return value.trim().isEmpty ? null : value;
  }

  CatalogProduct _singleMutationRow(dynamic response) {
    final rows = _rowsFromResponse(response);
    if (rows.length != 1) {
      throw const CatalogResponseException();
    }
    return CatalogProduct.fromRpcRow(rows.single);
  }

  Future<CatalogProduct?> _latestOrNull(String productId) async {
    try {
      return await getById(productId);
    } catch (_) {
      return null;
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
