import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/auth/data/secure_supabase_local_storage.dart';
import 'package:sherko_pharma/features/navigation/application/app_navigation_controller.dart';
import 'package:sherko_pharma/features/order/domain/order_model.dart';
import 'package:sherko_pharma/features/session/data/app_session_store.dart';

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
  test('secure session store round-trips exact order snapshot per account', () async {
    final secure = _MemorySecureStore();
    final store = SecureAppSessionStore(
      store: secure,
      keyPrefix: 'test:session:v1',
    );
    const snapshot = AppSessionSnapshot(
      ownerId: 'owner-a',
      destination: AppDestination.order,
      order: OrderState(
        lines: [
          OrderLine(
            productId: 'product-a',
            displayName: 'Product A',
            quantity: 3,
            unitAmount: 1000,
            currency: 'SYP',
            productRevision: 7,
          ),
          OrderLine(
            productId: 'product-b',
            displayName: 'Product B',
            quantity: 2,
            unitAmount: 5,
            currency: 'USD',
            productRevision: 2,
          ),
        ],
      ),
    );

    await store.save(snapshot);

    final restored = await store.load(ownerId: 'owner-a');
    final otherOwner = await store.load(ownerId: 'owner-b');

    expect(restored, isNotNull);
    expect(restored!.ownerId, 'owner-a');
    expect(restored.destination, AppDestination.order);
    expect(restored.order.lines, hasLength(2));
    expect(restored.order.lines.first.quantity, 3);
    expect(restored.order.lines.first.unitAmount, 1000);
    expect(restored.order.lines.first.productRevision, 7);
    expect(restored.order.totalSyp, 3000);
    expect(restored.order.totalUsd, 10);
    expect(otherOwner, isNull);
  });

  test('malformed or unsupported session fails closed and is removed', () async {
    final secure = _MemorySecureStore();
    final store = SecureAppSessionStore(
      store: secure,
      keyPrefix: 'test:session:v1',
    );
    secure.values['test:session:v1:owner-a'] = '{"version":999}';

    await expectLater(
      store.load(ownerId: 'owner-a'),
      throwsA(isA<AppSessionStorageException>()),
    );

    expect(secure.values, isEmpty);
  });

  test('invalid persisted line is rejected before restoration', () {
    expect(
      () => AppSessionSnapshot.fromJson({
        'version': 1,
        'owner_id': 'owner-a',
        'destination': 'order',
        'order_lines': [
          {
            'product_id': 'product-a',
            'display_name': 'Product A',
            'quantity': 0,
            'unit_amount': 1000,
            'currency': 'SYP',
            'product_revision': 1,
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => AppSessionSnapshot.fromJson({
        'version': 1,
        'owner_id': 'owner-a',
        'destination': 'order',
        'order_lines': [
          {
            'product_id': 'product-a',
            'display_name': 'Product A',
            'quantity': 1,
            'unit_amount': 1000,
            'currency': 'EUR',
            'product_revision': 1,
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('duplicate product identities and overflow are rejected', () {
    expect(
      () => AppSessionSnapshot.fromJson({
        'version': 1,
        'owner_id': 'owner-a',
        'destination': 'order',
        'order_lines': [
          {
            'product_id': 'duplicate',
            'display_name': 'A',
            'quantity': 1,
            'unit_amount': 1,
            'currency': 'SYP',
            'product_revision': 1,
          },
          {
            'product_id': 'duplicate',
            'display_name': 'B',
            'quantity': 1,
            'unit_amount': 2,
            'currency': 'SYP',
            'product_revision': 1,
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => AppSessionSnapshot.fromJson({
        'version': 1,
        'owner_id': 'owner-a',
        'destination': 'order',
        'order_lines': [
          {
            'product_id': 'huge',
            'display_name': 'Huge',
            'quantity': 2,
            'unit_amount': maxOrderAmount,
            'currency': 'SYP',
            'product_revision': 1,
          },
        ],
      }),
      throwsA(isA<OrderAmountOverflow>()),
    );
  });
}
