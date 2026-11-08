import 'dart:math';
import 'dart:ui' show Rect;

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/services/detection/detection_announcer.dart';
import 'package:blindspot_app/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A speech engine that records text and finishes every utterance
/// immediately, so the announcer's awaits resolve within the test.
class FakeSpeechEngine implements SpeechEngine {
  final List<String> spoken = <String>[];

  @override
  Future<void> configure({
    required String language,
    required double rate,
  }) async {}

  @override
  Future<bool> isLanguageAvailable(String language) async => true;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}
}

class AnnouncerHarness {
  /// Seed 80's first `nextInt(1001)` is 0, so the same-label cooldown is
  /// exactly 4000 ms and the 4.1 s boundary below is deterministic.
  AnnouncerHarness({int seed = 80}) {
    announcer = DetectionAnnouncer(
      tts: TtsService(engine),
      now: () => current,
      alarmActive: () => alarm,
      random: Random(seed),
    );
  }

  final FakeSpeechEngine engine = FakeSpeechEngine();
  late final DetectionAnnouncer announcer;
  DateTime current = DateTime.utc(2026, 11, 8, 12);
  bool alarm = false;

  void advance(int milliseconds) {
    current = current.add(Duration(milliseconds: milliseconds));
  }
}

const Rect leftThird = Rect.fromLTWH(0, 0, 100, 100);
const Rect aheadThird = Rect.fromLTWH(280, 0, 80, 80);
const Rect rightThird = Rect.fromLTWH(540, 0, 100, 100);

Detection detection({
  String label = 'Chair',
  double confidence = 0.9,
  double? distanceMeters = 2.0,
  Rect box = aheadThird,
}) {
  return Detection(
    label: label,
    confidence: confidence,
    box: box,
    distanceMeters: distanceMeters,
    direction: directionFor(box),
  );
}

void main() {
  test('announces the exact phrase for an object on the left', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[
      detection(label: 'Chair', distanceMeters: 1.0, box: leftThird),
    ]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Chair on the left, approximately 1 meter',
    ]);
  });

  test('announces the exact phrase for an object ahead', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[
      detection(label: 'Table', distanceMeters: 2.0, box: aheadThird),
    ]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Table ahead, approximately 2 meters',
    ]);
  });

  test('announces the exact phrase for an object on the right', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[
      detection(label: 'Door', distanceMeters: 0.55, box: rightThird),
    ]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Door on the right, approximately 60 centimeters',
    ]);
  });

  test('announces the nearest detection, not the most confident', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[
      detection(label: 'Chair', confidence: 0.99, distanceMeters: 3.0),
      detection(label: 'Table', confidence: 0.7, distanceMeters: 1.2),
    ]);
    expect(h.engine.spoken.last, 'Table ahead, approximately 1 meter');
  });

  test('breaks an equal distance with the higher confidence', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[
      detection(label: 'Chair', confidence: 0.7, distanceMeters: 2.0),
      detection(label: 'Table', confidence: 0.8, distanceMeters: 2.0),
    ]);
    expect(h.engine.spoken.last, 'Table ahead, approximately 2 meters');
  });

  test(
    'ignores detections without a distance when one has a distance',
    () async {
      final AnnouncerHarness h = AnnouncerHarness();
      await h.announcer.onDetections(<Detection>[
        detection(label: 'Chair', distanceMeters: 2.0),
        detection(
          label: 'Door',
          confidence: 0.99,
          distanceMeters: null,
          box: leftThird,
        ),
      ]);
      expect(h.engine.spoken.last, 'Chair ahead, approximately 2 meters');
    },
  );

  test('announces nothing and no disclaimer for an empty list', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[]);
    expect(h.engine.spoken, isEmpty);
  });

  test('suppresses the same label inside the 4 s cooldown', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[detection()]);
    h.advance(3900);
    await h.announcer.onDetections(<Detection>[detection()]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Chair ahead, approximately 2 meters',
    ]);
  });

  test('keys the cooldown by label, not by the composed phrase', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[detection()]);
    h.advance(3900);
    await h.announcer.onDetections(<Detection>[detection(distanceMeters: 3.0)]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Chair ahead, approximately 2 meters',
    ]);
  });

  test('allows the same label at 4.1 s', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[detection()]);
    h.advance(4100);
    await h.announcer.onDetections(<Detection>[detection()]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Chair ahead, approximately 2 meters',
      'Chair ahead, approximately 2 meters',
    ]);
  });

  test('allows a different label at 2.1 s', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[detection()]);
    h.advance(2100);
    await h.announcer.onDetections(<Detection>[
      detection(label: 'Table', distanceMeters: 2.0),
    ]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Chair ahead, approximately 2 meters',
      'Table ahead, approximately 2 meters',
    ]);
  });

  test(
    'stays silent while the alarm is active, without using a cooldown',
    () async {
      final AnnouncerHarness h = AnnouncerHarness();
      h.alarm = true;
      await h.announcer.onDetections(<Detection>[detection()]);
      expect(h.engine.spoken, isEmpty);

      h.alarm = false;
      h.advance(3500);
      await h.announcer.onDetections(<Detection>[detection()]);
      expect(h.engine.spoken, <String>[
        Copy.detectionDisclaimer,
        'Chair ahead, approximately 2 meters',
      ]);
    },
  );

  test('speaks the disclaimer once, before the first announcement', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[detection()]);
    h.advance(2100);
    await h.announcer.onDetections(<Detection>[
      detection(label: 'Table', distanceMeters: 2.0),
    ]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Chair ahead, approximately 2 meters',
      'Table ahead, approximately 2 meters',
    ]);
    expect(
      h.engine.spoken.where((String s) => s == Copy.detectionDisclaimer),
      hasLength(1),
    );
  });

  test('reset re-arms the disclaimer and clears the cooldown', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[detection()]);
    h.advance(1000);
    await h.announcer.reset();
    await h.announcer.onDetections(<Detection>[detection()]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Chair ahead, approximately 2 meters',
      Copy.detectionDisclaimer,
      'Chair ahead, approximately 2 meters',
    ]);
  });

  test('an empty list does not disturb the running cooldown', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[detection()]);
    h.advance(3000);
    await h.announcer.onDetections(<Detection>[]);
    h.advance(1100);
    await h.announcer.onDetections(<Detection>[detection()]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'Chair ahead, approximately 2 meters',
      'Chair ahead, approximately 2 meters',
    ]);
  });

  test('announces the fallback label without a distance', () async {
    final AnnouncerHarness h = AnnouncerHarness();
    await h.announcer.onDetections(<Detection>[
      detection(
        label: Copy.objectFallback,
        distanceMeters: null,
        box: leftThird,
      ),
    ]);
    expect(h.engine.spoken, <String>[
      Copy.detectionDisclaimer,
      'object on the left',
    ]);
  });
}
