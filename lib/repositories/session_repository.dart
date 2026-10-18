import 'dart:convert';

import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/services/token_store.dart';

/// The signed-in session restored from local storage at launch.
class CachedSession {
  const CachedSession({required this.token, required this.user});

  final String token;
  final User user;
}

/// Offline-safe persistence of the auth token plus the cached user profile.
///
/// [load] never throws: corrupt or foreign stored JSON (or a failing
/// keychain read) deletes the bad user entry and reports signed-out,
/// so an airplane-mode relaunch lands on Welcome instead of crashing.
/// A missing/empty token also deletes an orphaned user entry, so the
/// cached profile never outlives the token on the device.
class SessionRepository {
  SessionRepository(SecureStore store)
      : _store = store,
        _tokens = TokenStore(store);

  /// Storage key for the cached user JSON.
  static const String userKey = 'blindspot_user';

  final SecureStore _store;
  final TokenStore _tokens;

  /// Restores the cached session, or null when there is none (signed out).
  Future<CachedSession?> load() async {
    try {
      final token = await _tokens.read();
      final userJson = await _store.read(userKey);
      if (token == null || token.isEmpty) {
        // No usable token: drop any orphaned user entry too, so the cached
        // profile (name/email/contact) never outlives the token on the
        // device — mirroring the corrupt-JSON path below.
        if (userJson != null && userJson.isNotEmpty) {
          await _store.delete(userKey);
        }
        return null;
      }
      if (userJson == null || userJson.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(userJson);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('stored user is not a JSON object');
      }
      return CachedSession(token: token, user: User.fromJson(decoded));
    } catch (_) {
      // Corrupt or foreign payload (or an unavailable store): drop the bad
      // entry so the next load starts clean, and report signed-out instead
      // of failing the relaunch.
      try {
        await _store.delete(userKey);
      } catch (_) {
        // Nothing more we can do; the next launch retries.
      }
      return null;
    }
  }

  /// Persists both halves of the session (token under `blindspot_token`,
  /// user JSON under `blindspot_user`).
  Future<void> save({required String token, required User user}) async {
    await _tokens.write(token);
    await _store.write(userKey, jsonEncode(user.toJson()));
  }

  /// Clears the cached session (logout / unauthorized).
  Future<void> clear() async {
    await _tokens.clear();
    await _store.delete(userKey);
  }
}
