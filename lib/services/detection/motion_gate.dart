import 'dart:typed_data';

import '../../constants/detection.dart';
import 'frame_converter.dart';

/// Mean absolute difference between two gray planes, over the shorter
/// length. Empty input reads as no motion.
double meanAbsoluteDifference(Uint8List previous, Uint8List current) {
  final int length = previous.length < current.length
      ? previous.length
      : current.length;
  if (length == 0) {
    return 0;
  }
  int total = 0;
  for (int i = 0; i < length; i++) {
    total += (previous[i] - current[i]).abs();
  }
  return total / length;
}

/// Samples the luma plane down to a [size] × [size] gray image.
///
/// Rows are addressed by [FramePlanes.yBytesPerRow] and columns by
/// [FramePlanes.width], so stride padding is never read and no full
/// resize is performed.
Uint8List downsampleGray(
  FramePlanes planes, {
  int size = DetectionConstants.motionSize,
}) {
  final Uint8List gray = Uint8List(size * size);
  for (int dy = 0; dy < size; dy++) {
    final int sourceRow = dy * planes.height ~/ size;
    final int rowStart = sourceRow * planes.yBytesPerRow;
    final int outputStart = dy * size;
    for (int dx = 0; dx < size; dx++) {
      final int sourceColumn = dx * planes.width ~/ size;
      gray[outputStart + dx] = planes.y[rowStart + sourceColumn];
    }
  }
  return gray;
}
