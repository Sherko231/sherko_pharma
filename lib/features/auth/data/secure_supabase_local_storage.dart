import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) {
    return storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    return storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) {
    return storage.delete(key: key);
  }
}

class SecureSupabaseLocalStorage extends LocalStorage {
  SecureSupabaseLocalStorage({
    required this.store,
    required this.sessionKey,
  });

  final SecureKeyValueStore store;
  final String sessionKey;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() {
    return _readFailClosed();
  }

  @override
  Future<bool> hasAccessToken() async {
    return await _readFailClosed() != null;
  }

  @override
  Future<void> persistSession(String persistSessionString) {
    return store.write(sessionKey, persistSessionString);
  }

  @override
  Future<void> removePersistedSession() {
    return store.delete(sessionKey);
  }

  Future<String?> _readFailClosed() async {
    try {
      return await store.read(sessionKey);
    } catch (_) {
      try {
        await store.delete(sessionKey);
      } catch (_) {
        // Fail closed even when cleanup cannot be completed immediately.
      }
      return null;
    }
  }
}
