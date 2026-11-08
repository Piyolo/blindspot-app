import 'dart:typed_data';

import 'package:blindspot_app/services/detection/frame_converter.dart';
import 'package:blindspot_app/services/detection/motion_gate.dart';
import 'package:flutter_test/flutter_test.dart';

FramePlanes planesFromY(
  Uint8List y, {
  required int width,
  required int height,
  required int stride,
}) {
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

void main() {
  group('meanAbsoluteDifference', () {
    test('identical planes read zero', () {
      final Uint8List plane = Uint8List.fromList(<int>[0, 42, 255, 17]);
      expect(meanAbsoluteDifference(plane, Uint8List.fromList(plane)), 0);
    });

    test('averages the absolute per-sample differences', () {
      expect(
        meanAbsoluteDifference(
          Uint8List.fromList(<int>[0, 10, 20]),
          Uint8List.fromList(<int>[10, 10, 0]),
        ),
        closeTo(10, 1e-9),
      );
    });

    test('empty planes read zero', () {
      expect(meanAbsoluteDifference(Uint8List(0), Uint8List(0)), 0);
    });

    test('a uniform 255 jump reads 255', () {
      final Uint8List current = Uint8List(16)..fillRange(0, 16, 255);
      expect(meanAbsoluteDifference(Uint8List(16), current), 255);
    });
  });

  group('downsampleGray', () {
    test('samples every second column of a 224-wide plane', () {
      const int width = 224;
      const int height = 224;
      const int stride = width + 32;
      final Uint8List y = Uint8List(stride * height);
      for (int row = 0; row < height; row++) {
        for (int column = 0; column < width; column++) {
          y[row * stride + column] = column;
        }
        y.fillRange(row * stride + width, row * stride + stride, 255);
      }

      final Uint8List gray = downsampleGray(
        planesFromY(y, width: width, height: height, stride: stride),
      );

      expect(gray, hasLength(112 * 112));
      expect(gray[0], 0);
      expect(gray[1], 2);
      expect(gray[111], 222);
      expect(gray[112], 0, reason: 'second sampled row starts over');
      expect(gray[112 + 111], 222);
      expect(gray, isNot(contains(255)), reason: 'row padding never sampled');
    });

    test('addresses rows by stride, not by width', () {
      const int width = 64;
      const int height = 224;
      const int stride = width + 16;
      final Uint8List y = Uint8List(stride * height);
      for (int row = 0; row < height; row++) {
        y.fillRange(row * stride, row * stride + width, row);
      }

      final Uint8List gray = downsampleGray(
        planesFromY(y, width: width, height: height, stride: stride),
      );

      // 224 rows collapse to 112 samples: rows 0, 2, 4, ...
      expect(gray[0], 0);
      expect(gray[112], 2);
      expect(gray[112 * 111], 222);
    });

    test('honours a custom output size', () {
      const int width = 224;
      const int height = 224;
      final Uint8List y = Uint8List(width * height);
      for (int row = 0; row < height; row++) {
        for (int column = 0; column < width; column++) {
          y[row * width + column] = column;
        }
      }

      final Uint8List gray = downsampleGray(
        planesFromY(y, width: width, height: height, stride: width),
        size: 4,
      );

      expect(gray, hasLength(16));
      expect(gray.sublist(0, 4), <int>[0, 56, 112, 168]);
      expect(gray.sublist(4, 8), <int>[0, 56, 112, 168]);
    });
  });
}
