import 'package:blindspot_app/constants/api_paths.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/repositories/network_retry.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/validation.dart';

/// Signed-in profile edits: partial user update and password change.
abstract class ProfileRepository {
  const ProfileRepository();

  /// Partially updates the signed-in user; a null/absent field is left
  /// unchanged by the server.
  Future<User> updateProfile({String? name, String? contactNumber});

  /// Changes the signed-in user's password; resolves when the server
  /// confirms (`{"ok": true}`).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

/// [ProfileRepository] over the live API.
///
/// Every call retries once on a network-level failure (see
/// [withNetworkRetry]); HTTP errors surface as [ApiException] carrying the
/// server's `detail` message and its status code. Passwords are passed
/// through to the request only — never logged or stored. [onRetry] fires
/// exactly once immediately before the single retry attempt.
class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._client, {this.onRetry});

  final ApiClient _client;

  /// Invoked only when the first attempt failed with a network-level
  /// [ApiException] (`statusCode == null`) and one retry is about to run.
  final void Function()? onRetry;

  @override
  Future<User> updateProfile({String? name, String? contactNumber}) async {
    // Same client-side guard as signup: a malformed contact number never
    // reaches the server (and, carrying a status code, is never retried).
    if (contactNumber != null && !isValidContactNumber(contactNumber)) {
      throw const ApiException('Invalid contact number', statusCode: 400);
    }
    // Send only what was provided: the server treats null/absent fields as
    // "leave unchanged", and explicit nulls could clear a stored value, so
    // they are never serialized here.
    final normalizedContact =
        contactNumber == null ? null : normalizeContactNumber(contactNumber);
    final body = <String, dynamic>{
      'name': ?name,
      'contact_number': ?normalizedContact,
    };
    return withNetworkRetry(() async {
      final json = await _client.put(ApiPaths.me, body: body);
      return User.fromJson(json['user'] as Map<String, dynamic>);
    }, onRetry: onRetry);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      withNetworkRetry(() async {
        await _client.put(
          ApiPaths.mePassword,
          body: <String, dynamic>{
            'current_password': currentPassword,
            'new_password': newPassword,
          },
        );
      }, onRetry: onRetry);
}

/// Test double for [ProfileRepository] (widget/provider tests): canned
/// success by default, [error] to force failure. No HTTP, no delays.
///
/// Passwords are deliberately never stored.
class MockProfileRepository implements ProfileRepository {
  MockProfileRepository({User? user, this.error}) : user = user ?? _cannedUser;

  /// User returned by a successful [updateProfile] (overridable per test).
  User user;

  /// When set, every call throws it (typically an [ApiException]).
  Object? error;

  int updateProfileCalls = 0;
  int changePasswordCalls = 0;

  String? lastName;
  String? lastContactNumber;

  @override
  Future<User> updateProfile({String? name, String? contactNumber}) async {
    updateProfileCalls += 1;
    lastName = name;
    lastContactNumber = contactNumber;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return user;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls += 1;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}

final User _cannedUser = User(
  id: 1,
  name: 'Mock User',
  email: 'mock@example.com',
  contactNumber: '09170000000',
  createdAt: DateTime.utc(2026, 1, 1),
);
