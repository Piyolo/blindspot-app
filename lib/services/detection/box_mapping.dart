import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:flutter/painting.dart' show BoxFit;

import '../../constants/detection.dart';

/// Maps a model-space box (0..640, letterboxed) onto the preview.
///
/// Two transforms compose:
/// 1. invert the converter's letterbox — `x = (modelX - padX) / scale`,
///    with the 640-square pads from [DetectionConstants.inputSize] and
///    the frame's own dimensions;
/// 2. fit the frame into the view with [fit] — `s = max(viewW/frameW,
///    viewH/frameH)` for [BoxFit.cover] (negative offsets when cropping)
///    or `min` for [BoxFit.contain] (positive padding).
///
/// A non-positive frame or view (the first layout pass) maps to
/// [Rect.zero] so no NaN reaches a painter.
Rect mapBoxToView({
  required Rect modelBox,
  required Size frameSize,
  required Size viewSize,
  BoxFit fit = BoxFit.cover,
}) {
  if (frameSize.width <= 0 ||
      frameSize.height <= 0 ||
      viewSize.width <= 0 ||
      viewSize.height <= 0) {
    return Rect.zero;
  }

  final double input = DetectionConstants.inputSize.toDouble();
  final double letterboxScale = math.min(
    input / frameSize.width,
    input / frameSize.height,
  );
  final double padX = (input - frameSize.width * letterboxScale) / 2;
  final double padY = (input - frameSize.height * letterboxScale) / 2;

  final double fitScale = fit == BoxFit.contain
      ? math.min(
          viewSize.width / frameSize.width,
          viewSize.height / frameSize.height,
        )
      : math.max(
          viewSize.width / frameSize.width,
          viewSize.height / frameSize.height,
        );
  final double offsetX = (viewSize.width - frameSize.width * fitScale) / 2;
  final double offsetY = (viewSize.height - frameSize.height * fitScale) / 2;

  final double scale = fitScale / letterboxScale;
  return Rect.fromLTRB(
    (modelBox.left - padX) * scale + offsetX,
    (modelBox.top - padY) * scale + offsetY,
    (modelBox.right - padX) * scale + offsetX,
    (modelBox.bottom - padY) * scale + offsetY,
  );
}
