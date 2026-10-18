import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:blindspot_app/models/api_exception.dart';

class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 25),
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? defaultBaseUrl,
        _timeout = timeout;

  static const String defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://blindspot-api-dkch.onrender.com');

  final http.Client _client;
  final String _baseUrl;
  final Duration _timeout;

  String? authToken;

  Future<Map<String, dynamic>> get(String path) => _request('GET', path);

  Future<Map<String, dynamic>> post(String path, {Map<String, dynamic>? body}) =>
      _request('POST', path, body: body);

  Future<Map<String, dynamic>> put(String path, {Map<String, dynamic>? body}) =>
      _request('PUT', path, body: body);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1$path');
    final request = http.Request(method, uri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = 'application/json';
    if (authToken != null) {
      request.headers['Authorization'] = 'Bearer $authToken';
    }
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      final streamed =
          await _client.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('Network error');
    } on http.ClientException {
      throw const ApiException('Network error');
    } on SocketException {
      throw const ApiException('Network error');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final text = utf8.decode(response.bodyBytes);
      if (text.isEmpty) {
        return <String, dynamic>{};
      }
      return jsonDecode(text) as Map<String, dynamic>;
    }

    String? detail;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic> && decoded['detail'] is String) {
        detail = decoded['detail'] as String;
      }
    } catch (_) {
      detail = null;
    }
    throw ApiException(detail ?? 'Request failed', statusCode: response.statusCode);
  }
}
