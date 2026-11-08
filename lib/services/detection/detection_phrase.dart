import '../../constants/copy.dart';
import '../../models/detection.dart';
import '../../utils/template.dart';
import 'depth_estimator.dart';

/// The direction word for [detection], recomputed from its model box so
/// the spoken phrase and the on-screen row can never disagree.
String detectionDirectionText(Detection detection) {
  return switch (directionFor(detection.box)) {
    DetectionDirection.left => Copy.directionLeft,
    DetectionDirection.ahead => Copy.directionAhead,
    DetectionDirection.right => Copy.directionRight,
  };
}

/// The distance phrase for [detection], or null when the decoder could
/// not estimate one (an unlabelled `Copy.objectFallback` detection).
String? detectionDistanceText(Detection detection) {
  return switch (distancePhrase(detection.distanceMeters)) {
    null => null,
    MetersPhrase(meters: 1) => Copy.distanceMetersOne,
    MetersPhrase(:final int meters) => fillTemplate(
      Copy.distanceMetersTemplate,
      <String, String>{'count': '$meters'},
    ),
    CentimetersPhrase(:final int centimeters) => fillTemplate(
      Copy.distanceCentimetersTemplate,
      <String, String>{'count': '$centimeters'},
    ),
  };
}

/// The spoken phrase for [detection]: `Copy.announcementTemplate` with the
/// direction and, when known, the distance. A distance-less detection
/// drops the template's distance clause instead of inventing one.
String detectionPhrase(Detection detection) {
  final String direction = detectionDirectionText(detection);
  final String? distance = detectionDistanceText(detection);
  if (distance == null) {
    return fillTemplate(
      Copy.announcementTemplate.replaceAll(RegExp(r',?\s*\{distance\}'), ''),
      <String, String>{'object': detection.label, 'direction': direction},
    );
  }
  return fillTemplate(Copy.announcementTemplate, <String, String>{
    'object': detection.label,
    'direction': direction,
    'distance': distance,
  });
}
