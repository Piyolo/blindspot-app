import 'package:flutter_test/flutter_test.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/models/auth_result.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/providers/auth_provider.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/services/token_store.dart';

/// [AuthRepository] double mirroring `ApiAuthRepository`'s retry contract:
/// one provider-visible call runs up to two attempts; while
/// [networkFailures] remain, each attempt fails with a network-level
/// [ApiException] (`statusCode == null`), firing [onRetry] and then
/// [onRetryAttempt] before the single retry runs — the provider can
/// therefore be wired exactly like production
/// (`ApiAuthRepository(client, onRetry: provider.notifyRetrying)`) and a
/// test can probe `retryingNetwork` mid-retry. [apiError] forces an
/// HTTP-level failure on every call.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    AuthResult? result,
    this.apiError,
    this.networkFailures = 0,
    this.onRetry,
    this.onRetryAttempt,
  }) : result = result ?? _cannedAuthResult;

  AuthResult result;
  ApiException? apiError;
  int networkFailures;
  void Function()? onRetry;
  void Function()? onRetryAttempt;

  int loginCalls = 0;
  int signupCalls = 0;

  /// Total attempts across all calls (a retried call counts two).
  int attempts = 0;

  @override
  Future<AuthResult> signup({
    required String name,
    required String email,
    required String password,
    required String contactNumber,
  }) {
    signupCalls += 1;
    return _call();
  }

  @override
  Future<AuthResult> login({required String email, required String password}) {
    loginCalls += 1;
    return _call();
  }

  Future<AuthResult> _call() async {
    final failure = apiError;
    if (failure != null) {
      attempts += 1;
      throw failure;
    }
    for (var attempt = 1; ; attempt++) {
      attempts += 1;
      if (networkFailures <= 0) {
        return result;
      }
      networkFailures -= 1;
      if (attempt >= 2) {
        // The single retry also failed: give up like withNetworkRetry.
        throw const ApiException('Network error');
      }
      onRetry?.call();
      onRetryAttempt?.call();
    }
  }
}

/// [SessionRepository] whose store read always fails, to prove
/// `restoreSession()` never throws.
class ThrowingSessionRepository extends SessionRepository {
  ThrowingSessionRepository() : super(InMemorySecureStore());

  @override
  Future<CachedSession?> load() => throw Exception('store unavailable');
}

/// [SecureStore] where every operation fails, to prove a dead store never
/// traps the user signed in (or fails a login the server accepted).
class ThrowingSecureStore implements SecureStore {
  @override
  Future<String?> read(String key) => throw Exception('store down');

  @override
  Future<void> write(String key, String value) => throw Exception('store down');

  @override
  Future<void> delete(String key) => throw Exception('store down');
}

final AuthResult _cannedAuthResult = AuthResult(
  accessToken: 'tok-abc',
  user: User(
    id: 7,
    name: 'Ana Cruz',
    email: 'ana@example.com',
    contactNumber: '09171234567',
    createdAt: DateTime.utc(2026, 10, 18, 9, 30),
  ),
);

void main() {
  User buildUser({
    String name = 'Ana Cruz',
    String contactNumber = '09171234567',
  }) => User(
    id: 7,
    name: name,
    email: 'ana@example.com',
    contactNumber: contactNumber,
    createdAt: DateTime.utc(2026, 10, 18, 9, 30),
  );

  late InMemorySecureStore store;
  late SessionRepository session;
  late ApiClient client;
  late MockAuthRepository repo;

  AuthProvider build({AuthRepository? auth, SessionRepository? sessionRepo}) =>
      AuthProvider(
        auth: auth ?? repo,
        session: sessionRepo ?? session,
        client: client,
      );

  /// Signs in via a cached session, like a real relaunch would.
  Future<AuthProvider> signedInProvider() async {
    await session.save(token: 'tok-123', user: buildUser());
    final provider = build();
    await provider.restoreSession();
    return provider;
  }

  setUp(() {
    store = InMemorySecureStore();
    session = SessionRepository(store);
    client = ApiClient(baseUrl: 'https://example.test');
    repo = MockAuthRepository();
  });

  test(
    'restoreSession with cached session -> signedIn and client token set',
    () async {
      await session.save(token: 'tok-123', user: buildUser());
      final provider = build();

      await provider.restoreSession();

      expect(provider.status, AuthStatus.signedIn);
      expect(provider.user?.name, 'Ana Cruz');
      expect(provider.user?.contactNumber, '09171234567');
      expect(client.authToken, 'tok-123');
      expect(repo.loginCalls + repo.signupCalls, 0);
    },
  );

  test('restoreSession without cache -> signedOut, no network call', () async {
    // A stale in-memory token from an earlier call in the same process
    // must not survive a restore that finds no cache (F1).
    client.authToken = 'stale-token';
    final provider = build();
    expect(provider.status, AuthStatus.unknown);

    await provider.restoreSession();

    expect(provider.status, AuthStatus.signedOut);
    expect(provider.user, isNull);
    expect(client.authToken, isNull);
    expect(repo.loginCalls + repo.signupCalls, 0);
  });

  test('restoreSession with a corrupt cached entry -> signedOut', () async {
    client.authToken = 'stale-token';
    await store.write(TokenStore.storageKey, 'tok-123');
    await store.write(SessionRepository.userKey, 'not json {{{');
    final provider = build();

    await provider.restoreSession();

    expect(provider.status, AuthStatus.signedOut);
    expect(provider.user, isNull);
    expect(client.authToken, isNull);
    // The bad entry is dropped so the next launch starts clean.
    expect(await store.read(SessionRepository.userKey), isNull);
  });

  test('restoreSession never throws when the session store fails', () async {
    client.authToken = 'stale-token';
    final provider = build(sessionRepo: ThrowingSessionRepository());

    await provider.restoreSession();

    expect(provider.status, AuthStatus.signedOut);
    expect(provider.user, isNull);
    expect(client.authToken, isNull);
  });

  test('login success persists token+user and sets client authToken', () async {
    final provider = build();

    final ok = await provider.login(
      email: 'ana@example.com',
      password: 'password1',
    );

    expect(ok, isTrue);
    expect(provider.status, AuthStatus.signedIn);
    expect(provider.busy, isFalse);
    expect(provider.lastError, isNull);
    expect(provider.user?.email, 'mock@example.com');
    expect(client.authToken, 'mock-access-token');
    expect(repo.lastEmail, 'ana@example.com');
    final cached = await session.load();
    expect(cached, isNotNull);
    expect(cached!.token, 'mock-access-token');
    expect(cached.user.email, 'mock@example.com');
  });

  test('login 401 -> signedOut with loginError, nothing persisted', () async {
    // Deliberately NOT the copy-deck string: a provider that forwarded the
    // raw server `detail` would fail this test (F3).
    repo.error = const ApiException('RAW-SERVER-401-DETAIL', statusCode: 401);
    final provider = await signedInProvider();
    await provider.signOut();

    final ok = await provider.login(
      email: 'ana@example.com',
      password: 'wrongpass1',
    );

    expect(ok, isFalse);
    expect(provider.status, AuthStatus.signedOut);
    expect(provider.lastError, Copy.loginError);
    expect(provider.busy, isFalse);
    expect(client.authToken, isNull);
    expect(await store.read(TokenStore.storageKey), isNull);
    expect(await store.read(SessionRepository.userKey), isNull);
  });

  test(
    'login network error -> lastError is the offline copy, retryingNetwork true during the retry',
    () async {
      // First attempt fails, the single retry also fails: network stays down.
      final fake = FakeAuthRepository(networkFailures: 2);
      var flagDuringRetry = false;
      final provider = build(auth: fake);
      await provider.restoreSession();
      fake.onRetry = provider.notifyRetrying;
      fake.onRetryAttempt = () => flagDuringRetry = provider.retryingNetwork;

      final ok = await provider.login(
        email: 'ana@example.com',
        password: 'password1',
      );

      expect(ok, isFalse);
      expect(fake.loginCalls, 1, reason: 'one provider-visible call');
      expect(fake.attempts, 2, reason: 'first attempt + the single retry');
      expect(
        flagDuringRetry,
        isTrue,
        reason: 'retryingNetwork is true while the retry runs',
      );
      expect(provider.lastError, Copy.offline);
      expect(provider.status, AuthStatus.signedOut);
      // Cleared once the call settled, success or not.
      expect(provider.retryingNetwork, isFalse);
      expect(provider.busy, isFalse);
    },
  );

  test(
    'login network error that succeeds on retry -> signedIn, flag cleared',
    () async {
      final fake = FakeAuthRepository(networkFailures: 1);
      var flagDuringRetry = false;
      final provider = build(auth: fake);
      fake.onRetry = provider.notifyRetrying;
      fake.onRetryAttempt = () => flagDuringRetry = provider.retryingNetwork;

      final ok = await provider.login(
        email: 'ana@example.com',
        password: 'password1',
      );

      expect(ok, isTrue);
      expect(fake.loginCalls, 1);
      expect(fake.attempts, 2);
      expect(flagDuringRetry, isTrue);
      expect(provider.status, AuthStatus.signedIn);
      expect(provider.retryingNetwork, isFalse);
      expect(provider.lastError, isNull);
    },
  );

  test(
    'retryingNetwork stays false when the repository has no onRetry hook',
    () async {
      // MockAuthRepository never signals a retry — the provider must simply
      // work (and never surface the waking flag) without the callback.
      repo.error = const ApiException('Network error');
      final provider = build();

      final ok = await provider.login(
        email: 'ana@example.com',
        password: 'password1',
      );

      expect(ok, isFalse);
      expect(provider.lastError, Copy.offline);
      expect(provider.retryingNetwork, isFalse);
    },
  );

  test(
    'retryingNetwork flip notifies listeners (screen repaint source)',
    () async {
      final fake = FakeAuthRepository(networkFailures: 1);
      final provider = build(auth: fake);
      await provider.restoreSession();
      final seenFlags = <bool>[];
      provider.addListener(() => seenFlags.add(provider.retryingNetwork));
      fake.onRetry = provider.notifyRetrying;

      final ok = await provider.login(
        email: 'ana@example.com',
        password: 'password1',
      );

      expect(ok, isTrue);
      // One notification fired with the flag set (banner shows) and the
      // settle notification with it cleared (banner hides).
      expect(seenFlags, contains(true));
      expect(seenFlags.last, isFalse);
    },
  );

  test('notifyRetrying while idle does not flip retryingNetwork', () {
    final provider = build();
    var notified = 0;
    provider.addListener(() => notified += 1);

    provider.notifyRetrying();

    // No auth call is in flight: the waking state must not stick, and no
    // listener churn should occur.
    expect(provider.retryingNetwork, isFalse);
    expect(notified, 0);
  });

  test(
    'signup network error -> offline copy, retryingNetwork true during the retry, false on settle',
    () async {
      final fake = FakeAuthRepository(networkFailures: 2);
      var flagDuringRetry = false;
      final provider = build(auth: fake);
      await provider.restoreSession();
      fake.onRetry = provider.notifyRetrying;
      fake.onRetryAttempt = () => flagDuringRetry = provider.retryingNetwork;

      final ok = await provider.signup(
        name: 'Ana Cruz',
        email: 'ana@example.com',
        password: 'password1',
        contactNumber: '09171234567',
      );

      expect(ok, isFalse);
      expect(fake.signupCalls, 1, reason: 'one provider-visible call');
      expect(fake.attempts, 2, reason: 'first attempt + the single retry');
      expect(flagDuringRetry, isTrue);
      expect(provider.lastError, Copy.offline);
      expect(provider.retryingNetwork, isFalse);
      expect(provider.busy, isFalse);
    },
  );

  test(
    'signup network error that succeeds on retry -> signedIn, flag cleared',
    () async {
      final fake = FakeAuthRepository(networkFailures: 1);
      var flagDuringRetry = false;
      final provider = build(auth: fake);
      fake.onRetry = provider.notifyRetrying;
      fake.onRetryAttempt = () => flagDuringRetry = provider.retryingNetwork;

      final ok = await provider.signup(
        name: 'Ana Cruz',
        email: 'ana@example.com',
        password: 'password1',
        contactNumber: '09171234567',
      );

      expect(ok, isTrue);
      expect(fake.signupCalls, 1);
      expect(fake.attempts, 2);
      expect(flagDuringRetry, isTrue);
      expect(provider.status, AuthStatus.signedIn);
      expect(provider.retryingNetwork, isFalse);
      expect(provider.lastError, isNull);
    },
  );

  test('login 429 -> rateLimited copy', () async {
    // Raw sentinel, not Copy.rateLimited: proves the mapping, not a
    // passthrough (F3).
    repo.error = const ApiException('RAW-SERVER-429-DETAIL', statusCode: 429);
    final provider = build();

    final ok = await provider.login(
      email: 'ana@example.com',
      password: 'password1',
    );

    expect(ok, isFalse);
    expect(provider.lastError, Copy.rateLimited);
  });

  test('login 400 / 500 / malformed-2xx -> genericError copy', () async {
    for (final status in <int>[400, 500, 200]) {
      // Raw sentinel, not Copy.genericError: proves the mapping (F3).
      repo.error = ApiException(
        'RAW-SERVER-UNEXPECTED-DETAIL',
        statusCode: status,
      );
      final provider = build();

      final ok = await provider.login(
        email: 'ana@example.com',
        password: 'password1',
      );

      expect(ok, isFalse, reason: 'status $status');
      expect(provider.lastError, Copy.genericError, reason: 'status $status');
      expect(provider.retryingNetwork, isFalse, reason: 'status $status');
    }
  });

  test('signup success -> signedIn; signup 409 -> emailExists copy', () async {
    final provider = build();
    final ok = await provider.signup(
      name: 'Ana Cruz',
      email: 'ana@example.com',
      password: 'password1',
      contactNumber: '09171234567',
    );
    expect(ok, isTrue);
    expect(provider.status, AuthStatus.signedIn);
    expect(repo.signupCalls, 1);
    expect(repo.lastName, 'Ana Cruz');
    expect(repo.lastContactNumber, '09171234567');
    expect(client.authToken, 'mock-access-token');

    // A fresh signed-out state (the successful signup above cached a session).
    await session.clear();
    // Raw sentinel, not the copy-deck string: proves 409 is *mapped* to
    // Copy.emailExists, not forwarded (F3).
    repo.error = const ApiException('RAW-SERVER-409-DETAIL', statusCode: 409);
    final second = build();
    await second.restoreSession();
    final failed = await second.signup(
      name: 'Ana Cruz',
      email: 'ana@example.com',
      password: 'password1',
      contactNumber: '09171234567',
    );
    expect(failed, isFalse);
    expect(second.status, AuthStatus.signedOut);
    expect(second.lastError, Copy.emailExists);
  });

  test('failed signup persists nothing and stays signedOut', () async {
    repo.error = const ApiException('Network error');
    final provider = build();
    await provider.restoreSession();

    final ok = await provider.signup(
      name: 'Ana Cruz',
      email: 'ana@example.com',
      password: 'password1',
      contactNumber: '09171234567',
    );

    expect(ok, isFalse);
    expect(provider.status, AuthStatus.signedOut);
    expect(client.authToken, isNull);
    expect(await store.read(TokenStore.storageKey), isNull);
    expect(await store.read(SessionRepository.userKey), isNull);
  });

  test('second submit while busy is ignored (single request)', () async {
    final provider = build();

    final first = provider.login(
      email: 'ana@example.com',
      password: 'password1',
    );
    final second = provider.login(
      email: 'ana@example.com',
      password: 'password1',
    );

    expect(await second, isFalse);
    expect(await first, isTrue);
    expect(repo.loginCalls, 1);
    expect(provider.status, AuthStatus.signedIn);
  });

  test('signOut clears storage and client token -> signedOut', () async {
    final provider = await signedInProvider();
    expect(provider.status, AuthStatus.signedIn);

    await provider.signOut();

    expect(provider.status, AuthStatus.signedOut);
    expect(provider.user, isNull);
    expect(client.authToken, isNull);
    expect(await store.read(TokenStore.storageKey), isNull);
    expect(await store.read(SessionRepository.userKey), isNull);
  });

  test(
    'successful login with a failing store ends signedIn, token set, no error',
    () async {
      final provider = AuthProvider(
        auth: repo,
        session: SessionRepository(ThrowingSecureStore()),
        client: client,
      );

      final ok = await provider.login(
        email: 'ana@example.com',
        password: 'password1',
      );

      // The server accepted the credentials: a dead store must not undo
      // the sign-in, throw, or surface an error for a login that worked.
      expect(ok, isTrue);
      expect(provider.status, AuthStatus.signedIn);
      expect(provider.user?.email, 'mock@example.com');
      expect(client.authToken, 'mock-access-token');
      expect(provider.lastError, isNull);
      expect(provider.busy, isFalse);
      expect(provider.retryingNetwork, isFalse);
    },
  );

  test(
    'signOut never throws and signs out even when the store clear fails',
    () async {
      final provider = AuthProvider(
        auth: repo,
        session: SessionRepository(ThrowingSecureStore()),
        client: client,
      );
      await provider.login(email: 'ana@example.com', password: 'password1');
      expect(provider.status, AuthStatus.signedIn);

      await provider.signOut(); // must not throw

      expect(provider.status, AuthStatus.signedOut);
      expect(provider.user, isNull);
      expect(client.authToken, isNull);
    },
  );

  test(
    'handleUnauthorized(401) clears the cached session -> signedOut',
    () async {
      final provider = await signedInProvider();

      final handled = provider.handleUnauthorized(401);

      expect(handled, isTrue);
      expect(provider.status, AuthStatus.signedOut);
      expect(provider.user, isNull);
      expect(client.authToken, isNull);
      await pumpEventQueue();
      expect(await store.read(TokenStore.storageKey), isNull);
      expect(await store.read(SessionRepository.userKey), isNull);
    },
  );

  test('handleUnauthorized with any other status is a no-op', () async {
    final provider = await signedInProvider();

    for (final status in <int?>[null, 400, 403, 500]) {
      expect(
        provider.handleUnauthorized(status),
        isFalse,
        reason: 'status $status',
      );
    }
    expect(provider.status, AuthStatus.signedIn);
    expect(client.authToken, 'tok-123');
    expect((await session.load())?.token, 'tok-123');
  });

  test(
    'replaceUser persists the updated user into the session store',
    () async {
      final provider = await signedInProvider();
      var notified = 0;
      provider.addListener(() => notified += 1);
      final updated = User(
        id: 7,
        name: 'Ana Santos',
        email: 'ana@example.com',
        contactNumber: '09181112222',
        createdAt: DateTime.utc(2026, 10, 18, 9, 30),
      );

      await provider.replaceUser(updated);

      expect(notified, 1);
      expect(provider.user?.name, 'Ana Santos');
      // The token is kept: only the user half is rewritten.
      expect(client.authToken, 'tok-123');
      final reloaded = await session.load();
      expect(reloaded, isNotNull);
      expect(reloaded!.token, 'tok-123');
      expect(reloaded.user.name, 'Ana Santos');
      expect(reloaded.user.contactNumber, '09181112222');
    },
  );

  test(
    'replaceUser never throws and still updates memory when the store fails',
    () async {
      final provider = AuthProvider(
        auth: repo,
        session: SessionRepository(ThrowingSecureStore()),
        client: client,
      );
      await provider.login(email: 'ana@example.com', password: 'password1');

      await provider.replaceUser(buildUser(name: 'Ana Santos')); // must not throw

      expect(provider.user?.name, 'Ana Santos');
      expect(client.authToken, isNotNull);
    },
  );
}
