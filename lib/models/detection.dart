import 'dart:ui' show Rect;

/// Which third of the frame a detection's box centre sits in, phrased by
/// the announcer via `Copy.directionLeft` / `directionAhead` /
/// `directionRight`.
enum DetectionDirection { left, ahead, right }

/// One detected object, screen-ready: the raw geometry lives in
/// **model space** (the 640×640 letterboxed input), never in view or
/// frame pixels, so distance and direction are device-independent
/// (plan "Decisions"; `p2-global-constraints.md`).
class Detection {
  const Detection({
    required this.label,
    required this.confidence,
    required this.box,
    required this.distanceMeters,
    required this.direction,
  });

  /// Class label as spoken (already an English proper-noun from
  /// `labelsV5.txt`), or `Copy.objectFallback` when the model's class
  /// index had no label.
  final String label;

  /// Post-sigmoid, post-NMS confidence of this detection.
  final double confidence;

  /// Bounding box in model space (0..640), clamped to the model input
  /// by the decoder (plan Task 2).
  final Rect box;

  /// Width-based distance estimate in metres; `null` for an unknown
  /// label (plan Task 3).
  final double? distanceMeters;

  /// Which third of the frame [box] sits in (see [directionFor]).
  final DetectionDirection direction;
}

/// Splits the model-space frame into thirds by the box centre:
/// `< width/3` is [DetectionDirection.left], `> 2*width/3` is
/// [DetectionDirection.right], and the exact boundaries fall through to
/// [DetectionDirection.ahead] — the comparison is strict, and the
/// boundaries are pinned by `test/detection_constants_test.dart`.
DetectionDirection directionFor(Rect box, {double width = 640}) {
  final double centre = box.center.dx;
  if (centre < width / 3) {
    return DetectionDirection.left;
  }
  if (centre > 2 * width / 3) {
    return DetectionDirection.right;
  }
  return DetectionDirection.ahead;
}
