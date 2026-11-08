import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/providers/detection_provider.dart';
import 'package:blindspot_app/services/detection/camera_source.dart';
import 'package:blindspot_app/services/detection/detection_announcer.dart';
import 'package:blindspot_app/services/detection/detection_engine.dart';
import 'package:blindspot_app/services/detection/frame_converter.dart';
import 'package:blindspot_app/services/detection/frame_processor.dart';
import 'package:blindspot_app/services/detection/proximity_alarm.dart';
import 'package:blindspot_app/services/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCamera implements CameraSource {
  void Function(CameraFrame)? _onFrame;

  int initializeCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;
  bool torch = false;
  Object? initializeError;

  @override
  Size? frameSize = const Size(640, 480);

  @override
  bool get hasTorch => true;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    final Object? error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> start(void Function(CameraFrame) onFrame) async {
    startCalls++;
    _onFrame = onFrame;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }

  @override
  Future<void> setTorch(bool on) async {
    torch = on;
  }

  /// Delivers one 2x2 frame; the engine's motion gate passes the first.
  void emit() {
    _onFrame?.call(
      CameraFrame(
        planes: FramePlanes(
          format: FrameFormat.yuv420,
          y: Uint8List.fromList(<int>[10, 20, 30, 40]),
          u: Uint8List.fromList(<int>[128]),
          v: Uint8List.fromList(<int>[128]),
          width: 2,
          height: 2,
          yBytesPerRow: 2,
          uvBytesPerRow: 1,
          uvPixelStride: 1,
          rotationDegrees: 0,
        ),
        capturedAt: DateTime(2026, 1, 1),
      ),
    );
  }
}

class SilentSpeechEngine implements SpeechEngine {
  @override
  Future<void> configure({
    required String language,
    required double rate,
  }) async {}

  @override
  Future<bool> isLanguageAvailable(String language) async => true;

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

class SilentAlarmOutput implements AlarmOutput {
  @override
  Future<void> vibrate(int milliseconds) async {}

  @override
  Future<void> playAlarm() async {}

  @override
  Future<void> stopAlarm() async {}
}

class RecordingAnnouncer extends DetectionAnnouncer {
  RecordingAnnouncer(List<String> log)
    : _log = log,
      super(
        tts: TtsService(SilentSpeechEngine()),
        now: DateTime.now,
        alarmActive: () => false,
      );

  final List<String> _log;
  final List<List<Detection>> calls = <List<Detection>>[];
  int resetCalls = 0;

  @override
  Future<void> onDetections(List<Detection> detections) async {
    calls.add(detections);
    _log.add('announce');
  }

  @override
  Future<void> reset() async {
    resetCalls++;
  }
}

class RecordingAlarm extends ProximityAlarm {
  RecordingAlarm(List<String> log)
    : _log = log,
      super(
        output: SilentAlarmOutput(),
        tts: TtsService(SilentSpeechEngine()),
        wait: (Duration duration) async {},
      );

  final List<String> _log;
  final List<Detection?> nearestCalls = <Detection?>[];
  int stopCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> onNearest(Detection? nearest) async {
    nearestCalls.add(nearest);
    _log.add('alarm');
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

class GatedProcessor implements FrameProcessor {
  final Completer<FrameResult?> result = Completer<FrameResult?>();
  bool started = false;

  @override
  Future<void> initialize() async {}

  @override
  Future<FrameResult?> process(FrameRequest request) {
    started = true;
    return result.future;
  }

  @override
  Future<void> dispose() async {}
}

Detection detection(String label, {double? distance, double confidence = 0.9}) {
  return Detection(
    label: label,
    confidence: confidence,
    box: const Rect.fromLTRB(300, 0, 340, 40),
    distanceMeters: distance,
    direction: DetectionDirection.ahead,
  );
}

FrameResult frameResult(List<Detection> detections) {
  return FrameResult(
    frameId: 1,
    detections: detections,
    convertMs: 1,
    inferenceMs: 1,
    totalMs: 2,
  );
}

class ProviderHarness {
  ProviderHarness({FrameProcessor? processor, this.signedIn = true})
    : camera = FakeCamera(),
      processor = processor ?? FakeFrameProcessor() {
    announcer = RecordingAnnouncer(log);
    alarm = RecordingAlarm(log);
    engine = DetectionEngine(
      camera: camera,
      processor: this.processor,
      now: () => now,
    );
    provider = DetectionProvider(
      engine: engine,
      announcer: announcer,
      alarm: alarm,
      isSignedIn: () => signedIn,
    );
  }

  final FakeCamera camera;
  final FrameProcessor processor;
  final List<String> log = <String>[];
  bool signedIn;
  DateTime now = DateTime(2026, 1, 1);
  late final RecordingAnnouncer announcer;
  late final RecordingAlarm alarm;
  late final DetectionEngine engine;
  late final DetectionProvider provider;
}

void main() {
  test(
    'start moves starting -> running and resets the announcer session',
    () async {
      final ProviderHarness h = ProviderHarness();
      final List<DetectionEngineStatus> statuses = <DetectionEngineStatus>[];
      h.provider.addListener(() => statuses.add(h.provider.status));

      await h.provider.start();

      expect(statuses.first, DetectionEngineStatus.starting);
      expect(statuses.last, DetectionEngineStatus.running);
      expect(h.provider.status, DetectionEngineStatus.running);
      expect(h.announcer.resetCalls, 1);
      expect(h.camera.initializeCalls, 1);
      expect(h.provider.hasTorch, isTrue);
      expect(h.provider.frameSize, const Size(640, 480));
    },
  );

  test('start is a no-op for a signed-out session', () async {
    final ProviderHarness h = ProviderHarness(signedIn: false);

    await h.provider.start();

    expect(h.provider.status, DetectionEngineStatus.idle);
    expect(h.camera.initializeCalls, 0);
    expect(h.announcer.resetCalls, 0);
  });

  test(
    'a frame reaches the announcer, then the alarm, and stores the nearest',
    () async {
      final Detection sofa = detection('Sofa', distance: 0.8);
      final Detection table = detection('Table', distance: 1.5);
      final Detection bed = detection('Bed');
      final ProviderHarness h = ProviderHarness(
        processor: FakeFrameProcessor(
          respond: (FrameRequest request) =>
              frameResult(<Detection>[table, sofa, bed]),
        ),
      );
      await h.provider.start();

      h.camera.emit();
      await pumpEventQueue();

      expect(h.provider.detections, <Detection>[table, sofa, bed]);
      expect(h.provider.nearest, same(sofa));
      expect(h.announcer.calls.single, <Detection>[table, sofa, bed]);
      expect(h.alarm.nearestCalls.single, same(sofa));
      expect(h.log, <String>['announce', 'alarm']);
    },
  );

  test(
    'nearest ignores distance-less detections and wins ties by confidence',
    () async {
      final Detection low = detection('Chair', distance: 1.0, confidence: 0.6);
      final Detection high = detection('Table', distance: 1.0, confidence: 0.9);
      final ProviderHarness h = ProviderHarness(
        processor: FakeFrameProcessor(
          respond: (FrameRequest request) =>
              frameResult(<Detection>[low, high, detection('Bed')]),
        ),
      );
      await h.provider.start();

      h.camera.emit();
      await pumpEventQueue();

      expect(h.provider.nearest, same(high));
    },
  );

  test(
    'no distance in the frame leaves nearest null but keeps the list',
    () async {
      final ProviderHarness h = ProviderHarness(
        processor: FakeFrameProcessor(
          respond: (FrameRequest request) =>
              frameResult(<Detection>[detection('Bed')]),
        ),
      );
      await h.provider.start();

      h.camera.emit();
      await pumpEventQueue();

      expect(h.provider.detections, hasLength(1));
      expect(h.provider.nearest, isNull);
      expect(h.alarm.nearestCalls.single, isNull);
    },
  );

  test('stop stops the engine and the alarm and clears the list', () async {
    final ProviderHarness h = ProviderHarness(
      processor: FakeFrameProcessor(
        respond: (FrameRequest request) =>
            frameResult(<Detection>[detection('Chair', distance: 1.0)]),
      ),
    );
    await h.provider.start();
    h.camera.emit();
    await pumpEventQueue();
    expect(h.provider.detections, isNotEmpty);

    await h.provider.stop();

    expect(h.provider.detections, isEmpty);
    expect(h.provider.nearest, isNull);
    expect(h.provider.status, DetectionEngineStatus.idle);
    expect(h.alarm.stopCalls, 1);
    expect(h.camera.stopCalls, 1);
  });

  test('retry recovers from a camera failure', () async {
    final ProviderHarness h = ProviderHarness();
    h.camera.initializeError = StateError('camera busy');

    await h.provider.start();
    expect(h.provider.status, DetectionEngineStatus.error);
    expect(h.provider.error, contains('camera busy'));

    h.camera.initializeError = null;
    await h.provider.retry();
    expect(h.provider.status, DetectionEngineStatus.running);
    expect(h.provider.error, isNull);
    expect(h.camera.startCalls, 1);
  });

  test('toggleTorch flips the engine torch and notifies', () async {
    final ProviderHarness h = ProviderHarness();
    await h.provider.start();
    int notifications = 0;
    h.provider.addListener(() => notifications++);

    await h.provider.toggleTorch();

    expect(h.provider.torchOn, isTrue);
    expect(h.camera.torch, isTrue);
    expect(notifications, 1);
  });

  test('dispose during a pending frame never announces or notifies', () async {
    final GatedProcessor processor = GatedProcessor();
    final ProviderHarness h = ProviderHarness(processor: processor);
    await h.provider.start();
    int notifications = 0;
    h.provider.addListener(() => notifications++);
    h.camera.emit();
    await pumpEventQueue();
    expect(processor.started, isTrue);
    final int before = notifications;

    h.provider.dispose();
    processor.result.complete(
      frameResult(<Detection>[detection('Chair', distance: 1.0)]),
    );
    await pumpEventQueue();

    expect(notifications, before);
    expect(h.announcer.calls, isEmpty);
    expect(h.alarm.nearestCalls, isEmpty);
    expect(h.alarm.disposeCalls, 1);
    expect(h.camera.disposeCalls, 1);
  });
}
