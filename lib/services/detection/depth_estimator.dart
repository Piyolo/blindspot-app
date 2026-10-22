import 'dart:math' show max;

import 'package:blindspot_app/constants/detection.dart';

/// Width-based depth estimate (plan Task 3, `2026-10-21-blindspot-
/// phase2-detection.md`): `cm = realWidthCm * focalLengthPx /
/// boxWidthPx`, `m = cm / 100`.
///
/// [boxWidthPx] must be the box width in **model space** (the 640×640
/// letterboxed input), never the view-mapped width, so the estimate is
/// device-independent (`p2-global-constraints.md`). [label] is matched
/// after normalisation: trimmed, lower-cased, internal whitespace
/// collapsed, then resolved through `DetectionConstants.labelAliases`.
///
/// Returns `null` for an unknown label or a non-positive width — there
/// is no "unknown" distance bucket.
double? estimateDistanceMeters({
  required String label,
  required double boxWidthPx,
}) {
  if (boxWidthPx <= 0) {
    return null;
  }
  final int? widthCm = DetectionConstants.realWidthCm[_normaliseLabel(label)];
  if (widthCm == null) {
    return null;
  }
  final double cm = widthCm * DetectionConstants.focalLengthPx / boxWidthPx;
  return cm / 100;
}

/// Trim + lower-case + collapse internal whitespace, then apply the
/// `tv` → `television` / `wc` → `toilet` aliases.
String _normaliseLabel(String label) {
  final String collapsed = label.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  return DetectionConstants.labelAliases[collapsed] ?? collapsed;
}

/// A spoken distance, already bucketed (plan Task 3): whole metres at or
/// above one metre, otherwise the nearest 10 cm with a 10 cm floor.
/// Rendered by the announcer through `Copy.distanceMetersOne` /
/// `Copy.distanceMetersTemplate` / `Copy.distanceCentimetersTemplate`.
sealed class DistancePhrase {
  const DistancePhrase();
}

/// "approximately {meters} meters" (`Copy.distanceMetersOne` when
/// [meters] is 1, else `Copy.distanceMetersTemplate`).
final class MetersPhrase extends DistancePhrase {
  const MetersPhrase(this.meters);

  final int meters;

  @override
  bool operator ==(Object other) =>
      other is MetersPhrase && other.meters == meters;

  @override
  int get hashCode => Object.hash(MetersPhrase, meters);
}

/// "approximately {centimeters} centimeters"
/// (`Copy.distanceCentimetersTemplate`).
final class CentimetersPhrase extends DistancePhrase {
  const CentimetersPhrase(this.centimeters);

  final int centimeters;

  @override
  bool operator ==(Object other) =>
      other is CentimetersPhrase && other.centimeters == centimeters;

  @override
  int get hashCode => Object.hash(CentimetersPhrase, centimeters);
}

/// Phrases a distance in metres for speech (plan Task 3). `null` in,
/// `null` out. The bucket is applied to the **raw** value before any
/// rounding: `m < 1.0` → the nearest 10 cm floored at 10 cm (and 100 cm
/// promotes to [MetersPhrase] 1); `m >= 1.0` → whole metres
/// (`1.4 → 1`, `1.5 → 2`, `2.0 → 2`).
DistancePhrase? distancePhrase(double? meters) {
  if (meters == null) {
    return null;
  }
  if (meters >= 1.0) {
    return MetersPhrase(meters.round());
  }
  final int cm = max(10, (meters * 100 / 10).round() * 10);
  if (cm >= 100) {
    return const MetersPhrase(1);
  }
  return CentimetersPhrase(cm);
}
