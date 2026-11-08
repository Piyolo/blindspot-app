import 'package:blindspot_app/services/detection/proximity_alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// [AlarmOutput] backed by the `blindspot/system` MethodChannel (Task 9).
///
/// The channel is best-effort: a missing vibrator, a missing player or any
/// platform failure is swallowed and only logged in debug, so the alarm can
/// never take detection down with it.
class PlatformAlarmOutput implements AlarmOutput {
  PlatformAlarmOutput({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('blindspot/system');

  final MethodChannel _channel;

  @override
  Future<void> vibrate(int milliseconds) =>
      _invoke('vibrate', <String, Object?>{'ms': milliseconds});

  @override
  Future<void> playAlarm() => _invoke('playAlarm');

  @override
  Future<void> stopAlarm() => _invoke('stopAlarm');

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      if (kDebugMode) {
        debugPrint('blindspot/system $method failed: ${error.code}');
      }
    }
  }
}
