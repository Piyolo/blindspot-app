import 'dart:ui' show Size;

import 'frame_converter.dart';

/// One camera frame, as the engine receives it.
class CameraFrame {
  const CameraFrame({required this.planes, required this.capturedAt});

  final FramePlanes planes;

  /// When the camera produced the frame.
  final DateTime capturedAt;
}

/// The seam between the engine and the `camera` plugin.
///
/// Implementations hand frames to [start]'s callback as they arrive; the
/// engine drops them rather than queueing, so the source never needs its
/// own backpressure.
abstract class CameraSource {
  /// Throws a platform exception when the camera cannot be opened.
  Future<void> initialize();

  Future<void> start(void Function(CameraFrame) onFrame);

  Future<void> stop();

  Future<void> dispose();

  bool get hasTorch;

  Future<void> setTorch(bool on);

  /// Rotated frame size, for mapping detections onto the preview.
  Size? get frameSize;
}
