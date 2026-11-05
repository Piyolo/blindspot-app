import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../../constants/copy.dart';
import '../../constants/detection.dart';
import '../../models/detection.dart';
import 'depth_estimator.dart';

/// Which axis of the raw output tensor carries the per-anchor channels.
enum YoloLayout { channelsFirst, anchorsFirst }

/// Runtime shape discovery, ported from `LocalYoloDetector.kt:44-62`.
///
/// The shipped model exports `[1, 18, 8400]` (4 box + 14 classes, no
/// objectness), but the donor also accepted the transposed layout and an
/// objectness variant, so the decoder keeps supporting all three:
/// a dimension that is `classCount + 4` or `classCount + 5` is the
/// channel axis; otherwise the smaller dimension is treated as channels.
YoloLayout detectLayout(int dim1, int dim2, int classCount) {
  if (dim1 - 4 == classCount || dim1 - 5 == classCount) {
    return YoloLayout.channelsFirst;
  }
  if (dim2 - 4 == classCount || dim2 - 5 == classCount) {
    return YoloLayout.anchorsFirst;
  }
  return dim1 < dim2 ? YoloLayout.channelsFirst : YoloLayout.anchorsFirst;
}

/// Decodes one raw YOLOv8 tensor into [Detection]s.
///
/// Faithful port of `LocalYoloDetector.kt:101-187`: normalised-coordinate
/// heuristic, sigmoid on the class logits (always — the donor does this
/// even for a model that already outputs probabilities), optional
/// objectness multiply, inclusive confidence threshold, strict-`>` IoU
/// per-class NMS, confidence-descending order and no detection cap.
///
/// Geometry stays in model space; [estimateDistanceMeters] therefore
/// receives the model-space box width and produces a device-independent
/// estimate (plan "Decisions").
List<Detection> postprocessYolo({
  required Float32List output,
  required int dim1,
  required int dim2,
  required List<String> labels,
  required double confidenceThreshold,
  double iouThreshold = DetectionConstants.nmsIou,
}) {
  if (dim1 <= 0 || dim2 <= 0 || labels.isEmpty) {
    return const <Detection>[];
  }
  assert(
    output.length == dim1 * dim2,
    'postprocessYolo: tensor has ${output.length} values, '
    'expected ${dim1 * dim2} ($dim1 x $dim2)',
  );

  final YoloLayout layout = detectLayout(dim1, dim2, labels.length);
  final int channels = layout == YoloLayout.channelsFirst ? dim1 : dim2;
  final int anchors = layout == YoloLayout.channelsFirst ? dim2 : dim1;
  final bool hasObjectness = channels - 5 == labels.length;
  final int classStart = hasObjectness ? 5 : 4;
  final int modelClasses = channels - classStart;
  if (modelClasses <= 0 || output.length < channels * anchors) {
    return const <Detection>[];
  }

  double valueAt(int anchor, int channel) => layout == YoloLayout.channelsFirst
      ? output[channel * anchors + anchor]
      : output[anchor * channels + channel];

  final List<_Candidate> candidates = <_Candidate>[];
  for (int anchor = 0; anchor < anchors; anchor++) {
    double cx = valueAt(anchor, 0);
    double cy = valueAt(anchor, 1);
    double w = valueAt(anchor, 2);
    double h = valueAt(anchor, 3);
    // The export may emit normalised corners; the donor scales them when
    // every value is plausibly a 0..2 fraction.
    if (cx <= 2 && cy <= 2 && w <= 2 && h <= 2) {
      cx *= DetectionConstants.inputSize;
      cy *= DetectionConstants.inputSize;
      w *= DetectionConstants.inputSize;
      h *= DetectionConstants.inputSize;
    }
    final double x1 = math.max(0, cx - w / 2);
    final double y1 = math.max(0, cy - h / 2);
    final double x2 = math.min(
      DetectionConstants.inputSize.toDouble(),
      cx + w / 2,
    );
    final double y2 = math.min(
      DetectionConstants.inputSize.toDouble(),
      cy + h / 2,
    );
    if (x2 <= x1 || y2 <= y1) {
      continue;
    }

    int bestClass = 0;
    double bestScore = -1;
    for (int c = 0; c < modelClasses; c++) {
      final double score = _sigmoid(valueAt(anchor, classStart + c));
      if (score > bestScore) {
        bestScore = score;
        bestClass = c;
      }
    }
    if (hasObjectness) {
      bestScore *= _sigmoid(valueAt(anchor, 4));
    }
    if (bestScore < confidenceThreshold) {
      continue;
    }
    candidates.add(
      _Candidate(
        classIndex: bestClass,
        score: bestScore,
        box: Rect.fromLTRB(x1, y1, x2, y2),
      ),
    );
  }

  candidates.sort((_Candidate a, _Candidate b) => b.score.compareTo(a.score));
  final List<_Candidate> kept = <_Candidate>[];
  for (final _Candidate candidate in candidates) {
    bool suppressed = false;
    for (final _Candidate accepted in kept) {
      if (accepted.classIndex == candidate.classIndex &&
          _intersectionOverUnion(accepted.box, candidate.box) > iouThreshold) {
        suppressed = true;
        break;
      }
    }
    if (!suppressed) {
      kept.add(candidate);
    }
  }

  return kept
      .map((_Candidate candidate) {
        final String label = candidate.classIndex < labels.length
            ? labels[candidate.classIndex]
            : Copy.objectFallback;
        return Detection(
          label: label,
          confidence: candidate.score,
          box: candidate.box,
          distanceMeters: estimateDistanceMeters(
            label: label,
            boxWidthPx: candidate.box.width,
          ),
          direction: directionFor(candidate.box),
        );
      })
      .toList(growable: false);
}

double _sigmoid(double value) => 1.0 / (1.0 + math.exp(-value));

double _intersectionOverUnion(Rect a, Rect b) {
  final double overlapWidth =
      math.min(a.right, b.right) - math.max(a.left, b.left);
  final double overlapHeight =
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
  if (overlapWidth <= 0 || overlapHeight <= 0) {
    return 0;
  }
  final double intersection = overlapWidth * overlapHeight;
  final double union = a.width * a.height + b.width * b.height - intersection;
  if (union <= 0) {
    return 0;
  }
  return intersection / union;
}

class _Candidate {
  const _Candidate({
    required this.classIndex,
    required this.score,
    required this.box,
  });

  final int classIndex;
  final double score;
  final Rect box;
}
