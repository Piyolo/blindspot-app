import 'package:blindspot_app/models/api_exception.dart';

/// Retries [call] exactly once when it fails with a network-level
/// [ApiException] — `statusCode == null`, i.e. connection loss, timeout, or
/// the cold Render backend dropping the first request.
///
/// HTTP errors always carry a status code (4xx/5xx) and are rethrown
/// immediately; only the transport layer is ever retried, and only once.
///
/// Internal to the repository layer: screens talk to `AuthRepository` /
/// `ProfileRepository`, never to this helper. It lives in its own file
/// (rather than as a `_`-private top-level function in one of the
/// repository files) because Dart's privacy is per-library, so a private
/// helper cannot be shared across the two repository files.
Future<T> withNetworkRetry<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException catch (error) {
    if (error.statusCode != null) {
      rethrow;
    }
    return await call();
  }
}
