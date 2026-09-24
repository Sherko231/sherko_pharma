import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/catalog/data/catalog_repository.dart';
import 'package:sherko_pharma/features/catalog/data/supabase_catalog_repository.dart';

class FakeRpcClient implements CatalogRpcClient {
  dynamic response;
  Object? error;
  String? functionName;
  Map<String, dynamic>? params;

  @override
  Future<dynamic> call(
    String functionName, {
    required Map<String, dynamic> params,
  }) async {
    this.functionName = functionName;
    this.params = Map<String, dynamic>.from(params);
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
}
