import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/services/detection/yolo_postprocess.dart';
import 'package:flutter_test/flutter_test.dart';

/// The 14 model labels in `assets/ml/labelsV5.txt` order.
const List<String> labels = <String>[
  'Bed',
  'Cabinet',
  'Chair',
  'Door',
  'Electric Fan',
  'Laptop',
  'Monitor',
  'Person',
  'Refrigerator',
  'Sink',
  'Sofa',
  'Table',
  'Television',
  'Toilet',
];

const double ln4 = 1.3862943611198906; // sigmoid → 0.8
final double ln3 = math.log(3); // sigmoid → 0.75
const double lowLogit = -10;

/// One `[cx,cy,w,h, 14 classes]` row (the shipped 18-channel layout).
List<double> row18(
  double cx,
  double cy,
  double w,
  double h, {
  Map<int, double> logits = const <int, double>{},
}) {
  final List<double> row = <double>[
    cx,
    cy,
    w,
    h,
    ...List<double>.filled(14, lowLogit),
  ];
  logits.forEach((int index, double value) => row[4 + index] = value);
  return row;
}

/// One `[cx,cy,w,h, objectness, 14 classes]` row (the 19-channel variant).
List<double> row19(
  double cx,
  double cy,
  double w,
  double h,
  double objectness, {
  Map<int, double> logits = const <int, double>{},
}) {
  final List<double> row = <double>[
    cx,
    cy,
    w,
    h,
    objectness,
    ...List<double>.filled(14, lowLogit),
  ];
  logits.forEach((int index, double value) => row[5 + index] = value);
  return row;
}

Float32List channelsFirst(int channels, int anchors, List<List<double>> rows) {
  final Float32List output = Float32List(channels * anchors);
  for (int anchor = 0; anchor < anchors; anchor++) {
    for (int channel = 0; channel < channels; channel++) {
      output[channel * anchors + anchor] = rows[anchor][channel];
    }
  }
  return output;
}

Float32List anchorsFirst(int channels, int anchors, List<List<double>> rows) {
  final Float32List output = Float32List(channels * anchors);
  for (int anchor = 0; anchor < anchors; anchor++) {
    for (int channel = 0; channel < channels; channel++) {
      output[anchor * channels + channel] = rows[anchor][channel];
    }
  }
  return output;
}

List<Detection> decode(
  Float32List output,
  int dim1,
  int dim2, {
  double threshold = 0.6,
  List<String> modelLabels = labels,
}) {
  return postprocessYolo(
    output: output,
    dim1: dim1,
    dim2: dim2,
    labels: modelLabels,
    confidenceThreshold: threshold,
  );
}

void main() {
  group('detectLayout', () {
    test('channels-first when dim1 is classCount + 4 or + 5', () {
      expect(detectLayout(18, 8400, 14), YoloLayout.channelsFirst);
      expect(detectLayout(19, 8400, 14), YoloLayout.channelsFirst);
    });

    test('anchors-first when dim2 is classCount + 4 or + 5', () {
      expect(detectLayout(8400, 18, 14), YoloLayout.anchorsFirst);
      expect(detectLayout(8400, 19, 14), YoloLayout.anchorsFirst);
    });

    test('falls back to the smaller dimension as channels', () {
      expect(detectLayout(100, 20, 18), YoloLayout.anchorsFirst);
      expect(detectLayout(20, 100, 18), YoloLayout.channelsFirst);
    });
  });

  group('postprocessYolo', () {
    test('decodes a pixel-space box with sigmoid, distance and direction', () {
      final List<Detection> result = decode(
        channelsFirst(18, 2, <List<double>>[
          row18(320, 320, 64, 128, logits: <int, double>{0: ln4, 1: -2}),
          row18(0, 0, 0, 0),
        ]),
        18,
        2,
      );

      expect(result, hasLength(1));
      final Detection detection = result.single;
      expect(detection.label, 'Bed');
      expect(detection.confidence, closeTo(0.8, 1e-9));
      expect(detection.box, const Rect.fromLTRB(288, 256, 352, 384));
      expect(detection.direction, DetectionDirection.ahead);
      // 100 cm (bed) × 980 / 64 px = 1531.25 cm = 15.3125 m.
      expect(detection.distanceMeters, closeTo(15.3125, 1e-9));
    });

    test('normalised boxes decode to the same geometry', () {
      final List<Detection> normalised = decode(
        channelsFirst(18, 1, <List<double>>[
          row18(0.5, 0.5, 0.1, 0.2, logits: <int, double>{0: ln4}),
        ]),
        18,
        1,
      );
      final List<Detection> pixels = decode(
        channelsFirst(18, 1, <List<double>>[
          row18(320, 320, 64, 128, logits: <int, double>{0: ln4}),
        ]),
        18,
        1,
      );

      // The fixture tensor is a Float32List, so normalised 0.1 * 640 is
      // quantised to float32 (~1e-6 px here); compare with a tolerance
      // far below any real geometry error instead of exact Rect equality.
      expect(
        normalised.single.box,
        rectMoreOrLessEquals(pixels.single.box, epsilon: 1e-4),
      );
      expect(normalised.single.confidence, pixels.single.confidence);
      expect(
        normalised.single.distanceMeters,
        closeTo(pixels.single.distanceMeters!, 1e-6),
      );
    });

    test('anchors-first and channels-first produce identical detections', () {
      final List<List<double>> rows = <List<double>>[
        row18(320, 320, 64, 128, logits: <int, double>{0: ln4}),
        row18(100, 100, 40, 40, logits: <int, double>{1: ln3}),
      ];
      final List<Detection> channels = decode(
        channelsFirst(18, 2, rows),
        18,
        2,
      );
      final List<Detection> anchors = decode(anchorsFirst(18, 2, rows), 2, 18);

      expect(channels, hasLength(2));
      expect(anchors, hasLength(2));
      for (int i = 0; i < 2; i++) {
        expect(anchors[i].label, channels[i].label);
        expect(anchors[i].confidence, channels[i].confidence);
        expect(anchors[i].box, channels[i].box);
      }
    });

    test('applies sigmoid (raw 0 is 0.5) and includes the threshold', () {
      final Float32List output = channelsFirst(18, 1, <List<double>>[
        row18(320, 320, 64, 128, logits: <int, double>{0: 0}),
      ]);

      final List<Detection> atThreshold = decode(output, 18, 1, threshold: 0.5);
      final List<Detection> above = decode(output, 18, 1, threshold: 0.5000001);

      expect(atThreshold, hasLength(1));
      expect(atThreshold.single.confidence, closeTo(0.5, 1e-12));
      expect(above, isEmpty);
    });

    test('multiplies by objectness when the model has that channel', () {
      final Float32List output = channelsFirst(19, 1, <List<double>>[
        row19(320, 320, 64, 128, 0, logits: <int, double>{0: 0}),
      ]);

      expect(decode(output, 19, 1, threshold: 0.2), hasLength(1));
      expect(decode(output, 19, 1, threshold: 0.3), isEmpty);
      expect(
        decode(output, 19, 1, threshold: 0.2).single.confidence,
        closeTo(0.25, 1e-12),
      );
    });

    test('clamps boxes at every edge', () {
      final List<Detection> result = decode(
        channelsFirst(18, 2, <List<double>>[
          row18(10, 10, 64, 64, logits: <int, double>{0: ln4}),
          row18(630, 630, 64, 64, logits: <int, double>{1: ln4}),
        ]),
        18,
        2,
      );

      expect(result, hasLength(2));
      expect(
        result.map((Detection d) => d.box),
        containsAll(<Rect>[
          const Rect.fromLTRB(0, 0, 42, 42),
          const Rect.fromLTRB(598, 598, 640, 640),
        ]),
      );
    });

    test('drops zero-area boxes', () {
      final List<Detection> result = decode(
        channelsFirst(18, 2, <List<double>>[
          row18(320, 320, 0, 64, logits: <int, double>{0: ln4}),
          row18(200, 200, 64, 0, logits: <int, double>{0: ln4}),
        ]),
        18,
        2,
      );

      expect(result, isEmpty);
    });

    test('suppresses identical same-class boxes (IoU 1.0)', () {
      final List<Detection> result = decode(
        channelsFirst(18, 2, <List<double>>[
          row18(320, 320, 64, 64, logits: <int, double>{0: ln4}),
          row18(320, 320, 64, 64, logits: <int, double>{0: ln3}),
        ]),
        18,
        2,
      );

      expect(result, hasLength(1));
      expect(result.single.confidence, closeTo(0.8, 1e-9));
    });

    test('keeps boxes whose IoU is exactly the threshold (strict >)', () {
      // A = (0,0,100,100), B = (0,0,100,50): intersection 5000,
      // union 10000 → IoU exactly 0.5.
      final List<Detection> result = decode(
        channelsFirst(18, 2, <List<double>>[
          row18(50, 50, 100, 100, logits: <int, double>{0: ln4}),
          row18(50, 25, 100, 50, logits: <int, double>{0: ln3}),
        ]),
        18,
        2,
      );

      expect(result, hasLength(2));
      expect(result[0].confidence, closeTo(0.8, 1e-9));
      // ln(3) survives a Float32 round-trip, so sigmoid(ln3) lands within
      // ~4e-9 of 0.75; this test is about NMS, not float precision.
      expect(result[1].confidence, closeTo(0.75, 1e-6));
    });

    test('suppresses boxes whose IoU is above the threshold', () {
      // A = (0,0,100,100), B = (0,0,100,60): IoU 0.6 > 0.5.
      final List<Detection> result = decode(
        channelsFirst(18, 2, <List<double>>[
          row18(50, 50, 100, 100, logits: <int, double>{0: ln4}),
          row18(50, 30, 100, 60, logits: <int, double>{0: ln3}),
        ]),
        18,
        2,
      );

      expect(result, hasLength(1));
      expect(result.single.confidence, closeTo(0.8, 1e-9));
    });

    test('keeps overlapping boxes of different classes', () {
      final List<Detection> result = decode(
        channelsFirst(18, 2, <List<double>>[
          row18(320, 320, 64, 64, logits: <int, double>{0: ln4}),
          row18(320, 320, 64, 64, logits: <int, double>{1: ln3}),
        ]),
        18,
        2,
      );

      expect(result, hasLength(2));
      expect(
        result.map((Detection d) => d.label),
        unorderedEquals(<String>['Bed', 'Cabinet']),
      );
    });

    test('has no detection cap and sorts by confidence descending', () {
      final List<Detection> result = decode(
        channelsFirst(18, 3, <List<double>>[
          row18(100, 100, 40, 40, logits: <int, double>{0: 0.8473}),
          row18(320, 320, 40, 40, logits: <int, double>{1: 2.1972}),
          row18(540, 540, 40, 40, logits: <int, double>{2: ln4}),
        ]),
        18,
        3,
      );

      expect(result, hasLength(3));
      expect(result.map((Detection d) => d.label).toList(), <String>[
        'Cabinet',
        'Chair',
        'Bed',
      ]);
      expect(result[0].confidence, greaterThan(result[1].confidence));
      expect(result[1].confidence, greaterThan(result[2].confidence));
    });

    test('returns nothing when every score is below the threshold', () {
      final List<Detection> result = decode(
        channelsFirst(18, 1, <List<double>>[
          row18(320, 320, 64, 64, logits: <int, double>{0: -5}),
        ]),
        18,
        1,
        threshold: 0.9,
      );

      expect(result, isEmpty);
    });

    test('uses the fallback label when the class index has no label', () {
      // A 20-channel export decoded against the real 14 labels: the layout
      // falls back to "smaller dim is channels", leaving class slots 14 and
      // 15 unlabelled. Realistic anchor count, because the fallback heuristic
      // only works when anchors are much larger than channels.
      const int channels = 20;
      const int anchors = 8400;
      final Float32List output = Float32List(channels * anchors);
      output[0 * anchors] = 320; // cx
      output[1 * anchors] = 320; // cy
      output[2 * anchors] = 64; // w
      output[3 * anchors] = 64; // h
      for (int c = 4; c < channels; c++) {
        output[c * anchors] = lowLogit;
      }
      // Channel 18 is class index 14 (classStart = 4), one past the last
      // of the 14 labels, so the decoder must fall back.
      output[18 * anchors] = ln4;

      final List<Detection> result = decode(output, channels, anchors);

      expect(result, hasLength(1));
      expect(result.single.label, Copy.objectFallback);
      expect(result.single.distanceMeters, isNull);
    });

    test('reports left and right thirds from the box centre', () {
      final List<Detection> result = decode(
        channelsFirst(18, 2, <List<double>>[
          row18(100, 320, 40, 40, logits: <int, double>{0: ln4}),
          row18(550, 320, 40, 40, logits: <int, double>{1: ln3}),
        ]),
        18,
        2,
      );

      expect(result[0].direction, DetectionDirection.left);
      expect(result[1].direction, DetectionDirection.right);
    });

    test('handles an empty tensor', () {
      expect(decode(Float32List(0), 0, 0), isEmpty);
      expect(decode(Float32List(0), 18, 0), isEmpty);
    });
  });
}
