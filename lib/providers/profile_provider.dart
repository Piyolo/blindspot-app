import 'package:flutter/foundation.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/providers/auth_provider.dart';
import 'package:blindspot_app/repositories/profile_repository.dart';

/// Owns the signed-in profile edits (contact number, name, password
/// change) — and nothing else. The session, token, and cached user belong
/// to [AuthProvider]: on success every edit that returns a user is merged
/// via [AuthProvider.replaceUser], and a 401 on any call is delegated to
/// [AuthProvider.handleUnauthorized], which clears the cached session.
///
/// `busy` guards re-entry exactly like `AuthProvider.busy` (a double
/// submit issues one request), and [lastError] only ever carries
/// copy-deck text.
class ProfileProvider extends ChangeNotifier {
  ProfileProvider({
    required ProfileRepository repository,
    required AuthProvider auth,
  }) : _repository = repository,
       _auth = auth;

  final ProfileRepository _repository;
  final AuthProvider _auth;

  bool _busy = false;
  String? _lastError;

  /// True while an edit request is in flight.
  bool get busy => _busy;

  /// The last edit failure as copy-deck text (never a raw server `detail`).
  String? get lastError => _lastError;

  /// Saves a new emergency contact number and refreshes the cached user.
  Future<bool> updateContact(String contactNumber) => _attempt(() async {
    final updated = await _repository.updateProfile(
      contactNumber: contactNumber,
    );
    await _auth.replaceUser(updated);
    return true;
  });

  /// Saves a new name and refreshes the cached user.
  Future<bool> changeName(String name) => _attempt(() async {
    final updated = await _repository.updateProfile(name: name);
    await _auth.replaceUser(updated);
    return true;
  });

  /// Changes the password. On success there is no user payload to merge,
  /// so [AuthProvider.replaceUser] is deliberately not called.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _attempt(() async {
    await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    return true;
  });

  Future<bool> _attempt(Future<bool> Function() body) async {
    if (_busy) {
      return false;
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      return await body();
    } on ApiException catch (error) {
      _handleApiError(error);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _handleApiError(ApiException error) {
    // A wrong current password is a rejected edit, not a dead session:
    // the server answers that specific 401 with its dedicated detail
    // (backend `CURRENT_PASSWORD_ERROR` == [Copy.wrongCurrentPassword]),
    // so the user stays signed in and sees the field-level copy.
    if (error.statusCode == 401 && error.message == Copy.wrongCurrentPassword) {
      _lastError = Copy.wrongCurrentPassword;
      return;
    }
    switch (error.statusCode) {
      case 401:
        // The session itself is no longer valid; AuthProvider owns the
        // sign-out (store + token cleared, signedOut). Task 12 routes and
        // shows the one-time notice off that status change.
        _auth.handleUnauthorized(401);
        return;
      case 429:
        _lastError = Copy.rateLimited;
        return;
      case null:
        // Network-level failure (already retried once by the repository):
        // profile edits require connectivity; the cached value is kept.
        _lastError = Copy.needInternet;
        return;
      default:
        // Includes 400 and the malformed-2xx ApiException (status 200).
        _lastError = Copy.genericError;
    }
  }
}
