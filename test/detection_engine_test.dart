import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/services/detection/camera_source.dart';
import 'package:blindspot_app/services/detection/detection_engine.dart';
import 'package:blindspot_app/services/detection/frame_converter.dart';
import 'package:blindspot_app/services/detection/frame_processor.dart';
import 'package:flutter_test/flutter_test.dart';

/// A camera that records its lifecycle and emits frames on demand.
///
/// [emit] keeps delivering to the last registered callback even after
/// [stop], which models a frame already in flight when the engine stops.
class FakeCamera implements CameraSource {
  FakeCamera({this.hasTorch = false});

  final List<String> calls = <String>[];
  final List<bool> torchStates = <bool>[];
  Object? initializeError;
  Object? startError;
  int disposeCalls = 0;
  void Function(CameraFrame)? _onFrame;

  @override
  bool hasTorch;

  @override
  Size? frameSize = const Size(640, 480);

  @override
  Future<void> initialize() async {
    calls.add('initialize');
    final Object? error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> start(void Function(CameraFrame) onFrame) async {
    calls.add('start');
    final Object? error = startError;
    if (error != null) {
      throw error;
    }
    _onFrame = onFrame;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> setTorch(bool on) async {
    torchStates.add(on);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    disposeCalls++;
  }

  void emit(FramePlanes planes, {required DateTime at}) {
    _onFrame?.call(CameraFrame(planes: planes, capturedAt: at));
  }
}

/// A processor whose results are either immediate or gated by a
/// completer, so tests can hold a run open without sleeping.
class RecordingProcessor implements FrameProcessor {
  RecordingProcessor({required this.clock});

  final DateTime Function() clock;
  final List<FrameRequest> requests = <FrameRequest>[];
  final List<DateTime> acceptedAt = <DateTime>[];
  final List<Completer<FrameResult?>> _pending = <Completer<FrameResult?>>[];
  FrameResult Function(FrameRequest request)? respond;
  Object? initializeError;
  Object? processError;
  bool manual = false;
  int initializeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    final Object? error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<FrameResult?> process(FrameRequest request) {
    requests.add(request);
    acceptedAt.add(clock());
    final Object? error = processError;
    if (error != null) {
      return Future<FrameResult?>.error(error);
    }
    if (manual) {
      final Completer<FrameResult?> completer = Completer<FrameResult?>();
      _pending.add(completer);
      return completer.future;
    }
    return Future<FrameResult?>.value(resultFor(request));
  }

  FrameResult resultFor(FrameRequest request) {
    final FrameResult Function(FrameRequest request)? override = respond;
    if (override != null) {
      return override(request);
    }
    return emptyResult(request.frameId);
  }

  void completeNext([FrameResult? result]) {
    _pending.removeAt(0).complete(result);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

FrameResult emptyResult(int frameId) {
  return FrameResult(
    frameId: frameId,
    detections: const <Detection>[],
    convertMs: 0,
    inferenceMs: 0,
    totalMs: 0,
  );
}

FrameResult slowResult(FrameRequest request) {
  return FrameResult(
    frameId: request.frameId,
    detections: const <Detection>[],
    convertMs: 0,
    inferenceMs: 0,
    totalMs: 400,
  );
}

FramePlanes grayPlane(int luma, {int width = 224, int height = 224}) {
  final int stride = width;
  final Uint8List y = Uint8List(stride * height)
    ..fillRange(0, stride * height, luma);
  return FramePlanes(
    format: FrameFormat.nv21,
    y: y,
    width: width,
    height: height,
    yBytesPerRow: stride,
    uvBytesPerRow: width,
    uvPixelStride: 2,
    rotationDegrees: 0,
  );
}

class EngineHarness {
  EngineHarness({bool hasTorch = false})
    : startedAt = DateTime(2026, 1, 1, 12),
      now = DateTime(2026, 1, 1, 12),
      camera = FakeCamera(hasTorch: hasTorch) {
    processor = RecordingProcessor(clock: () => now);
    engine = DetectionEngine(
      camera: camera,
      processor: processor,
      now: () => now,
      onResult: (List<Detection> detections, FrameResult result) {
        results.add((detections, result));
      },
      onStatus: (DetectionEngineStatus status, String? error) {
        statuses.add(status);
        errors.add(error);
      },
    );
  }

  final DateTime startedAt;
  DateTime now;
  final FakeCamera camera;
  late final RecordingProcessor processor;
  late final DetectionEngine engine;
  final List<(List<Detection>, FrameResult)> results =
      <(List<Detection>, FrameResult)>[];
  final List<DetectionEngineStatus> statuses = <DetectionEngineStatus>[];
  final List<String?> errors = <String?>[];

  void advance(int milliseconds) {
    now = now.add(Duration(milliseconds: milliseconds));
  }

  Future<void> emit(FramePlanes planes) async {
    camera.emit(planes, at: now);
    await pumpEventQueue();
  }

  List<int> get acceptedOffsetsMs => processor.acceptedAt
      .map((DateTime time) => time.difference(startedAt).inMilliseconds)
      .toList(growable: false);
}

void main() {
  group('lifecycle', () {
    test(
      'start() reports starting, initialises both halves, then running',
      () async {
        final EngineHarness h = EngineHarness();
        expect(h.engine.status, DetectionEngineStatus.idle);

        final Future<void> starting = h.engine.start();
        expect(h.engine.status, DetectionEngineStatus.starting);

        await starting;
        expect(h.engine.status, DetectionEngineStatus.running);
        expect(h.camera.calls, <String>['initialize', 'start']);
        expect(h.processor.initializeCalls, 1);
        expect(h.statuses, <DetectionEngineStatus>[
          DetectionEngineStatus.starting,
          DetectionEngineStatus.running,
        ]);
        expect(h.errors, <String?>[null, null]);
      },
    );

    test(
      'a camera init failure reports error and stops; retry() recovers',
      () async {
        final EngineHarness h = EngineHarness();
        h.camera.initializeError = StateError('camera boom');

        await h.engine.start();
        expect(h.engine.status, DetectionEngineStatus.error);
        expect(h.errors.last, contains('camera boom'));
        expect(h.camera.calls, <String>['initialize', 'stop']);
        expect(h.processor.initializeCalls, 0);

        h.camera.initializeError = null;
        await h.engine.retry();
        expect(h.engine.status, DetectionEngineStatus.running);
        expect(h.camera.calls.last, 'start');
      },
    );

    test(
      'a processor init failure reports error before the camera starts',
      () async {
        final EngineHarness h = EngineHarness();
        h.processor.initializeError = StateError('model missing');

        await h.engine.start();
        expect(h.engine.status, DetectionEngineStatus.error);
        expect(h.errors.last, contains('model missing'));
        expect(h.camera.calls, <String>['initialize', 'stop']);
      },
    );

    test(
      'stop() during a run discards the result and returns to idle',
      () async {
        final EngineHarness h = EngineHarness();
        h.processor.manual = true;
        await h.engine.start();
        await h.emit(grayPlane(0));
        expect(h.processor.requests, hasLength(1));

        await h.engine.stop();
        expect(h.engine.status, DetectionEngineStatus.idle);
        expect(h.camera.calls.last, 'stop');

        h.processor.completeNext(
          emptyResult(h.processor.requests.single.frameId),
        );
        await pumpEventQueue();
        expect(h.results, isEmpty);

        await h.emit(grayPlane(255));
        expect(h.processor.requests, hasLength(1));
      },
    );

    test('stop() resets the thermal tier', () async {
      final EngineHarness h = EngineHarness();
      h.processor.respond = slowResult;
      await h.engine.start();
      await h.emit(grayPlane(0));
      h.advance(600);
      await h.emit(grayPlane(255));
      expect(h.processor.requests, hasLength(2), reason: 'two slow frames');

      await h.engine.stop();
      await h.engine.start();
      await h.emit(grayPlane(0));
      h.advance(600);
      await h.emit(grayPlane(255));

      // With a reset tier the second frame passes the 600 ms gate; a
      // surviving 1200 ms tier would have dropped it.
      expect(h.processor.requests, hasLength(4));
    });

    test(
      'dispose() is idempotent, ignores in-flight work and shuts both halves',
      () async {
        final EngineHarness h = EngineHarness();
        h.processor.manual = true;
        await h.engine.start();
        await h.emit(grayPlane(0));

        await h.engine.dispose();
        await h.engine.dispose();

        expect(h.camera.disposeCalls, 1);
        expect(h.processor.disposeCalls, 1);
        expect(h.engine.status, DetectionEngineStatus.idle);

        h.processor.completeNext(
          emptyResult(h.processor.requests.single.frameId),
        );
        await pumpEventQueue();
        expect(h.results, isEmpty);

        await h.emit(grayPlane(255));
        expect(h.processor.requests, hasLength(1));
      },
    );

    test('toggleTorch() is a no-op without a torch', () async {
      final EngineHarness h = EngineHarness(hasTorch: false);
      await h.engine.start();

      await h.engine.toggleTorch();

      expect(h.camera.torchStates, isEmpty);
      expect(h.engine.hasTorch, isFalse);
      expect(h.engine.torchOn, isFalse);
    });

    test('toggleTorch() flips the torch and tracks it', () async {
      final EngineHarness h = EngineHarness(hasTorch: true);
      await h.engine.start();
      expect(h.engine.hasTorch, isTrue);

      await h.engine.toggleTorch();
      expect(h.engine.torchOn, isTrue);

      await h.engine.toggleTorch();
      expect(h.engine.torchOn, isFalse);
      expect(h.camera.torchStates, <bool>[true, false]);
    });
  });

  group('frame pump', () {
    test(
      'drops frames inside the 600 ms gate and accepts at exactly 600 ms',
      () async {
        final EngineHarness h = EngineHarness();
        await h.engine.start();

        await h.emit(grayPlane(0));
        expect(h.processor.requests, hasLength(1));

        h.advance(300);
        await h.emit(grayPlane(255));
        expect(h.processor.requests, hasLength(1));

        // 500 ms in is still inside the 600 ms gate; a 450 ms cadence
        // (the donor's) would accept here, so this pins the spec value.
        h.advance(200);
        await h.emit(grayPlane(255));
        expect(h.processor.requests, hasLength(1));

        h.advance(100);
        await h.emit(grayPlane(255));
        expect(h.processor.requests, hasLength(2));
      },
    );

    test('drops an overlapping frame while a run is in flight', () async {
      final EngineHarness h = EngineHarness();
      h.processor.manual = true;
      await h.engine.start();
      await h.emit(grayPlane(0));
      expect(h.processor.requests, hasLength(1));

      h.advance(600);
      await h.emit(grayPlane(255));
      expect(h.processor.requests, hasLength(1));

      h.processor.completeNext(
        emptyResult(h.processor.requests.single.frameId),
      );
      await pumpEventQueue();

      h.advance(600);
      await h.emit(grayPlane(255));
      expect(h.processor.requests, hasLength(2));
    });

    test('a null result emits nothing and clears busy', () async {
      final EngineHarness h = EngineHarness();
      h.processor.manual = true;
      await h.engine.start();
      await h.emit(grayPlane(0));

      h.processor.completeNext();
      await pumpEventQueue();
      expect(h.results, isEmpty);

      h.advance(600);
      await h.emit(grayPlane(255));
      expect(h.processor.requests, hasLength(2));
    });

    test(
      'skips identical frames after the first and resumes on motion',
      () async {
        final EngineHarness h = EngineHarness();
        await h.engine.start();
        await h.emit(grayPlane(0));
        expect(h.processor.requests, hasLength(1));

        h.advance(600);
        await h.emit(grayPlane(0));
        expect(h.processor.requests, hasLength(1), reason: 'no motion');

        h.advance(600);
        await h.emit(grayPlane(255));
        expect(h.processor.requests, hasLength(2));

        h.advance(600);
        await h.emit(grayPlane(255));
        expect(
          h.processor.requests,
          hasLength(2),
          reason: 'still frame skipped',
        );
      },
    );

    test(
      'forwards detections and the result with monotonic frame ids',
      () async {
        final EngineHarness h = EngineHarness();
        const Detection chair = Detection(
          label: 'chair',
          confidence: 0.9,
          box: Rect.fromLTRB(10, 20, 110, 220),
          distanceMeters: 1.5,
          direction: DetectionDirection.ahead,
        );
        h.processor.respond = (FrameRequest request) => FrameResult(
          frameId: request.frameId,
          detections: const <Detection>[chair],
          convertMs: 3,
          inferenceMs: 40,
          totalMs: 50,
        );
        await h.engine.start();
        await h.emit(grayPlane(0));
        h.advance(600);
        await h.emit(grayPlane(255));

        expect(
          h.processor.requests.map((FrameRequest request) => request.frameId),
          <int>[1, 2],
        );
        expect(h.processor.requests.first.capturedAt, h.startedAt);
        expect(h.results, hasLength(2));
        expect(h.results.first.$1.single, chair);
        expect(h.results.first.$2.frameId, 1);
        expect(h.results.last.$2.frameId, 2);
        expect(h.errors, everyElement(isNull));
      },
    );

    test(
      'a processing error reports error, stops the camera and ignores later frames',
      () async {
        final EngineHarness h = EngineHarness();
        h.processor.processError = StateError('inference boom');
        await h.engine.start();
        await h.emit(grayPlane(0));

        expect(h.engine.status, DetectionEngineStatus.error);
        expect(h.errors.last, contains('inference boom'));
        expect(h.camera.calls.last, 'stop');

        await h.emit(grayPlane(255));
        expect(h.processor.requests, hasLength(1));
      },
    );
  });

  group('thermal ladder', () {
    test(
      'escalates 600 -> 1200 -> 2000 after two slow frames and stops there',
      () async {
        final EngineHarness h = EngineHarness();
        h.processor.respond = slowResult;
        await h.engine.start();

        for (int tick = 0; tick < 18; tick++) {
          await h.emit(grayPlane((tick * 30) % 256));
          if (tick < 17) {
            h.advance(600);
          }
        }

        expect(h.acceptedOffsetsMs, <int>[
          0,
          600,
          1800,
          3000,
          5400,
          7800,
          10200,
        ]);
      },
    );

    test('returns to 600 ms after 10 s of fast frames', () async {
      final EngineHarness h = EngineHarness();
      int runs = 0;
      h.processor.respond = (FrameRequest request) {
        final bool slow = runs < 2;
        runs++;
        return FrameResult(
          frameId: request.frameId,
          detections: const <Detection>[],
          convertMs: 0,
          inferenceMs: 0,
          totalMs: slow ? 400 : 100,
        );
      };
      await h.engine.start();

      for (int tick = 0; tick < 24; tick++) {
        await h.emit(grayPlane((tick * 30) % 256));
        if (tick < 23) {
          h.advance(600);
        }
      }

      expect(h.acceptedOffsetsMs, <int>[
        0,
        600,
        1800,
        3000,
        4200,
        5400,
        6600,
        7800,
        9000,
        10200,
        11400,
        12600,
        13200,
        13800,
      ]);
    });

    test('a fast frame between slow frames prevents escalation', () async {
      final EngineHarness h = EngineHarness();
      int runs = 0;
      h.processor.respond = (FrameRequest request) {
        final int run = runs++;
        return FrameResult(
          frameId: request.frameId,
          detections: const <Detection>[],
          convertMs: 0,
          inferenceMs: 0,
          totalMs: run == 1 ? 100 : 400,
        );
      };
      await h.engine.start();

      await h.emit(grayPlane(0));
      h.advance(600);
      await h.emit(grayPlane(100));
      h.advance(600);
      await h.emit(grayPlane(200));
      h.advance(600);
      await h.emit(grayPlane(50));

      // Had the slow streak survived the fast frame, the third frame would
      // have escalated and the fourth would miss the 600 ms gate.
      expect(h.acceptedOffsetsMs, <int>[0, 600, 1200, 1800]);
    });
  });
}
