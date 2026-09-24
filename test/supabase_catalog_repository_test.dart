import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';
import 'package:sherko_pharma/features/catalog/data/supabase_catalog_repository.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product_input.dart';

class FakeRpcClient implements CatalogRpcClient {
  dynamic response;
  Object? error;
  Future<dynamic> Function(String functionName, Map<String, dynamic> params)?
      handler;
  String? functionName;
  Map<String, dynamic>? params;
  final calls = <String>[];

  @override
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    this.functionName = functionName;
    this.params = Map<String, dynamic>.from(params);
    calls.add(functionName);
    final customHandler = handler;
    if (customHandler != null) {
      return customHandler(functionName, params);
    }
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return response;
  }
}

Map<String, dynamic> rpcRow({
  String id = '00000000-0000-0000-0000-000000000001',
}) {
  return {
    'id': id,
    'name_en': 'Aspirin',
    'name_ar': 'أسبرين',
    'composition': 'Acetylsalicylic acid',
    'manufacturer': 'Test Pharma',
    'strength': '100 mg',
    'dosage_form': 'Tablet',
    'package_description': '20 tablets',
    'barcode': '0012345',
    'barcode2': 'ALT-001',
    'selling_amount': 15000,
    'currency': 'SYP',
    'notes': null,
    'revision': 3,
    'updated_at': '2026-09-24T12:00:00Z',
  };
}

void main() {
  test('search maps exact RPC fields and clamps client limit to 25', () async {
    final rpc = FakeRpcClient()
      ..response = [rpcRow()];
    final repository = SupabaseCatalogRepository(rpc);

    final products = await repository.search(
      '  أسبرين  ',
      limit: 999,
    );

    expect(rpc.functionName, 'catalog_search');
    expect(rpc.params, {
      'search_text': '  أسبرين  ',
      'requested_limit': 25,
    });
    expect(products, hasLength(1));
    expect(products.single.nameAr, 'أسبرين');
    expect(products.single.barcode, '0012345');
    expect(products.single.sellingAmount, 15000);
    expect(products.single.currency, 'SYP');
    expect(products.single.revision, 3);
  });

  test('detail maps exactly one catalog_get row', () async {
    final rpc = FakeRpcClient()
      ..response = [rpcRow(id: 'product-id')];
    final repository = SupabaseCatalogRepository(rpc);

    final product = await repository.getById('product-id');

    expect(rpc.functionName, 'catalog_get');
    expect(rpc.params, {'product_id': 'product-id'});
    expect(product.id, 'product-id');
  });

  test('detail distinguishes a missing product from malformed response', () async {
    final rpc = FakeRpcClient()..response = <dynamic>[];
    final repository = SupabaseCatalogRepository(rpc);

    await expectLater(
      repository.getById('missing'),
      throwsA(isA<CatalogNotFoundException>()),
    );

    rpc.response = {'not': 'a list'};
    await expectLater(
      repository.getById('broken'),
      throwsA(isA<CatalogResponseException>()),
    );
  });

  test('malformed product fields become a response error', () async {
    final row = rpcRow()..['selling_amount'] = '15000';
    final rpc = FakeRpcClient()..response = [row];
    final repository = SupabaseCatalogRepository(rpc);

    await expectLater(
      repository.search('Aspirin'),
      throwsA(isA<CatalogResponseException>()),
    );
  });

  test('transport or server failures are normalized', () async {
    final rpc = FakeRpcClient()..error = StateError('network');
    final repository = SupabaseCatalogRepository(rpc);

    await expectLater(
      repository.search('Aspirin'),
      throwsA(isA<CatalogRepositoryException>()),
    );
  });

  group('catalog mutations', () {
    const productId = '55555555-5555-4555-8555-555555555555';
    const input = CatalogProductInput(
      nameEn: 'Created',
      nameAr: 'منشأ',
      composition: 'ingredient',
      manufacturer: 'Maker',
      strength: '10 mg',
      dosageForm: 'tablet',
      packageDescription: 'box',
      barcode: '0000123',
      barcode2: 'ALT-X',
      sellingAmount: 75,
      currency: 'USD',
      notes: 'note',
    );

    test('create uses idempotent RPC with exact canonical input', () async {
      final rpc = FakeRpcClient()
        ..response = [
          {
            ...rpcRow(id: productId),
            'name_en': 'Created',
            'name_ar': 'منشأ',
            'composition': 'ingredient',
            'manufacturer': 'Maker',
            'strength': '10 mg',
            'dosage_form': 'tablet',
            'package_description': 'box',
            'barcode': '0000123',
            'barcode2': 'ALT-X',
            'selling_amount': 75,
            'currency': 'USD',
            'notes': 'note',
          },
        ];
      final repository = SupabaseCatalogRepository(rpc);

      final result = await repository.create(
        productId: productId,
        input: input,
      );

      expect(result, isA<CatalogSaveConfirmed>());
      expect(rpc.functionName, 'catalog_create_idempotent');
      expect(rpc.params, {
        'product_id': productId,
        'product_name_en': 'Created',
        'product_name_ar': 'منشأ',
        'product_composition': 'ingredient',
        'product_manufacturer': 'Maker',
        'product_strength': '10 mg',
        'product_dosage_form': 'tablet',
        'product_package_description': 'box',
        'product_barcode': '0000123',
        'product_barcode2': 'ALT-X',
        'product_selling_amount': 75,
        'product_currency': 'USD',
        'product_notes': 'note',
      });
    });

    test('update sends expected revision and approved fields only', () async {
      final original = CatalogProduct.fromRpcRow(rpcRow(id: productId));
      final rpc = FakeRpcClient()
        ..response = [
          {
            ...rpcRow(id: productId),
            'name_en': 'Created',
            'name_ar': 'منشأ',
            'composition': 'ingredient',
            'manufacturer': 'Maker',
            'strength': '10 mg',
            'dosage_form': 'tablet',
            'package_description': 'box',
            'barcode': '0000123',
            'barcode2': 'ALT-X',
            'selling_amount': 75,
            'currency': 'USD',
            'notes': 'note',
            'revision': original.revision + 1,
          },
        ];
      final repository = SupabaseCatalogRepository(rpc);

      final result = await repository.update(
        original: original,
        input: input,
      );

      expect(result, isA<CatalogSaveConfirmed>());
      expect(rpc.functionName, 'catalog_update');
      expect(rpc.params?['product_id'], productId);
      expect(rpc.params?['expected_revision'], original.revision);
      expect(rpc.params?.containsKey('source_payload'), isFalse);
      expect(rpc.params?.containsKey('source_purchase_amount'), isFalse);
    });

    test('stale update maps database code to explicit conflict', () async {
      final original = CatalogProduct.fromRpcRow(rpcRow(id: productId));
      final latest = {
        ...rpcRow(id: productId),
        'name_en': 'Server newer',
        'revision': original.revision + 1,
      };
      final rpc = FakeRpcClient()
        ..handler = (functionName, params) async {
          if (functionName == 'catalog_update') {
            throw const CatalogRpcException(code: '40001');
          }
          if (functionName == 'catalog_get') {
            return [latest];
          }
          throw StateError('unexpected RPC');
        };
      final repository = SupabaseCatalogRepository(rpc);

      final result = await repository.update(
        original: original,
        input: input,
      );

      expect(result, isA<CatalogSaveConflict>());
      expect((result as CatalogSaveConflict).latest?.nameEn, 'Server newer');
    });

    test('lost create response reconciles matching row as confirmed', () async {
      final rpc = FakeRpcClient()
        ..handler = (functionName, params) async {
          if (functionName == 'catalog_create_idempotent') {
            throw const CatalogRpcException();
          }
          if (functionName == 'catalog_get') {
            return [
              {
                ...rpcRow(id: productId),
                'name_en': 'Created',
                'name_ar': 'منشأ',
                'composition': 'ingredient',
                'manufacturer': 'Maker',
                'strength': '10 mg',
                'dosage_form': 'tablet',
                'package_description': 'box',
                'barcode': '0000123',
                'barcode2': 'ALT-X',
                'selling_amount': 75,
                'currency': 'USD',
                'notes': 'note',
              },
            ];
          }
          throw StateError('unexpected RPC');
        };
      final repository = SupabaseCatalogRepository(rpc);

      final result = await repository.create(
        productId: productId,
        input: input,
      );

      expect(result, isA<CatalogSaveConfirmed>());
      expect(rpc.calls, ['catalog_create_idempotent', 'catalog_get']);
    });

    test('lost create response with definite not-found is safe rejection', () async {
      final rpc = FakeRpcClient()
        ..handler = (functionName, params) async {
          if (functionName == 'catalog_create_idempotent') {
            throw const CatalogRpcException();
          }
          if (functionName == 'catalog_get') {
            return <dynamic>[];
          }
          throw StateError('unexpected RPC');
        };
      final repository = SupabaseCatalogRepository(rpc);

      final result = await repository.create(
        productId: productId,
        input: input,
      );

      expect(result, isA<CatalogSaveRejected>());
    });

    test('unreadable create outcome stays uncertain and does not retry write', () async {
      final rpc = FakeRpcClient()
        ..handler = (functionName, params) async {
          throw const CatalogRpcException();
        };
      final repository = SupabaseCatalogRepository(rpc);

      final result = await repository.create(
        productId: productId,
        input: input,
      );

      expect(result, isA<CatalogSaveUncertain>());
      expect(
        rpc.calls.where((name) => name == 'catalog_create_idempotent'),
        hasLength(1),
      );
    });

    test('lost update response reconciles committed values as confirmed', () async {
      final original = CatalogProduct.fromRpcRow(rpcRow(id: productId));
      final rpc = FakeRpcClient()
        ..handler = (functionName, params) async {
          if (functionName == 'catalog_update') {
            throw const CatalogRpcException();
          }
          if (functionName == 'catalog_get') {
            return [
              {
                ...rpcRow(id: productId),
                'name_en': 'Created',
                'name_ar': 'منشأ',
                'composition': 'ingredient',
                'manufacturer': 'Maker',
                'strength': '10 mg',
                'dosage_form': 'tablet',
                'package_description': 'box',
                'barcode': '0000123',
                'barcode2': 'ALT-X',
                'selling_amount': 75,
                'currency': 'USD',
                'notes': 'note',
                'revision': original.revision + 1,
              },
            ];
          }
          throw StateError('unexpected RPC');
        };
      final repository = SupabaseCatalogRepository(rpc);

      final result = await repository.update(
        original: original,
        input: input,
      );

      expect(result, isA<CatalogSaveConfirmed>());
    });

    test('lost update response with unchanged row is safe rejection', () async {
      final original = CatalogProduct.fromRpcRow(rpcRow(id: productId));
      final rpc = FakeRpcClient()
        ..handler = (functionName, params) async {
          if (functionName == 'catalog_update') {
            throw const CatalogRpcException();
          }
          if (functionName == 'catalog_get') {
            return [rpcRow(id: productId)];
          }
          throw StateError('unexpected RPC');
        };
      final repository = SupabaseCatalogRepository(rpc);

      final result = await repository.update(
        original: original,
        input: input,
      );

      expect(result, isA<CatalogSaveRejected>());
    });
  });

}
