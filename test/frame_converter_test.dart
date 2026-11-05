import 'dart:typed_data';

import 'package:blindspot_app/services/detection/frame_converter.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(List<int> values) => Uint8List.fromList(values);

/// A neutral-chroma YUV420 frame: U = V = 128, so RGB == Y and every
/// channel of a decoded pixel carries the same value.
FramePlanes grayPlanes({
  required int width,
  required int height,
  required List<int> luma,
  int rotation = 0,
}) {
  final int chromaWidth = (width + 1) >> 1;
  final int chromaHeight = (height + 1) >> 1;
  final int chromaLength = chromaWidth * chromaHeight;
  return FramePlanes(
    format: FrameFormat.yuv420,
    y: bytes(luma),
    u: Uint8List(chromaLength)..fillRange(0, chromaLength, 128),
    v: Uint8List(chromaLength)..fillRange(0, chromaLength, 128),
    width: width,
    height: height,
    yBytesPerRow: width,
    uvBytesPerRow: chromaWidth,
    uvPixelStride: 1,
    rotationDegrees: rotation,
  );
}

/// One channel of a decoded, letterboxed pixel.
double at(ConvertedFrame frame, int x, int y, int channel) =>
    frame.input[(y * frame.geometry.outW + x) * 3 + channel];

void expectGray(ConvertedFrame frame, int x, int y, int luma) {
  for (int channel = 0; channel < 3; channel++) {
    expect(
      at(frame, x, y, channel),
      closeTo(luma / 255.0, 1e-6),
      reason: 'pixel ($x,$y) channel $channel',
    );
  }
}

/// Builds a 4x2 frame whose luma is `[1,2,3,4, 5,6,7,8]`, used by the
/// format/stride comparisons.
FramePlanes rowPlanes({
  required FrameFormat format,
  required Uint8List y,
  required Uint8List chromaA,
  required Uint8List chromaB,
  int yBytesPerRow = 4,
  int uvBytesPerRow = 2,
  int uvPixelStride = 1,
}) {
  return FramePlanes(
    format: format,
    y: y,
    u: format == FrameFormat.yuv420 ? chromaA : null,
    v: format == FrameFormat.yuv420 ? chromaB : null,
    vu: format == FrameFormat.nv21 ? chromaA : null,
    width: 4,
    height: 2,
    yBytesPerRow: yBytesPerRow,
    uvBytesPerRow: uvBytesPerRow,
    uvPixelStride: uvPixelStride,
    rotationDegrees: 0,
  );
}

void main() {
  group('BT.601 conversion', () {
    test('a 2x2 frame decodes to exact BT.601 floats', () {
      final ConvertedFrame frame = convertFrame(
        FramePlanes(
          format: FrameFormat.yuv420,
          y: bytes(<int>[0, 64, 160, 255]),
          u: bytes(<int>[90]),
          v: bytes(<int>[200]),
          width: 2,
          height: 2,
          yBytesPerRow: 2,
          uvBytesPerRow: 1,
          uvPixelStride: 1,
          rotationDegrees: 0,
        ),
        size: 2,
      );

      expect(frame.input.length, 12);
      expect(frame.geometry.scale, 1.0);
      expect(frame.geometry.padX, 0.0);
      expect(frame.geometry.padY, 0.0);
      expect(frame.geometry.outW, 2);
      expect(frame.geometry.outH, 2);

      // U-128 = -38, V-128 = 72:
      //   r = y + 98.690760, g = y - 37.426018, b = y - 65.832948.
      // y=0 and y=64 clamp g/b at 0; y=160 and y=255 clamp r at 255.
      expect(at(frame, 0, 0, 0), closeTo(98.690760 / 255, 1e-6));
      expect(at(frame, 0, 0, 1), 0.0);
      expect(at(frame, 0, 0, 2), 0.0);

      expect(at(frame, 1, 0, 0), closeTo(162.690760 / 255, 1e-6));
      expect(at(frame, 1, 0, 1), closeTo(26.573982 / 255, 1e-6));
      expect(at(frame, 1, 0, 2), 0.0);

      expect(at(frame, 0, 1, 0), 1.0);
      expect(at(frame, 0, 1, 1), closeTo(122.573982 / 255, 1e-6));
      expect(at(frame, 0, 1, 2), closeTo(94.167052 / 255, 1e-6));

      expect(at(frame, 1, 1, 0), 1.0);
      expect(at(frame, 1, 1, 1), closeTo(217.573982 / 255, 1e-6));
      expect(at(frame, 1, 1, 2), closeTo(189.167052 / 255, 1e-6));
    });
  });

  group('formats', () {
    test('nv21 and yuv420 produce identical output', () {
      final ConvertedFrame planar = convertFrame(
        rowPlanes(
          format: FrameFormat.yuv420,
          y: bytes(<int>[10, 20, 30, 40, 50, 60, 70, 80]),
          chromaA: bytes(<int>[90, 200]),
          chromaB: bytes(<int>[200, 90]),
        ),
        size: 4,
      );
      // NV21 interleaves V then U per chroma sample:
      // sample 0 (V=200, U=90), sample 1 (V=90, U=200).
      final ConvertedFrame nv21 = convertFrame(
        rowPlanes(
          format: FrameFormat.nv21,
          y: bytes(<int>[10, 20, 30, 40, 50, 60, 70, 80]),
          chromaA: bytes(<int>[200, 90, 90, 200]),
          chromaB: Uint8List(0),
          uvBytesPerRow: 4,
          uvPixelStride: 2,
        ),
        size: 4,
      );

      expect(planar.input.length, nv21.input.length);
      expect(nv21.input, orderedEquals(planar.input));
    });

    test('reads interleaved chroma with pixelStride 2', () {
      // CameraX hands U and V as two views over one interleaved buffer
      // [U0, V0, U1, V1]; the V view starts one byte in.
      final Uint8List interleaved = bytes(<int>[90, 200, 200, 90]);
      final ConvertedFrame interleavedFrame = convertFrame(
        rowPlanes(
          format: FrameFormat.yuv420,
          y: bytes(<int>[10, 20, 30, 40, 50, 60, 70, 80]),
          chromaA: interleaved,
          chromaB: Uint8List.sublistView(interleaved, 1),
          uvBytesPerRow: 4,
          uvPixelStride: 2,
        ),
        size: 4,
      );
      final ConvertedFrame planar = convertFrame(
        rowPlanes(
          format: FrameFormat.yuv420,
          y: bytes(<int>[10, 20, 30, 40, 50, 60, 70, 80]),
          chromaA: bytes(<int>[90, 200]),
          chromaB: bytes(<int>[200, 90]),
        ),
        size: 4,
      );

      expect(interleavedFrame.input, orderedEquals(planar.input));
    });

    test('de-strides rows with stride > width', () {
      final ConvertedFrame contiguous = convertFrame(
        rowPlanes(
          format: FrameFormat.yuv420,
          y: bytes(<int>[10, 20, 30, 40, 50, 60, 70, 80]),
          chromaA: bytes(<int>[90, 200]),
          chromaB: bytes(<int>[200, 90]),
        ),
        size: 4,
      );
      final ConvertedFrame strided = convertFrame(
        rowPlanes(
          format: FrameFormat.yuv420,
          y: bytes(<int>[10, 20, 30, 40, 99, 99, 50, 60, 70, 80, 99, 99]),
          chromaA: bytes(<int>[90, 200, 99, 99]),
          chromaB: bytes(<int>[200, 90, 99, 99]),
          yBytesPerRow: 6,
          uvBytesPerRow: 4,
        ),
        size: 4,
      );

      expect(strided.input, orderedEquals(contiguous.input));
    });
  });

  group('rotation', () {
    test('rotates 90, 180 and 270 degrees clockwise', () {
      // Source:  10 20     90° CW:  30 10    180°:  40 30    270° CW:  20 40
      //          30 40              40 20            20 10             10 30
      const List<List<List<int>>> expected = <List<List<int>>>[
        <List<int>>[
          <int>[10, 20],
          <int>[30, 40],
        ],
        <List<int>>[
          <int>[30, 10],
          <int>[40, 20],
        ],
        <List<int>>[
          <int>[40, 30],
          <int>[20, 10],
        ],
        <List<int>>[
          <int>[20, 40],
          <int>[10, 30],
        ],
      ];
      const List<int> rotations = <int>[0, 90, 180, 270];

      for (int r = 0; r < rotations.length; r++) {
        final ConvertedFrame frame = convertFrame(
          grayPlanes(
            width: 2,
            height: 2,
            luma: <int>[10, 20, 30, 40],
            rotation: rotations[r],
          ),
          size: 2,
        );
        for (int y = 0; y < 2; y++) {
          for (int x = 0; x < 2; x++) {
            expectGray(frame, x, y, expected[r][y][x]);
          }
        }
      }
    });

    test('rotation swaps the letterbox axes', () {
      // 4x2 source rotated 90° CW is 2x4: rows [5,1] [6,2] [7,3] [8,4].
      // Into a 4x4 output at scale 1 that leaves one pad column each side.
      final ConvertedFrame frame = convertFrame(
        grayPlanes(
          width: 4,
          height: 2,
          luma: <int>[1, 2, 3, 4, 5, 6, 7, 8],
          rotation: 90,
        ),
        size: 4,
      );

      expect(frame.geometry.scale, 1.0);
      expect(frame.geometry.padX, 1.0);
      expect(frame.geometry.padY, 0.0);
      expect(frame.geometry.outW, 4);
      expect(frame.geometry.outH, 4);

      expectGray(frame, 0, 0, 114); // pad
      expectGray(frame, 1, 0, 5);
      expectGray(frame, 2, 0, 1);
      expectGray(frame, 3, 0, 114); // pad
      expectGray(frame, 1, 3, 8);
      expectGray(frame, 2, 3, 4);
    });
  });

  group('letterbox', () {
    test('pads with 114 and keeps the source rows contiguous', () {
      final ConvertedFrame frame = convertFrame(
        grayPlanes(width: 4, height: 2, luma: <int>[1, 2, 3, 4, 5, 6, 7, 8]),
        size: 4,
      );

      expect(frame.geometry.scale, 1.0);
      expect(frame.geometry.padX, 0.0);
      expect(frame.geometry.padY, 1.0);

      for (int x = 0; x < 4; x++) {
        expectGray(frame, x, 0, 114);
        expectGray(frame, x, 3, 114);
      }
      for (int x = 0; x < 4; x++) {
        expectGray(frame, x, 1, x + 1);
        expectGray(frame, x, 2, x + 5);
      }
    });

    test('pad value is configurable', () {
      final ConvertedFrame frame = convertFrame(
        grayPlanes(width: 4, height: 2, luma: <int>[1, 2, 3, 4, 5, 6, 7, 8]),
        size: 4,
        pad: 0,
      );

      expectGray(frame, 0, 0, 0);
      expectGray(frame, 3, 3, 0);
    });

    test('the default output is 640x640x3', () {
      final ConvertedFrame frame = convertFrame(
        grayPlanes(width: 2, height: 2, luma: <int>[10, 20, 30, 40]),
      );

      expect(frame.geometry.outW, 640);
      expect(frame.geometry.outH, 640);
      expect(frame.geometry.scale, 320.0);
      expect(frame.geometry.padX, 0.0);
      expect(frame.geometry.padY, 0.0);
      expect(frame.input.length, 640 * 640 * 3);
      expectGray(frame, 639, 639, 40);
    });
  });

  group('robustness', () {
    test('handles odd dimensions without a RangeError', () {
      final ConvertedFrame frame = convertFrame(
        grayPlanes(width: 3, height: 3, luma: <int>[0, 1, 2, 3, 4, 5, 6, 7, 8]),
        size: 3,
      );

      expect(frame.input.length, 27);
      expect(frame.geometry.scale, 1.0);
      expectGray(frame, 0, 0, 0);
      expectGray(frame, 2, 2, 8);
    });

    test('rejects a rotation that is not a right angle', () {
      expect(
        () => convertFrame(
          grayPlanes(
            width: 2,
            height: 2,
            luma: <int>[1, 2, 3, 4],
            rotation: 45,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('rejects missing chroma planes', () {
      expect(
        () => convertFrame(
          FramePlanes(
            format: FrameFormat.yuv420,
            y: bytes(<int>[1, 2, 3, 4]),
            width: 2,
            height: 2,
            yBytesPerRow: 2,
            uvBytesPerRow: 1,
            uvPixelStride: 1,
            rotationDegrees: 0,
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => convertFrame(
          FramePlanes(
            format: FrameFormat.nv21,
            y: bytes(<int>[1, 2, 3, 4]),
            width: 2,
            height: 2,
            yBytesPerRow: 2,
            uvBytesPerRow: 2,
            uvPixelStride: 2,
            rotationDegrees: 0,
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
