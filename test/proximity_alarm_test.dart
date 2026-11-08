import 'dart:async';
import 'dart:ui' show Rect;

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/services/detection/proximity_alarm.dart';
import 'package:blindspot_app/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every platform effect into one ordered log shared with the
/// waiter and the speech engine, so the sequence can be asserted whole.
class FakeAlarmOutput implements AlarmOutput {
  FakeAlarmOutput(this.events);

  final List<String> events;

  @override
  Future<void> vibrate(int milliseconds) async {
    events.add('vibrate:$milliseconds');
  }

  @override
  Future<void> playAlarm() async {
    events.add('playAlarm');
  }

  @override
  Future<void> stopAlarm() async {
    events.add('stopAlarm');
  }
}

class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine(this.events);

  final List<String> events;

  @override
  Future<void> configure({
    required String language,
    required double rate,
  }) async {}

  @override
  Future<bool> isLanguageAvailable(String language) async => true;

  @override
  Future<void> speak(String text) async {
    events.add('speak:$text');
  }

  @override
  Future<void> stop() async {}
}

/// Either completes immediately (the default) or holds each wait until
/// [releaseNext]/[releaseAll], which lets a test inspect the window.
class RecordingWaiter {
  RecordingWaiter({required this.events, this.gated = false});

  final List<String> events;
  final bool gated;
  final List<Duration> requested = <Duration>[];
  final List<Completer<void>> _pending = <Completer<void>>[];

  Future<void> wait(Duration duration) {
    requested.add(duration);
    events.add('wait:${duration.inMilliseconds}ms');
    if (!gated) {
      return Future<void>.value();
    }
    final Completer<void> completer = Completer<void>();
    _pending.add(completer);
    return completer.future;
  }

  int get pending =>
      _pending.where((Completer<void> c) => !c.isCompleted).length;

  void releaseNext() {
    _pending.firstWhere((Completer<void> c) => !c.isCompleted).complete();
  }

  void releaseAll() {
    for (final Completer<void> completer in _pending) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}

class AlarmHarness {
  AlarmHarness({bool gated = false}) {
    tts = TtsService(FakeSpeechEngine(events));
    waiter = RecordingWaiter(events: events, gated: gated);
    alarm = ProximityAlarm(
      output: FakeAlarmOutput(events),
      tts: tts,
      wait: waiter.wait,
    );
  }

  final List<String> events = <String>[];
  late final TtsService tts;
  late final RecordingWaiter waiter;
  late final ProximityAlarm alarm;
}

Detection detection({String label = 'Chair', double? distanceMeters = 0.5}) {
  return Detection(
    label: label,
    confidence: 0.9,
    box: const Rect.fromLTWH(280, 0, 80, 80),
    distanceMeters: distanceMeters,
    direction: DetectionDirection.ahead,
  );
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('does not trigger at exactly the 0.70 m threshold', () async {
    final AlarmHarness h = AlarmHarness();
    await h.alarm.onNearest(detection(distanceMeters: 0.70));
    expect(h.events, isEmpty);
    expect(h.alarm.isActive, isFalse);
  });

  test('does not trigger beyond the threshold either', () async {
    final AlarmHarness h = AlarmHarness();
    await h.alarm.onNearest(detection(distanceMeters: 0.71));
    expect(h.events, isEmpty);
  });

  test('plays the four effects in order with the pinned durations', () async {
    final AlarmHarness h = AlarmHarness();
    await h.alarm.onNearest(detection(distanceMeters: 0.69));

    expect(h.events, <String>[
      'vibrate:300',
      'wait:300ms',
      'playAlarm',
      'wait:1000ms',
      'speak:Chair is too close.',
      'wait:3000ms',
    ]);
    expect(h.waiter.requested, <Duration>[
      const Duration(milliseconds: 300),
      const Duration(milliseconds: 1000),
      const Duration(milliseconds: 3000),
    ]);
    expect(h.alarm.isActive, isFalse);
  });

  test('speaks the too-close template with the detection label', () async {
    final AlarmHarness h = AlarmHarness();
    await h.alarm.onNearest(detection(label: 'Sofa', distanceMeters: 0.4));
    expect(h.events, contains('speak:Sofa is too close.'));
    expect(Copy.tooCloseTemplate, '{object} is too close.');
  });

  test('is active for the whole window and ignores a second trigger', () async {
    final AlarmHarness h = AlarmHarness(gated: true);
    final Future<void> run = h.alarm.onNearest(detection());
    await pump();

    expect(h.alarm.isActive, isTrue);
    expect(h.events, <String>['vibrate:300', 'wait:300ms']);

    await h.alarm.onNearest(detection());
    expect(h.events, <String>['vibrate:300', 'wait:300ms']);

    h.waiter.releaseNext();
    await pump();
    expect(h.events, <String>[
      'vibrate:300',
      'wait:300ms',
      'playAlarm',
      'wait:1000ms',
    ]);

    await h.alarm.onNearest(detection());
    expect(h.events.where((String e) => e == 'vibrate:300'), hasLength(1));

    h.waiter.releaseNext();
    await pump();
    expect(h.events, <String>[
      'vibrate:300',
      'wait:300ms',
      'playAlarm',
      'wait:1000ms',
      'speak:Chair is too close.',
      'wait:3000ms',
    ]);
    expect(h.alarm.isActive, isTrue);

    h.waiter.releaseNext();
    await pump();
    await run;
    expect(h.alarm.isActive, isFalse);
  });

  test('allows a new trigger after the window ends', () async {
    final AlarmHarness h = AlarmHarness();
    await h.alarm.onNearest(detection());
    await h.alarm.onNearest(detection());
    expect(h.events.where((String e) => e == 'vibrate:300'), hasLength(2));
  });

  test('stop silences the output and cancels the sequence', () async {
    final AlarmHarness h = AlarmHarness(gated: true);
    final Future<void> run = h.alarm.onNearest(detection());
    await pump();

    await h.alarm.stop();
    expect(h.alarm.isActive, isFalse);
    expect(h.events, contains('stopAlarm'));

    h.waiter.releaseAll();
    await pump();
    await run;

    expect(h.events.where((String e) => e.startsWith('speak:')), isEmpty);
    expect(h.events.where((String e) => e == 'playAlarm'), isEmpty);
  });

  test(
    'dispose during the sequence never speaks afterwards and is idempotent',
    () async {
      final AlarmHarness h = AlarmHarness(gated: true);
      final Future<void> run = h.alarm.onNearest(detection());
      await pump();

      await h.alarm.dispose();
      await h.alarm.dispose();
      expect(h.events.where((String e) => e == 'stopAlarm'), hasLength(1));

      h.waiter.releaseAll();
      await pump();
      await run;

      expect(h.events.where((String e) => e.startsWith('speak:')), isEmpty);
      expect(h.alarm.isActive, isFalse);

      await h.alarm.onNearest(detection());
      expect(h.events.where((String e) => e == 'vibrate:300'), hasLength(1));
    },
  );

  test('a frame without a distance never triggers', () async {
    final AlarmHarness h = AlarmHarness();
    await h.alarm.onNearest(null);
    await h.alarm.onNearest(detection(distanceMeters: null));
    expect(h.events, isEmpty);
    expect(h.alarm.isActive, isFalse);
  });
}
