import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/models/auth_result.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/services/api_client.dart';

/// Lifecycle of the signed-in session, as observed by the routing layer.
enum AuthStatus {
  /// Not yet determined — [AuthProvider.restoreSession] has not run.
  unknown,

  /// No usable cached session (or it was cleared).
  signedOut,

  /// A cached/just-created session is active and `client.authToken` set.
  signedIn,
}

/// Owns the session: login, signup, logout, cached-session restore, the
/// auth token on [ApiClient], and the cached [User].
///
/// Profile edits live in `ProfileProvider`, which calls back into
/// [replaceUser] / [handleUnauthorized] rather than duplicating any of
/// this. The provider performs no I/O of its own beyond the injected
/// repositories, and — being offline-safe by design — `restoreSession()`
/// never throws: an unreadable/corrupt store signs the user out instead
/// of failing the relaunch.
///
/// Wiring the cold-server signal (Task 9's waking banner): construct the
/// repository with this provider's [notifyRetrying] as its `onRetry`
/// hook, e.g.
/// ```dart
/// late final AuthProvider auth;
/// final repo = ApiAuthRepository(client, onRetry: auth.notifyRetrying);
/// auth = AuthProvider(auth: repo, session: session, client: client);
/// ```
/// The retry itself works regardless — the hook only surfaces the state.
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AuthRepository auth,
    required SessionRepository session,
    required ApiClient client,
  }) : _auth = auth,
       _session = session,
       _client = client;

  final AuthRepository _auth;
  final SessionRepository _session;
  final ApiClient _client;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _lastError;
  bool _busy = false;
  bool _retryingNetwork = false;

  AuthStatus get status => _status;

  User? get user => _user;

  /// The last auth failure as copy-deck text (never a raw server `detail`).
  String? get lastError => _lastError;

  /// Clears [lastError] without touching any other state, so a failure
  /// from one screen never renders on the next one (a signup 409 must not
  /// appear as a live-region error on a freshly opened Login). Screens
  /// call this from `initState`. Notifies only when there was an error to
  /// clear, so a clean provider stays silent.
  ///
  /// The notification rides a microtask: `initState` runs inside the
  /// framework's build phase, where a synchronous `notifyListeners()`
  /// would trip "setState() or markNeedsBuild() called during build" on
  /// the provider scope (and on any previous screen still mounted). The
  /// microtask runs as soon as that synchronous work — including the
  /// build — has finished, while [lastError] itself is already null from
  /// the moment this method returns.
  void clearError() {
    if (_lastError == null) {
      return;
    }
    _lastError = null;
    scheduleMicrotask(() {
      // The microtask can outlive the provider (a screen disposing in the
      // same turn), and notifying a disposed ChangeNotifier throws in debug.
      if (_disposed) {
        return;
      }
      notifyListeners();
    });
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// True while a login/signup request is in flight; screens disable
  /// submit on it and it guards re-entry (a double submit issues exactly
  /// one request).
  bool get busy => _busy;

  /// True only while the repository's single network retry runs (see
  /// [notifyRetrying]); always false once the call has settled.
  bool get retryingNetwork => _retryingNetwork;

  /// Hook for the repository's `onRetry` callback
  /// (`ApiAuthRepository(client, onRetry: provider.notifyRetrying)`, or a
  /// test fake mirroring that contract): marks the single retry attempt as
  /// in flight so a screen can show [Copy.serverWaking], e.g. during a
  /// cold Render wake-up. Reset automatically when the in-flight
  /// login/signup settles, success or failure.
  ///
  /// Ignored while no auth call is in flight (`busy` false), so a stray
  /// invocation — e.g. another repository wired to this hook — can never
  /// strand the waking banner outside an auth request.
  void notifyRetrying() {
    if (!_busy) {
      return;
    }
    _retryingNetwork = true;
    notifyListeners();
  }

  /// Restores the cached session at launch. No cache → [AuthStatus.signedOut]
  /// with no network call; a corrupt or unreadable store signs out too —
  /// this method never throws, so an airplane-mode relaunch lands on
  /// Welcome instead of crashing.
  ///
  /// The no-cache path is deterministic about in-memory state: any token
  /// left over from an earlier call in the same process is cleared, so
  /// `signedOut` always means "no token installed".
  Future<void> restoreSession() async {
    CachedSession? cached;
    try {
      cached = await _session.load();
    } catch (_) {
      // Unreadable store: treat as signed out rather than fail the launch.
      cached = null;
    }
    if (cached == null) {
      _client.authToken = null;
      _user = null;
      _status = AuthStatus.signedOut;
    } else {
      _client.authToken = cached.token;
      _user = cached.user;
      _status = AuthStatus.signedIn;
    }
    notifyListeners();
  }

  /// Signs in; on success goes signed in and persists token + user
  /// best-effort (a failing store never fails a successful login).
  /// On failure nothing is persisted, the status is untouched, and
  /// [lastError] carries copy-deck text mapped from the status code.
  Future<bool> login({required String email, required String password}) =>
      _authenticate(
        () => _auth.login(email: email, password: password),
        isSignup: false,
      );

  /// Like [login] for the signup endpoint; a 409 maps to
  /// [Copy.emailExists].
  Future<bool> signup({
    required String name,
    required String email,
    required String password,
    required String contactNumber,
  }) => _authenticate(
    () => _auth.signup(
      name: name,
      email: email,
      password: password,
      contactNumber: contactNumber,
    ),
    isSignup: true,
  );

  Future<bool> _authenticate(
    Future<AuthResult> Function() call, {
    required bool isSignup,
  }) async {
    if (_busy) {
      return false;
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final result = await call();
      // The server accepted the credentials: sign in in memory first —
      // authoritative and independent of storage — then persist
      // best-effort. A failed attempt still leaves storage untouched (it
      // never reaches this point), and a failed *write* must not undo or
      // sour a login that genuinely worked: the session just won't
      // survive a restart.
      _client.authToken = result.accessToken;
      _user = result.user;
      _status = AuthStatus.signedIn;
      try {
        await _session.save(token: result.accessToken, user: result.user);
      } catch (_) {
        // Best-effort persistence; nothing further to do.
      }
      return true;
    } on ApiException catch (error) {
      _lastError = _errorFor(error, isSignup: isSignup);
      return false;
    } finally {
      // Both flags describe only the in-flight call, whatever its outcome.
      _busy = false;
      _retryingNetwork = false;
      notifyListeners();
    }
  }

  /// Maps an [ApiException] to copy-deck text. A raw server `detail` is
  /// never surfaced — screens only ever render [Copy] constants.
  static String _errorFor(ApiException error, {required bool isSignup}) {
    switch (error.statusCode) {
      case 401:
        // Bad credentials on login; on signup a 401 is unexpected → generic.
        return isSignup ? Copy.genericError : Copy.loginError;
      case 409:
        return isSignup ? Copy.emailExists : Copy.genericError;
      case 429:
        return Copy.rateLimited;
      case null:
        // Network-level failure (already retried once by the repository).
        return Copy.offline;
      default:
        // Includes 400 and the malformed-2xx ApiException (status 200).
        return Copy.genericError;
    }
  }

  /// Clears the cached session and the client token, going signed out.
  ///
  /// In-memory state changes first; the storage clear is best-effort and
  /// never throws — a failing store must not trap the user signed in.
  Future<void> signOut() async {
    _client.authToken = null;
    _user = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
    try {
      await _session.clear();
    } catch (_) {
      // Best-effort: the app is signed out regardless; a stale cache
      // entry (if any survived) is retried on the next clear/restore.
    }
  }

  /// Applies an updated user (e.g. after a profile edit) without touching
  /// the token: updates the in-memory user and notifies listeners, then
  /// persists the new user into the session store (keeping the existing
  /// token) best-effort — a failing store never fails a successful edit.
  Future<void> replaceUser(User user) async {
    final token = _client.authToken;
    _user = user;
    notifyListeners();
    if (token != null) {
      try {
        await _session.save(token: token, user: user);
      } catch (_) {
        // Best-effort: the in-memory session is already updated.
      }
    }
  }

  /// Handles a server-side rejection of the current session: only a 401
  /// clears the store + client token and signs out (returning true);
  /// anything else is left to the caller.
  bool handleUnauthorized(int? statusCode) {
    if (statusCode != 401) {
      return false;
    }
    // Synchronous by contract; storage settles in the background.
    unawaited(_session.clear());
    _client.authToken = null;
    _user = null;
    _status = AuthStatus.signedOut;
    notifyListeners();
    return true;
  }
}
