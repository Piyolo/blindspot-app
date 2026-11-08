import 'package:flutter/material.dart';

import '../models/detection.dart';
import '../services/detection/box_mapping.dart';
import '../theme/tokens.dart';

/// Draws one stroked rectangle per detection over the preview.
///
/// Sizes are passed in rather than measured: [frameSize] is the rotated
/// camera frame and [viewSize] is the preview area from its LayoutBuilder.
/// The overlay never intercepts touches; it is a sighted helper layered
/// over the preview.
class BboxOverlay extends StatelessWidget {
  const BboxOverlay({
    super.key,
    required this.detections,
    required this.frameSize,
    required this.viewSize,
  });

  final List<Detection> detections;
  final Size frameSize;
  final Size viewSize;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: BboxPainter(
          detections: detections,
          frameSize: frameSize,
          viewSize: viewSize,
        ),
        size: viewSize,
      ),
    );
  }
}

class BboxPainter extends CustomPainter {
  BboxPainter({
    required this.detections,
    required this.frameSize,
    required this.viewSize,
  });

  final List<Detection> detections;
  final Size frameSize;
  final Size viewSize;

  /// One path per mapped detection; boxes with no area after mapping are
  /// skipped (the decoder can emit zero-width boxes from tied anchors).
  List<Path> get paths {
    final List<Path> result = <Path>[];
    for (final Detection detection in detections) {
      final Rect rect = mapBoxToView(
        modelBox: detection.box,
        frameSize: frameSize,
        viewSize: viewSize,
      );
      if (rect.width <= 0 || rect.height <= 0) {
        continue;
      }
      result.add(Path()..addRect(rect));
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.cream;
    for (final Path path in paths) {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(BboxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.frameSize != frameSize ||
        oldDelegate.viewSize != viewSize;
  }
}
