import 'package:blindspot_app/services/secure_store.dart';

/// Persists the auth JWT in a [SecureStore].
class TokenStore {
  TokenStore(this._store);

  /// Storage key for the auth token.
  static const String storageKey = 'blindspot_token';

  final SecureStore _store;

  Future<String?> read() => _store.read(storageKey);

  Future<void> write(String token) => _store.write(storageKey, token);

  Future<void> clear() => _store.delete(storageKey);
}
