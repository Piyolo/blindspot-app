import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/repositories/auth_repository.dart';
import 'package:blindspot_app/services/api_client.dart';

void main() {
  const userJson = '{"id": 7, "name": "Ana Cruz", "email": "ana@example.com", '
      '"contact_number": "+639171234567", "created_at": "2026-10-18T12:00:00Z"}';
  const authJson =
      '{"access_token": "tok-abc", "token_type": "bearer", "user": $userJson}';

  ApiAuthRepository repoWith(MockClient mock) => ApiAuthRepository(
        ApiClient(baseUrl: 'https://example.test', client: mock),
      );

  test(
      'signup posts /api/v1/auth/signup with normalized contact and parses AuthResult',
      () async {
    late http.Request captured;
    final repo = repoWith(MockClient((request) async {
      captured = request;
      return http.Response(authJson, 201);
    }));

    final result = await repo.signup(
      name: 'Ana Cruz',
      email: 'ana@example.com',
      password: 'password1',
      contactNumber: '+63 917-123-4567',
    );

    expect(captured.method, 'POST');
    expect(captured.url.toString(),
        'https://example.test/api/v1/auth/signup');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body, <String, dynamic>{
      'name': 'Ana Cruz',
      'email': 'ana@example.com',
      'password': 'password1',
      'contact_number': '+639171234567',
    });
    expect(result.accessToken, 'tok-abc');
    expect(result.user.id, 7);
    expect(result.user.email, 'ana@example.com');
    expect(result.user.contactNumber, '+639171234567');
    expect(result.user.createdAt, DateTime.utc(2026, 10, 18, 12));
  });

  test('signup maps 409 to ApiException with the detail message', () async {
    final repo = repoWith(MockClient((request) async => http.Response(
        '{"detail": "This email is already registered. Try logging in."}',
        409)));

    await expectLater(
      repo.signup(
        name: 'Ana Cruz',
        email: 'ana@example.com',
        password: 'password1',
        contactNumber: '09171234567',
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 409)
          .having((e) => e.message, 'message',
              'This email is already registered. Try logging in.')),
    );
  });

  test('signup rejects a malformed contact client-side without a request',
      () async {
    var requests = 0;
    final repo = repoWith(MockClient((request) async {
      requests += 1;
      return http.Response(authJson, 201);
    }));

    await expectLater(
      repo.signup(
        name: 'Ana Cruz',
        email: 'ana@example.com',
        password: 'password1',
        contactNumber: '12',
      ),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 400)
          .having((e) => e.message, 'message', 'Invalid contact number')),
    );
    expect(requests, 0);
  });

  test('login maps 401 to ApiException(loginError)', () async {
    final repo = repoWith(MockClient((request) async =>
        http.Response('{"detail": "Invalid email or password."}', 401)));

    await expectLater(
      repo.login(email: 'ana@example.com', password: 'wrongpassword1'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', 'Invalid email or password.')),
    );
  });

  test('login retries once on network error then succeeds', () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      if (calls == 1) {
        throw http.ClientException('connection reset');
      }
      return http.Response(authJson, 200);
    }));

    final result =
        await repo.login(email: 'ana@example.com', password: 'password1');

    expect(calls, 2);
    expect(result.accessToken, 'tok-abc');
  });

  test('login does not retry on 401', () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      return http.Response('{"detail": "Invalid email or password."}', 401);
    }));

    await expectLater(
      repo.login(email: 'ana@example.com', password: 'wrongpassword1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
    expect(calls, 1);
  });

  test('login does not retry on 500', () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      return http.Response('{"detail": "Internal server error"}', 500);
    }));

    await expectLater(
      repo.login(email: 'ana@example.com', password: 'password1'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 500)
          .having((e) => e.message, 'message', 'Internal server error')),
    );
    expect(calls, 1);
  });

  test('login gives up after the single retry when the network stays down',
      () async {
    var calls = 0;
    final repo = repoWith(MockClient((request) async {
      calls += 1;
      throw http.ClientException('connection reset');
    }));

    await expectLater(
      repo.login(email: 'ana@example.com', password: 'password1'),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Network error')
          .having((e) => e.statusCode, 'statusCode', isNull)),
    );
    expect(calls, 2);
  });

  test('login maps 429 rate limiting to ApiException', () async {
    final repo = repoWith(MockClient((request) async =>
        http.Response('{"detail": "Too many requests. Try again shortly."}', 429)));

    await expectLater(
      repo.login(email: 'ana@example.com', password: 'password1'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 429)
          .having(
              (e) => e.message, 'message', 'Too many requests. Try again shortly.')),
    );
  });

  test('login maps a non-JSON error body to a status-code ApiException',
      () async {
    final repo =
        repoWith(MockClient((request) async => http.Response('<html>Bad Gateway</html>', 502)));

    await expectLater(
      repo.login(email: 'ana@example.com', password: 'password1'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 502)
          .having((e) => e.message, 'message', 'Request failed')),
    );
  });

  test('MockAuthRepository serves a canned success and can be set to fail',
      () async {
    final ok = MockAuthRepository();
    final result =
        await ok.login(email: 'ana@example.com', password: 'password1');
    expect(ok.loginCalls, 1);
    expect(result.accessToken, 'mock-access-token');
    expect(result.user.email, 'mock@example.com');

    final failing =
        MockAuthRepository(error: const ApiException('boom', statusCode: 500));
    await expectLater(
      failing.signup(
        name: 'Ana Cruz',
        email: 'ana@example.com',
        password: 'password1',
        contactNumber: '09171234567',
      ),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'boom')),
    );
    expect(failing.signupCalls, 1);
  });
}
