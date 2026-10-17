import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:blindspot_app/models/api_exception.dart';
import 'package:blindspot_app/services/api_client.dart';

void main() {
  test('GET sends bearer token, hits /api/v1, and parses JSON', () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        captured = req;
        return http.Response('{"ok": true}', 200);
      }),
    );
    client.authToken = 't123';
    final data = await client.get('/health');
    expect(data['ok'], true);
    expect(captured.url.toString(), 'https://example.test/api/v1/health');
    expect(captured.headers['Authorization'], 'Bearer t123');
  });

  test('no token means no Authorization header', () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      }),
    );
    await client.get('/health');
    expect(captured.headers.containsKey('Authorization'), false);
  });

  test('non-2xx maps FastAPI detail to ApiException', () async {
    final client = ApiClient(
      baseUrl: 'https://example.test',
      client: MockClient((req) async =>
          http.Response('{"detail": "Invalid email or password."}', 401)),
    );
    await expectLater(
      client.post('/auth/login', body: {}),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 401)
          .having((e) => e.message, 'message', 'Invalid email or password.')),
    );
  });

  test('timeout maps to network ApiException', () async {
    final client = ApiClient(
      baseUrl: 'https://example.test',
      timeout: const Duration(milliseconds: 50),
      client: MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      client.get('/health'),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Network error')
          .having((e) => e.statusCode, 'statusCode', isNull)),
    );
  });
}
