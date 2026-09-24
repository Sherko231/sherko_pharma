import 'package:flutter_test/flutter_test.dart';
import 'package:sherko_pharma/features/auth/data/secure_supabase_local_storage.dart';

class FakeSecureKeyValueStore implements SecureKeyValueStore {
  String? value;
  bool throwOnRead = false;
  bool throwOnDelete = false;
  int deleteCalls = 0;

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) {
      throw StateError('unreadable');
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    this.value = value;
  }

  @override
  Future<void> delete(String key) async {
    deleteCalls += 1;
    if (throwOnDelete) {
      throw StateError('undeletable');
    }
    value = null;
  }
}

void main() {
  test('persists and removes only the Supabase session string', () async {
    final store = FakeSecureKeyValueStore();
    final storage = SecureSupabaseLocalStorage(
      store: store,
      sessionKey: 'test-session-key',
    );

    await storage.persistSession('opaque-session-data');

    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), 'opaque-session-data');

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('unreadable secure session fails closed and requests cleanup', () async {
    final store = FakeSecureKeyValueStore()
      ..value = 'unreadable-session'
      ..throwOnRead = true;
    final storage = SecureSupabaseLocalStorage(
      store: store,
      sessionKey: 'test-session-key',
    );

    expect(await storage.accessToken(), isNull);
    expect(store.deleteCalls, 1);
  });

  test('read failure remains signed out even if cleanup also fails', () async {
    final store = FakeSecureKeyValueStore()
      ..value = 'unreadable-session'
      ..throwOnRead = true
      ..throwOnDelete = true;
    final storage = SecureSupabaseLocalStorage(
      store: store,
      sessionKey: 'test-session-key',
    );

    expect(await storage.hasAccessToken(), isFalse);
    expect(store.deleteCalls, 1);
  });
}
