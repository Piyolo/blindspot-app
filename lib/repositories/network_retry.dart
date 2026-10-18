import 'package:blindspot_app/models/api_exception.dart';

/// Retries [call] exactly once when it fails with a network-level
/// [ApiException] — `statusCode == null`, i.e. connection loss, timeout, or
/// the cold Render backend dropping the first request.
///
/// HTTP errors always carry a status code (4xx/5xx) and are rethrown
/// immediately; only the transport layer is ever retried, and only once.
/// [onRetry] (when provided) fires exactly once, immediately before that
/// single retry attempt — never on first-attempt success, never on 4xx/5xx.
///
/// Each attempt also runs through [_guarded], so any failure to *interpret*
/// a response surfaces as an [ApiException] (see [_guarded]).
///
/// Internal to the repository layer: screens talk to `AuthRepository` /
/// `ProfileRepository`, never to this helper. It lives in its own file
/// (rather than as a `_`-private top-level function in one of the
/// repository files) because Dart's privacy is per-library, so a private
/// helper cannot be shared across the two repository files.
Future<T> withNetworkRetry<T>(
  Future<T> Function() call, {
  void Function()? onRetry,
}) async {
  try {
    return await _guarded(call);
  } on ApiException catch (error) {
    if (error.statusCode != null) {
      rethrow;
    }
    onRetry?.call();
    return await _guarded(call);
  }
}

/// Success status used when a 2xx response cannot be interpreted: the exact
/// code (200 vs 201) is not observable through `ApiClient`'s map-returning
/// API, and the important property is that it is **non-null**, so the
/// failure is never retried and providers route it to their generic-error
/// path instead of the offline copy.
const ApiException _malformedResponse =
    ApiException('Malformed response', statusCode: 200);

/// Runs a single attempt, converting any failure to *interpret* a response
/// — truncated JSON, a non-object body, or a payload missing/mistyping its
/// required fields — into an [ApiException].
///
/// These failures can only originate from a response whose status was 2xx:
/// `ApiClient` already degrades non-2xx `detail` parsing itself and maps
/// transport failures to `ApiException('Network error')`. Providers catch
/// [ApiException] only, so a raw [FormatException]/[TypeError] escaping
/// here would become an unhandled error — the loud-failure direction is to
/// surface it as an [ApiException] with a non-null status.
Future<T> _guarded<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException {
    rethrow;
  } on FormatException {
    throw _malformedResponse;
  } on TypeError {
    throw _malformedResponse;
  }
}
