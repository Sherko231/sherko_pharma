import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/auth/data/secure_supabase_local_storage.dart';
import 'package:sherko_pharma/features/catalog/data/catalog_draft_store.dart';
import 'package:sherko_pharma/features/catalog/domain/catalog_product_input.dart';

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('secure draft store round-trips partial create input per account', () async {
    final secure = _MemorySecureStore();
    final store = SecureCatalogDraftStore(
      store: secure,
      keyPrefix: 'test:draft:v1',
    );
    const draft = CatalogProductDraft(
      ownerId: 'owner-a',
      scopeKey: 'create',
      productId: '11111111-1111-4111-8111-111111111111',
      formData: CatalogProductFormData(
        nameEn: '',
        nameAr: 'مسودة',
        composition: '',
        manufacturer: '',
        strength: '',
        dosageForm: '',
        packageDescription: '',
        barcode: '000123',
        barcode2: '',
        sellingAmountText: '',
        currency: 'SYP',
        notes: 'unfinished',
      ),
      baseProduct: null,
      uncertain: false,
    );

    await store.save(draft);

    final restored = await store.load(
      ownerId: 'owner-a',
      scopeKey: 'create',
    );
    final otherOwner = await store.load(
      ownerId: 'owner-b',
      scopeKey: 'create',
    );

    expect(restored, isNotNull);
    expect(restored!.productId, draft.productId);
    expect(restored.formData.nameAr, 'مسودة');
    expect(restored.formData.barcode, '000123');
    expect(otherOwner, isNull);
  });

  test('malformed draft fails closed and is removed', () async {
    final secure = _MemorySecureStore();
    final store = SecureCatalogDraftStore(
      store: secure,
      keyPrefix: 'test:draft:v1',
    );
    secure.values['test:draft:v1:owner-a:create'] = '{"version":999}';

    await expectLater(
      store.load(ownerId: 'owner-a', scopeKey: 'create'),
      throwsA(isA<CatalogDraftStorageException>()),
    );

    expect(secure.values, isEmpty);
  });
}
