import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Abstraction over platform secure storage so tests never touch the real
/// keychain/keystore.
abstract class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production store backed by `FlutterSecureStorage` (Keychain on iOS,
/// Keystore on Android).
class FlutterSecureStore implements SecureStore {
  FlutterSecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Test double: a plain in-memory map, headless — no platform channels.
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _entries = <String, String>{};

  @override
  Future<String?> read(String key) async => _entries[key];

  @override
  Future<void> write(String key, String value) async {
    _entries[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _entries.remove(key);
  }
}
