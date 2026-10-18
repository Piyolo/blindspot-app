import 'package:blindspot_app/constants/api_paths.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/models/auth_result.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/repositories/network_retry.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/validation.dart';

/// Signup and login for the signed-out flow.
abstract class AuthRepository {
  const AuthRepository();

  Future<AuthResult> signup({
    required String name,
    required String email,
    required String password,
    required String contactNumber,
  });

  Future<AuthResult> login({required String email, required String password});
}

/// [AuthRepository] over the live API.
///
/// Every call retries once on a network-level failure (see
/// [withNetworkRetry]); HTTP errors surface as [ApiException] carrying the
/// server's `detail` message and its status code — the screens own the
/// user-facing copy. [onRetry] fires exactly once immediately before the
/// single retry attempt, so the provider layer can surface the
/// server-waking state during a Render cold start.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._client, {this.onRetry});

  final ApiClient _client;

  /// Invoked only when the first attempt failed with a network-level
  /// [ApiException] (`statusCode == null`) and one retry is about to run.
  final void Function()? onRetry;

  @override
  Future<AuthResult> signup({
    required String name,
    required String email,
    required String password,
    required String contactNumber,
  }) async {
    // Client-side guard: the screens validate the field before calling, so
    // this only fires on a programming error. It keeps a malformed contact
    // number from ever becoming a server 400 — and, because it carries a
    // status code, from being pointlessly retried.
    if (!isValidContactNumber(contactNumber)) {
      throw const ApiException('Invalid contact number', statusCode: 400);
    }
    return withNetworkRetry(() async {
      final json = await _client.post(
        ApiPaths.signup,
        body: <String, dynamic>{
          'name': name,
          'email': email,
          'password': password,
          // Normalized to the server's canonical form (+digits or digits),
          // mirroring `normalize_contact_number` in the backend schemas.
          'contact_number': normalizeContactNumber(contactNumber),
        },
      );
      return AuthResult.fromJson(json);
    }, onRetry: onRetry);
  }

  @override
  Future<AuthResult> login({required String email, required String password}) =>
      withNetworkRetry(() async {
        final json = await _client.post(
          ApiPaths.login,
          body: <String, dynamic>{'email': email, 'password': password},
        );
        return AuthResult.fromJson(json);
      }, onRetry: onRetry);
}

/// Test double for [AuthRepository] (widget/provider tests): canned success
/// by default, [error] to force failure. No HTTP, no artificial delays.
///
/// Captures the non-secret arguments a test may assert on; passwords are
/// deliberately never stored.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({AuthResult? result, this.error})
      : result = result ?? _cannedAuthResult;

  /// Success payload returned by every call (overridable per test).
  AuthResult result;

  /// When set, every call throws it (typically an [ApiException]).
  Object? error;

  int signupCalls = 0;
  int loginCalls = 0;

  String? lastName;
  String? lastEmail;
  String? lastContactNumber;

  @override
  Future<AuthResult> signup({
    required String name,
    required String email,
    required String password,
    required String contactNumber,
  }) async {
    signupCalls += 1;
    lastName = name;
    lastEmail = email;
    lastContactNumber = contactNumber;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result;
  }

  @override
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    loginCalls += 1;
    lastEmail = email;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result;
  }
}

final AuthResult _cannedAuthResult = AuthResult(
  accessToken: 'mock-access-token',
  user: User(
    id: 1,
    name: 'Mock User',
    email: 'mock@example.com',
    contactNumber: '09170000000',
    createdAt: DateTime.utc(2026, 1, 1),
  ),
);
