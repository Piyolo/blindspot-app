import 'package:flutter_test/flutter_test.dart';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/providers/auth_provider.dart';
import 'package:blindspot_app/providers/profile_provider.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/repositories/profile_repository.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/services/api_client.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/services/token_store.dart';

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
  late AuthProvider auth;
  late MockProfileRepository repo;
  late ProfileProvider profile;

  setUp(() async {
    store = InMemorySecureStore();
    session = SessionRepository(store);
    client = ApiClient(baseUrl: 'https://example.test');
    // Land in the signed-in state a profile edit starts from. The
    // AuthRepository is never exercised here — profile edits go through
    // ProfileRepository; AuthProvider only owns session + token state.
    await session.save(token: 'tok-123', user: buildUser());
    auth = AuthProvider(
      auth: MockAuthRepository(),
      session: session,
      client: client,
    );
    await auth.restoreSession();
    repo = MockProfileRepository();
    profile = ProfileProvider(repository: repo, auth: auth);
  });

  test(
    'profile updateContact success -> repository called once and auth user refreshed (ProfileProvider)',
    () async {
      repo.user = buildUser(contactNumber: '09181112222');

      final ok = await profile.updateContact('0918-111-2222');

      expect(ok, isTrue);
      expect(repo.updateProfileCalls, 1);
      expect(repo.lastContactNumber, '0918-111-2222');
      expect(profile.lastError, isNull);
      expect(profile.busy, isFalse);
      // AuthProvider owns the cached user: the edit is merged through
      // replaceUser, which keeps the token and rewrites the stored user.
      expect(auth.user?.contactNumber, '09181112222');
      final reloaded = await session.load();
      expect(reloaded, isNotNull);
      expect(reloaded!.token, 'tok-123');
      expect(reloaded.user.contactNumber, '09181112222');
    },
  );

  test(
    'profile changeName success -> auth user refreshed and persisted',
    () async {
      repo.user = buildUser(name: 'Ana Santos');

      final ok = await profile.changeName('Ana Santos');

      expect(ok, isTrue);
      expect(repo.updateProfileCalls, 1);
      expect(repo.lastName, 'Ana Santos');
      expect(auth.user?.name, 'Ana Santos');
      final reloaded = await session.load();
      expect(reloaded!.user.name, 'Ana Santos');
      expect(reloaded.token, 'tok-123');
    },
  );

  test(
    'profile changePassword success -> resolves, session untouched',
    () async {
      final ok = await profile.changePassword(
        currentPassword: 'password1',
        newPassword: 'password2',
      );

      expect(ok, isTrue);
      expect(repo.changePasswordCalls, 1);
      expect(profile.lastError, isNull);
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.user?.name, 'Ana Cruz');
    },
  );

  test(
    'profile changePassword wrong current -> wrongCurrentPassword copy, stays signedIn',
    () async {
      // The server's dedicated 401 detail for a wrong current password
      // (backend `CURRENT_PASSWORD_ERROR`), not a dead session.
      repo.error = const ApiException(
        'Current password is incorrect.',
        statusCode: 401,
      );

      final ok = await profile.changePassword(
        currentPassword: 'oldpassword1',
        newPassword: 'password2',
      );

      expect(ok, isFalse);
      expect(profile.lastError, Copy.wrongCurrentPassword);
      expect(profile.busy, isFalse);
      // Crucially: no sign-out, nothing cleared.
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.user?.name, 'Ana Cruz');
      expect(client.authToken, 'tok-123');
      expect(await store.read(TokenStore.storageKey), 'tok-123');
      expect(await store.read(SessionRepository.userKey), isNotNull);
    },
  );

  test(
    'profile 401 -> handleUnauthorized cleared the cached session',
    () async {
      // Raw sentinel, not the copy-deck string: this path signs out rather
      // than mapping a message, and must never forward the server detail.
      repo.error = const ApiException('RAW-SERVER-401-DETAIL', statusCode: 401);

      final ok = await profile.updateContact('09181112222');

      expect(ok, isFalse);
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.user, isNull);
      expect(client.authToken, isNull);
      // Ratified: Task 12 sources its one-time notice from the status
      // transition, so lastError stays untouched here.
      expect(profile.lastError, isNull);
      await pumpEventQueue();
      expect(await store.read(TokenStore.storageKey), isNull);
      expect(await store.read(SessionRepository.userKey), isNull);
    },
  );

  test('profile offline (network error) -> needInternet copy', () async {
    repo.error = const ApiException('Network error');

    final ok = await profile.changeName('Ana Santos');

    expect(ok, isFalse);
    expect(profile.lastError, Copy.needInternet);
    // The cached value is kept: auth user untouched.
    expect(auth.user?.name, 'Ana Cruz');
  });

  test(
    'profile 429 -> rateLimited copy; other statuses -> genericError',
    () async {
      repo.error = const ApiException('Too many requests.', statusCode: 429);
      expect(await profile.changeName('X'), isFalse);
      expect(profile.lastError, Copy.rateLimited);

      repo.error = const ApiException('Server exploded', statusCode: 500);
      expect(await profile.changeName('X'), isFalse);
      expect(profile.lastError, Copy.genericError);

      // Malformed 2xx surfaces as a status-coded ApiException too.
      repo.error = const ApiException('Malformed response', statusCode: 200);
      expect(await profile.changeName('X'), isFalse);
      expect(profile.lastError, Copy.genericError);
    },
  );

  test(
    'second profile submit while busy is ignored (single request)',
    () async {
      repo.user = buildUser(contactNumber: '09181112222');

      final first = profile.updateContact('09181112222');
      final second = profile.updateContact('09199998888');

      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(repo.updateProfileCalls, 1);
      expect(auth.user?.contactNumber, '09181112222');
    },
  );
}
