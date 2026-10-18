import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/repositories/profile_repository.dart';
import 'package:blindspot_app/services/api_client.dart';

void main() {
  const userJson = '{"id": 7, "name": "Ana Cruz", "email": "ana@example.com", '
      '"contact_number": "+639171234567", "created_at": "2026-10-18T12:00:00Z"}';
  const meJson = '{"user": $userJson}';

  ApiProfileRepository repoWith(MockClient mock) => ApiProfileRepository(
        ApiClient(baseUrl: 'https://example.test', client: mock),
      );

  test('updateProfile PUTs /api/v1/me and parses the returned user', () async {
    late http.Request captured;
    final repo = repoWith(MockClient((request) async {
      captured = request;
      return http.Response(meJson, 200);
    }));

    final user = await repo.updateProfile(
      name: 'Ana Cruz',
      contactNumber: '+63 917 123 4567',
    );

    expect(captured.method, 'PUT');
    expect(captured.url.toString(), 'https://example.test/api/v1/me');
    expect(jsonDecode(captured.body), <String, dynamic>{
      'name': 'Ana Cruz',
      'contact_number': '+639171234567',
    });
    expect(user.id, 7);
    expect(user.name, 'Ana Cruz');
    expect(user.contactNumber, '+639171234567');
    expect(user.createdAt, DateTime.utc(2026, 10, 18, 12));
  });

  test('updateProfile sends only the provided fields', () async {
    final bodies = <Map<String, dynamic>>[];
    final repo = repoWith(MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(meJson, 200);
    }));

    await repo.updateProfile(name: 'Ana Cruz');
    await repo.updateProfile(contactNumber: '09171234567');
    await repo.updateProfile();

    expect(bodies, <Map<String, dynamic>>[
      <String, dynamic>{'name': 'Ana Cruz'},
      <String, dynamic>{'contact_number': '09171234567'},
      <String, dynamic>{},
    ]);
  });

  test('updateProfile rejects a malformed contact client-side without a request',
      () async {
    var requests = 0;
    final repo = repoWith(MockClient((request) async {
      requests += 1;
      return http.Response(meJson, 200);
    }));

    await expectLater(
      repo.updateProfile(contactNumber: 'abc'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 400)
          .having((e) => e.message, 'message', 'Invalid contact number')),
    );
    expect(requests, 0);
  });

  test('updateProfile maps 401 to ApiException and does not retry', () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      return http.Response('{"detail": "Invalid or expired token"}', 401);
    }));

    await expectLater(
      repo.updateProfile(name: 'Ana Cruz'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', 'Invalid or expired token')),
    );
    expect(calls, 1);
  });

  test('updateProfile retries once on network error then succeeds', () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      if (calls == 1) {
        throw http.ClientException('connection reset');
      }
      return http.Response(meJson, 200);
    }));

    final user = await repo.updateProfile(name: 'Ana Cruz');

    expect(calls, 2);
    expect(user.name, 'Ana Cruz');
  });

  test('changePassword PUTs /api/v1/me/password and resolves on {"ok":true}',
      () async {
    late http.Request captured;
    final repo = repoWith(MockClient((request) async {
      captured = request;
      return http.Response('{"ok": true}', 200);
    }));

    await repo.changePassword(
        currentPassword: 'oldpass12', newPassword: 'newpass12');

    expect(captured.method, 'PUT');
    expect(captured.url.toString(), 'https://example.test/api/v1/me/password');
    expect(jsonDecode(captured.body), <String, dynamic>{
      'current_password': 'oldpass12',
      'new_password': 'newpass12',
    });
  });

  test('changePassword maps 401 wrong current password to ApiException',
      () async {
    final repo = repoWith(MockClient((request) async =>
        http.Response('{"detail": "Current password is incorrect."}', 401)));

    await expectLater(
      repo.changePassword(
          currentPassword: 'wrongpass1', newPassword: 'newpass12'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', 'Current password is incorrect.')),
    );
  });

  test('updateProfile onRetry fires exactly once when the first attempt is a network error',
      () async {
    var calls = 0;
    var retries = 0;
    final repo = ApiProfileRepository(
      ApiClient(baseUrl: 'https://example.test', client: MockClient((request) async {
        calls += 1;
        if (calls == 1) {
          throw http.ClientException('connection reset');
        }
        return http.Response(meJson, 200);
      })),
      onRetry: () => retries += 1,
    );

    await repo.updateProfile(name: 'Ana Cruz');

    expect(calls, 2);
    expect(retries, 1);
  });

  test('updateProfile onRetry does not fire on first-attempt success', () async {
    var retries = 0;
    final repo = ApiProfileRepository(
      ApiClient(baseUrl: 'https://example.test', client: MockClient((request) async =>
          http.Response(meJson, 200))),
      onRetry: () => retries += 1,
    );

    await repo.updateProfile(name: 'Ana Cruz');

    expect(retries, 0);
  });

  test('updateProfile onRetry does not fire on 401', () async {
    var calls = 0;
    var retries = 0;
    final repo = ApiProfileRepository(
      ApiClient(baseUrl: 'https://example.test', client: MockClient((request) async {
        calls += 1;
        return http.Response('{"detail": "Invalid or expired token"}', 401);
      })),
      onRetry: () => retries += 1,
    );

    await expectLater(
      repo.updateProfile(name: 'Ana Cruz'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(calls, 1);
    expect(retries, 0);
  });

  test('changePassword throws ApiException when the server returns ok:false',
      () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      return http.Response('{"ok": false}', 200);
    }));

    await expectLater(
      repo.changePassword(
          currentPassword: 'oldpass12', newPassword: 'newpass12'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 200)
          .having((e) => e.message, 'message', isNotEmpty)),
    );
    expect(calls, 1);
  });

  test('changePassword throws ApiException when ok is missing ({})', () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      return http.Response('{}', 200);
    }));

    await expectLater(
      repo.changePassword(
          currentPassword: 'oldpass12', newPassword: 'newpass12'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 200)
          .having((e) => e.message, 'message', isNotEmpty)),
    );
    expect(calls, 1);
  });

  test('changePassword throws ApiException on an empty response body', () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      return http.Response('', 200);
    }));

    await expectLater(
      repo.changePassword(
          currentPassword: 'oldpass12', newPassword: 'newpass12'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 200)
          .having((e) => e.message, 'message', isNotEmpty)),
    );
    expect(calls, 1);
  });

  test(
      'changePassword throws ApiException on ok:null, a non-object body, and malformed JSON without retrying',
      () async {
    final bodies = <String>[
      '{"ok": null}', // null flag
      '[1, 2]', // non-object body
      '{"ok": tr', // truncated JSON
    ];
    for (final body in bodies) {
      var calls = 0;
      var retries = 0;
      final repo = ApiProfileRepository(
        ApiClient(
          baseUrl: 'https://example.test',
          client: MockClient((request) async {
            calls += 1;
            return http.Response(body, 200);
          }),
        ),
        onRetry: () => retries += 1,
      );

      await expectLater(
        repo.changePassword(
            currentPassword: 'oldpass12', newPassword: 'newpass12'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', isNotNull)
            .having((e) => e.message, 'message', isNotEmpty)),
        reason: 'body: $body',
      );
      expect(calls, 1, reason: 'no retry for body: $body');
      expect(retries, 0, reason: 'no onRetry for body: $body');
    }
  });

  test('updateProfile maps malformed 2xx payloads to ApiException and never retries',
      () async {
    final malformedBodies = <String>[
      '', // empty body: no user object
      '{"user": {"id": 7}}', // user missing required fields
      '{"user": {', // truncated JSON
    ];
    for (final body in malformedBodies) {
      var calls = 0;
      var retries = 0;
      final repo = ApiProfileRepository(
        ApiClient(
          baseUrl: 'https://example.test',
          client: MockClient((request) async {
            calls += 1;
            return http.Response(body, 200);
          }),
        ),
        onRetry: () => retries += 1,
      );

      await expectLater(
        repo.updateProfile(name: 'Ana Cruz'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', isNotNull)
            .having((e) => e.message, 'message', isNotEmpty)),
        reason: 'body: $body',
      );
      expect(calls, 1, reason: 'no retry for body: $body');
      expect(retries, 0, reason: 'no onRetry for body: $body');
    }
  });

  test('MockProfileRepository serves a canned success and can be set to fail',
      () async {
    final ok = MockProfileRepository();
    final user = await ok.updateProfile(name: 'Ana Cruz');
    expect(ok.updateProfileCalls, 1);
    expect(user.email, 'mock@example.com');

    final failing =
        MockProfileRepository(error: const ApiException('boom', statusCode: 500));
    await expectLater(
      failing.changePassword(
          currentPassword: 'oldpass12', newPassword: 'newpass12'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'boom')),
    );
    expect(failing.changePasswordCalls, 1);
  });
}
