import 'dart:math' as math;
import 'dart:typed_data';

/// Plane layout of a camera frame.
enum FrameFormat {
  /// Three planes: Y, then U, then V (CameraX's `YUV_420_888`). The U and
  /// V views may interleave through [FramePlanes.uvPixelStride] == 2.
  yuv420,

  /// One luma plane followed by interleaved V,U chroma (NV21).
  nv21,
}

/// The raw planes of one camera frame, before conversion.
///
/// Rows are addressed by stride, never by `width`: CameraX reports
/// `bytesPerRow >= width` for the luma plane and may pad every chroma row
/// too (plan "Platform facts"). The frame is never assumed contiguous.
class FramePlanes {
  const FramePlanes({
    required this.format,
    required this.y,
    this.u,
    this.v,
    this.vu,
    required this.width,
    required this.height,
    required this.yBytesPerRow,
    required this.uvBytesPerRow,
    required this.uvPixelStride,
    required this.rotationDegrees,
  });

  /// Which of the two supported layouts these planes use.
  final FrameFormat format;

  /// Luma plane. Its first `yBytesPerRow * height` bytes are the image;
  /// an NV21 frame's single plane may carry chroma bytes after that
  /// region, which is why [vu] can be a view into the same buffer.
  final Uint8List y;

  /// U plane (yuv420 only).
  final Uint8List? u;

  /// V plane (yuv420 only).
  final Uint8List? v;

  /// Interleaved V,U chroma region (nv21 only), starting at the byte
  /// after the luma region in the camera's planar buffer: sample `i` is
  /// `V = vu[uvPixelStride * i]`, `U = vu[uvPixelStride * i + 1]`.
  final Uint8List? vu;

  /// Image width in pixels (the Y plane's logical width, not its stride).
  final int width;

  /// Image height in pixels.
  final int height;

  /// Number of bytes per luma row (`>= width`).
  final int yBytesPerRow;

  /// Number of bytes per chroma row (`>= chromaWidth * uvPixelStride`).
  final int uvBytesPerRow;

  /// Distance in bytes between adjacent chroma samples: 1 for planar
  /// U/V views, 2 for interleaved (NV21 or CameraX's shared buffer).
  final int uvPixelStride;

  /// Clockwise rotation to apply to the image before letterboxing.
  final int rotationDegrees;
}

/// Where the source image landed in the square model input.
///
/// A destination pixel `(dx, dy)` samples the rotated source at
/// `((dx - padX) / scale, (dy - padY) / scale)` with nearest-neighbour
/// rounding; Task 11 inverts exactly this geometry to map detections back
/// onto the preview.
class LetterboxGeometry {
  const LetterboxGeometry({
    required this.scale,
    required this.padX,
    required this.padY,
    required this.outW,
    required this.outH,
  });

  /// `min(outW / srcW, outH / srcH)`.
  final double scale;

  /// Left padding of the scaled image, in output pixels.
  final double padX;

  /// Top padding of the scaled image, in output pixels.
  final double padY;

  /// Output width (the model input side).
  final int outW;

  /// Output height (the model input side).
  final int outH;
}

/// A model-ready frame: NHWC float32 in 0..1, plus the geometry that
/// produced it.
class ConvertedFrame {
  const ConvertedFrame({required this.input, required this.geometry});

  /// `outH * outW * 3` floats, each channel divided by 255.
  final Float32List input;

  /// Letterbox transform applied after rotation.
  final LetterboxGeometry geometry;
}

/// Converts one camera frame into the YOLOv8 input tensor.
///
/// Pipeline: de-stride each plane, decode BT.601 full-range RGB, rotate
/// clockwise by [FramePlanes.rotationDegrees], letterbox with [size] and
/// [pad], sample nearest-neighbour, then divide by 255 (plan Task 4).
///
/// Pure Dart: this runs unchanged on the main isolate in tests and inside
/// the conversion isolate in production. Throws [ArgumentError] for a
/// malformed frame (missing planes, short buffers, an unsupported
/// rotation) rather than producing a garbage tensor.
ConvertedFrame convertFrame(
  FramePlanes planes, {
  int size = 640,
  int pad = 114,
}) {
  if (size <= 0) {
    throw ArgumentError.value(size, 'size', 'must be positive');
  }
  if (pad < 0 || pad > 255) {
    throw ArgumentError.value(pad, 'pad', 'must be 0..255');
  }
  final int rotation = planes.rotationDegrees;
  if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
    throw ArgumentError.value(
      rotation,
      'rotationDegrees',
      'must be 0, 90, 180 or 270',
    );
  }
  final int width = planes.width;
  final int height = planes.height;
  if (width <= 0 || height <= 0) {
    throw ArgumentError('frame must be at least 1x1, got ${width}x$height');
  }
  if (planes.yBytesPerRow < width) {
    throw ArgumentError.value(
      planes.yBytesPerRow,
      'yBytesPerRow',
      'must be >= the frame width ($width)',
    );
  }
  if (planes.uvBytesPerRow <= 0 || planes.uvPixelStride <= 0) {
    throw ArgumentError('chroma strides must be positive');
  }

  final int chromaWidth = (width + 1) >> 1;
  final int chromaHeight = (height + 1) >> 1;
  final int requiredY = planes.yBytesPerRow * height;
  if (planes.y.length < requiredY) {
    throw ArgumentError(
      'luma plane has ${planes.y.length} bytes, needs $requiredY',
    );
  }
  // Last addressed byte + 1: NV21 reads the V byte and the U byte after
  // it, planar U/V read one byte per sample.
  final int requiredChroma =
      (chromaHeight - 1) * planes.uvBytesPerRow +
      (chromaWidth - 1) * planes.uvPixelStride +
      (planes.format == FrameFormat.nv21 ? 2 : 1);

  final Uint8List? uPlane = planes.u;
  final Uint8List? vPlane = planes.v;
  final Uint8List? vuPlane = planes.vu;
  final bool nv21 = planes.format == FrameFormat.nv21;
  if (nv21) {
    if (vuPlane == null) {
      throw ArgumentError('nv21 frames require the interleaved vu plane');
    }
    if (vuPlane.length < requiredChroma) {
      throw ArgumentError(
        'vu plane has ${vuPlane.length} bytes, needs $requiredChroma',
      );
    }
  } else {
    if (uPlane == null || vPlane == null) {
      throw ArgumentError('yuv420 frames require the u and v planes');
    }
    if (uPlane.length < requiredChroma || vPlane.length < requiredChroma) {
      throw ArgumentError('u/v planes are shorter than $requiredChroma bytes');
    }
  }
  final Uint8List chromaU = nv21 ? vuPlane! : uPlane!;
  final Uint8List chromaV = nv21 ? vuPlane! : vPlane!;

  final bool rotated = rotation == 90 || rotation == 270;
  final int srcW = rotated ? height : width;
  final int srcH = rotated ? width : height;
  final double scale = math.min(size / srcW, size / srcH);
  final double padX = (size - srcW * scale) / 2.0;
  final double padY = (size - srcH * scale) / 2.0;

  final Float32List input = Float32List(size * size * 3);
  input.fillRange(0, input.length, pad / 255.0);

  // Destination column -> rotated-source column, -1 for a padding column.
  final Int32List sourceX = Int32List(size);
  for (int dx = 0; dx < size; dx++) {
    final int sx = ((dx - padX) / scale).floor();
    sourceX[dx] = sx >= 0 && sx < srcW ? sx : -1;
  }

  for (int dy = 0; dy < size; dy++) {
    final int sy = ((dy - padY) / scale).floor();
    if (sy < 0 || sy >= srcH) {
      continue;
    }
    final int outputRow = dy * size * 3;
    for (int dx = 0; dx < size; dx++) {
      final int sx = sourceX[dx];
      if (sx < 0) {
        continue;
      }

      // Invert the clockwise rotation: rotated (sx, sy) was source
      // (x, y) before the image was turned.
      final int srcPixelX;
      final int srcPixelY;
      if (rotation == 0) {
        srcPixelX = sx;
        srcPixelY = sy;
      } else if (rotation == 90) {
        srcPixelX = sy;
        srcPixelY = height - 1 - sx;
      } else if (rotation == 180) {
        srcPixelX = width - 1 - sx;
        srcPixelY = height - 1 - sy;
      } else {
        srcPixelX = width - 1 - sy;
        srcPixelY = sx;
      }

      final int luma = planes.y[srcPixelY * planes.yBytesPerRow + srcPixelX];
      final int uvIndex =
          (srcPixelY >> 1) * planes.uvBytesPerRow +
          (srcPixelX >> 1) * planes.uvPixelStride;
      final int u;
      final int v;
      if (nv21) {
        v = chromaU[uvIndex];
        u = chromaU[uvIndex + 1];
      } else {
        u = chromaU[uvIndex];
        v = chromaV[uvIndex];
      }

      // Donor's BT.601 full-range formula (LocalYoloDetector.kt neighbours
      // in the old app), clamped to 0..255.
      final double uf = u - 128.0;
      final double vf = v - 128.0;
      final int offset = outputRow + dx * 3;
      input[offset] = _clamp255(luma + 1.370705 * vf) / 255.0;
      input[offset + 1] =
          _clamp255(luma - 0.337633 * uf - 0.698001 * vf) / 255.0;
      input[offset + 2] = _clamp255(luma + 1.732446 * uf) / 255.0;
    }
  }

  return ConvertedFrame(
    input: input,
    geometry: LetterboxGeometry(
      scale: scale,
      padX: padX,
      padY: padY,
      outW: size,
      outH: size,
    ),
  );
}

double _clamp255(double value) {
  if (value <= 0) {
    return 0;
  }
  if (value >= 255) {
    return 255;
  }
  return value;
}
