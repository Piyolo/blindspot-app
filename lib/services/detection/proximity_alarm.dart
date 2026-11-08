import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/constants/detection.dart';
import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/services/tts_service.dart';
import 'package:blindspot_app/utils/template.dart';

/// The device effects the proximity alarm drives. The Android backing is
/// the `blindspot/system` channel (Task 9); tests use a fake.
abstract class AlarmOutput {
  Future<void> vibrate(int milliseconds);

  Future<void> playAlarm();

  Future<void> stopAlarm();
}

/// Warns that an object is closer than [DetectionConstants.proximityMeters]
/// (plan Task 8, spec §6.1/§10).
///
/// One trigger is a fixed sequence: `vibrate(300)` → 300 ms → `playAlarm()`
/// → [DetectionConstants.proximitySoundMs] → speak `Copy.tooCloseTemplate`
/// at [SpeechPriority.proximityAlarm] → [DetectionConstants.proximityCooldownMs]
/// of no triggering. [isActive] is true for that whole window, so the
/// announcer's `alarmActive` callback also suppresses detection speech
/// during the cooldown. There is no hysteresis (matches the donor).
///
/// [stop] and [dispose] invalidate the running sequence: its pending
/// awaits still complete, but it issues no further effect and never
/// speaks. [dispose] is idempotent.
class ProximityAlarm {
  ProximityAlarm({
    required AlarmOutput output,
    required TtsService tts,
    DateTime Function()? now,
    Future<void> Function(Duration)? wait,
  }) : _output = output,
       _tts = tts,
       _wait = wait ?? _delayed;

  final AlarmOutput _output;
  final TtsService _tts;
  final Future<void> Function(Duration) _wait;

  bool _active = false;
  bool _disposed = false;

  /// Incremented by [stop] and [dispose]; a sequence only continues while
  /// its run number is still current.
  int _run = 0;

  /// True from the first vibration through the end of the cooldown, so a
  /// frame that arrives mid-window is ignored by [onNearest].
  bool get isActive => _active;

  /// Runs the alarm sequence when [nearest] is strictly inside the
  /// threshold; a null distance never triggers.
  Future<void> onNearest(Detection? nearest) async {
    if (_disposed || _active) {
      return;
    }
    final double? distance = nearest?.distanceMeters;
    if (nearest == null ||
        distance == null ||
        distance >= DetectionConstants.proximityMeters) {
      return;
    }

    _active = true;
    final int run = ++_run;
    try {
      await _output.vibrate(DetectionConstants.proximityVibrateMs);
      if (!_isCurrent(run)) {
        return;
      }
      await _wait(
        Duration(milliseconds: DetectionConstants.proximityVibrateMs),
      );
      if (!_isCurrent(run)) {
        return;
      }
      await _output.playAlarm();
      if (!_isCurrent(run)) {
        return;
      }
      await _wait(Duration(milliseconds: DetectionConstants.proximitySoundMs));
      if (!_isCurrent(run)) {
        return;
      }
      await _tts.speak(
        fillTemplate(Copy.tooCloseTemplate, <String, String>{
          'object': nearest.label,
        }),
        priority: SpeechPriority.proximityAlarm,
      );
      if (!_isCurrent(run)) {
        return;
      }
      await _wait(
        Duration(milliseconds: DetectionConstants.proximityCooldownMs),
      );
    } finally {
      if (run == _run) {
        _active = false;
      }
    }
  }

  /// Silences the output and invalidates the running sequence.
  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    _run++;
    _active = false;
    await _output.stopAlarm();
  }

  /// [stop] once; later calls do nothing.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _run++;
    _active = false;
    await _output.stopAlarm();
  }

  bool _isCurrent(int run) => !_disposed && run == _run;

  static Future<void> _delayed(Duration duration) =>
      Future<void>.delayed(duration);
}
