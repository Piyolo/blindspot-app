import 'dart:typed_data';

import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/services/detection/frame_converter.dart';
import 'package:blindspot_app/services/detection/frame_processor.dart';
import 'package:flutter_test/flutter_test.dart';

FramePlanes tinyPlanes() => FramePlanes(
  format: FrameFormat.yuv420,
  y: Uint8List.fromList(<int>[1, 2, 3, 4]),
  u: Uint8List.fromList(<int>[128]),
  v: Uint8List.fromList(<int>[128]),
  width: 2,
  height: 2,
  yBytesPerRow: 2,
  uvBytesPerRow: 1,
  uvPixelStride: 1,
  rotationDegrees: 0,
);

FrameRequest frame(int id) => FrameRequest(
  planes: tinyPlanes(),
  frameId: id,
  capturedAt: DateTime.utc(2026, 1, 1, 0, 0, id),
);

FrameResult scripted(
  int id, {
  int convertMs = 4,
  int inferenceMs = 90,
  int totalMs = 100,
}) => FrameResult(
  frameId: id,
  detections: const <Detection>[],
  convertMs: convertMs,
  inferenceMs: inferenceMs,
  totalMs: totalMs,
);

void main() {
  group('FrameResult', () {
    test('carries the frame id, detections and timings', () {
      final FrameResult result = scripted(7);

      expect(result.frameId, 7);
      expect(result.detections, isEmpty);
      expect(result.convertMs, 4);
      expect(result.inferenceMs, 90);
      expect(result.totalMs, 100);
    });
  });

  group('FakeFrameProcessor', () {
    test('records lifecycle calls and synthesizes a result', () async {
      final FakeFrameProcessor processor = FakeFrameProcessor();
      await processor.initialize();
      final FrameResult? result = await processor.process(frame(3));
      await processor.dispose();

      expect(processor.initializeCalls, 1);
      expect(processor.requests.single.frameId, 3);
      expect(processor.disposeCalls, 1);
      expect(result, isNotNull);
      expect(result!.frameId, 3);
      expect(result.detections, isEmpty);
      expect(result.convertMs, 0);
      expect(result.inferenceMs, 0);
      expect(result.totalMs, 0);
    });

    test('returns scripted results in order', () async {
      final FakeFrameProcessor processor = FakeFrameProcessor(
        script: <FrameResult>[scripted(11), scripted(12)],
      );

      final FrameResult? first = await processor.process(frame(1));
      final FrameResult? second = await processor.process(frame(2));

      expect(first!.frameId, 11);
      expect(first.inferenceMs, 90);
      expect(second!.frameId, 12);
    });

    test('serialises concurrent process calls', () async {
      final FakeFrameProcessor processor = FakeFrameProcessor(
        delay: const Duration(milliseconds: 10),
      );

      final List<FrameResult?> results = await Future.wait(
        <Future<FrameResult?>>[
          processor.process(frame(1)),
          processor.process(frame(2)),
        ],
      );

      expect(processor.maxConcurrent, 1);
      expect(processor.startedFrameIds, <int>[1, 2]);
      expect(processor.completedFrameIds, <int>[1, 2]);
      expect(results.map((FrameResult? result) => result!.frameId), <int>[
        1,
        2,
      ]);
    });

    test('propagates an initialize error', () async {
      final FakeFrameProcessor processor = FakeFrameProcessor()
        ..initializeError = StateError('no model');

      await expectLater(processor.initialize(), throwsA(isA<StateError>()));
    });

    test('keeps processing after a frame throws', () async {
      final FakeFrameProcessor processor = FakeFrameProcessor(
        respond: (FrameRequest request) {
          if (request.frameId == 1) {
            throw StateError('boom');
          }
          return scripted(request.frameId);
        },
      );

      await expectLater(
        processor.process(frame(1)),
        throwsA(isA<StateError>()),
      );
      final FrameResult? result = await processor.process(frame(2));

      expect(result!.frameId, 2);
      expect(processor.maxConcurrent, 1);
    });

    test('records dispose', () async {
      final FakeFrameProcessor processor = FakeFrameProcessor();
      await processor.dispose();
      expect(processor.disposeCalls, 1);
    });
  });
}
