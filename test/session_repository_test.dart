import 'package:flutter_test/flutter_test.dart';
import 'package:blindspot_app/models/user.dart';
import 'package:blindspot_app/repositories/session_repository.dart';
import 'package:blindspot_app/services/secure_store.dart';
import 'package:blindspot_app/services/token_store.dart';

void main() {
  late InMemorySecureStore store;
  late SessionRepository repository;

  User buildUser() => User(
        id: 7,
        name: 'Ana Cruz',
        email: 'ana@example.com',
        contactNumber: '09171234567',
        createdAt: DateTime.utc(2026, 10, 18, 9, 30),
      );

  setUp(() {
    store = InMemorySecureStore();
    repository = SessionRepository(store);
  });

  group('TokenStore', () {
    test('read/write/clear use the blindspot_token key', () async {
      final tokens = TokenStore(store);
      expect(await tokens.read(), isNull);
      await tokens.write('tok-123');
      expect(await store.read('blindspot_token'), 'tok-123');
      expect(await tokens.read(), 'tok-123');
      await tokens.clear();
      expect(await tokens.read(), isNull);
      expect(await store.read('blindspot_token'), isNull);
    });
  });

  group('SessionRepository', () {
    test('save then load returns the token and the user', () async {
      await repository.save(token: 'tok-123', user: buildUser());

      final loaded = await repository.load();
      expect(loaded, isNotNull);
      expect(loaded!.token, 'tok-123');
      expect(loaded.user.toJson(), buildUser().toJson());
      expect(loaded.user.name, 'Ana Cruz');
      expect(loaded.user.contactNumber, '09171234567');
    });

    test('clear() then load() returns null and empties storage', () async {
      await repository.save(token: 'tok-123', user: buildUser());
      await repository.clear();

      expect(await repository.load(), isNull);
      expect(await store.read('blindspot_token'), isNull);
      expect(await store.read('blindspot_user'), isNull);
    });

    test('load with nothing stored returns null', () async {
      expect(await repository.load(), isNull);
    });

    test('token without a user entry returns null', () async {
      await store.write('blindspot_token', 'tok-123');
      expect(await repository.load(), isNull);
    });

    test('corrupt stored user JSON returns null and deletes the bad entry',
        () async {
      await repository.save(token: 'tok-123', user: buildUser());
      await store.write('blindspot_user', 'not json {{{');

      expect(await repository.load(), isNull);
      expect(await store.read('blindspot_user'), isNull);
    });

    test('foreign non-object stored JSON returns null and deletes the bad entry',
        () async {
      await repository.save(token: 'tok-123', user: buildUser());
      await store.write('blindspot_user', '["someone", "else"]');

      expect(await repository.load(), isNull);
      expect(await store.read('blindspot_user'), isNull);
    });

    test('stored JSON with the wrong shape returns null and deletes the entry',
        () async {
      await repository.save(token: 'tok-123', user: buildUser());
      await store.write(
          'blindspot_user', '{"unexpected": true, "id": "not an int"}');

      expect(await repository.load(), isNull);
      expect(await store.read('blindspot_user'), isNull);
    });
  });
}
