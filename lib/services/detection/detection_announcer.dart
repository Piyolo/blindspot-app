import 'dart:math';

import 'package:blindspot_app/constants/copy.dart';
import 'package:blindspot_app/constants/detection.dart';
import 'package:blindspot_app/models/detection.dart';
import 'package:blindspot_app/services/detection/depth_estimator.dart';
import 'package:blindspot_app/services/tts_service.dart';
import 'package:blindspot_app/utils/template.dart';

/// Turns a frame's detections into one spoken announcement (plan Task 7,
/// spec §6.1).
///
/// The nearest detection wins (smallest [Detection.distanceMeters];
/// equal distances go to the higher confidence). A distance-less
/// detection never outranks one with a distance; when *no* detection has
/// a distance — the decoder's `Copy.objectFallback` path — the most
/// confident one is still announced, without a distance.
///
/// Announcements are keyed by **label**, not by the composed phrase: the
/// same label waits [DetectionConstants.announceSameLabelMinMs]..
/// [DetectionConstants.announceSameLabelMaxMs] ms (drawn from [random]),
/// a changed label waits [DetectionConstants.announceChangedLabelMs] ms.
/// While [alarmActive] is true nothing is spoken and the cooldown is not
/// touched. The accuracy disclaimer is spoken once per session, ahead of
/// the first object phrase; [reset] re-arms it.
class DetectionAnnouncer {
  DetectionAnnouncer({
    required TtsService tts,
    required DateTime Function() now,
    required bool Function() alarmActive,
    Random? random,
    this.labelsFil,
  }) : _tts = tts,
       _now = now,
       _alarmActive = alarmActive,
       _random = random ?? Random();

  final TtsService _tts;
  final DateTime Function() _now;
  final bool Function() _alarmActive;
  final Random _random;

  /// Reserved for Phase 5's Filipino announcements; never read in Phase 2.
  final Map<String, String>? labelsFil;

  DateTime? _lastAnnouncementAt;
  String? _lastLabel;
  int _sameLabelCooldownMs = DetectionConstants.announceSameLabelMinMs;
  bool _disclaimerSpoken = false;

  /// Announces at most one object from [detections].
  Future<void> onDetections(List<Detection> detections) async {
    final Detection? candidate = _nearest(detections);
    if (candidate == null || _alarmActive()) {
      return;
    }

    final DateTime now = _now();
    if (_isCoolingDown(now, candidate.label)) {
      return;
    }

    // The cooldown starts at the decision, before the awaits, so a frame
    // that arrives during the disclaimer cannot announce twice.
    _lastAnnouncementAt = now;
    _lastLabel = candidate.label;
    _sameLabelCooldownMs =
        DetectionConstants.announceSameLabelMinMs +
        _random.nextInt(
          DetectionConstants.announceSameLabelMaxMs -
              DetectionConstants.announceSameLabelMinMs +
              1,
        );

    if (!_disclaimerSpoken) {
      _disclaimerSpoken = true;
      await _tts.speak(
        Copy.detectionDisclaimer,
        priority: SpeechPriority.detection,
      );
    }
    await _tts.speak(_phraseFor(candidate), priority: SpeechPriority.detection);
  }

  /// Starts a new screen session: the next announcement re-arms the
  /// disclaimer and no label is cooling down.
  Future<void> reset() async {
    _lastAnnouncementAt = null;
    _lastLabel = null;
    _disclaimerSpoken = false;
  }

  Detection? _nearest(List<Detection> detections) {
    Detection? nearest;
    for (final Detection detection in detections) {
      if (detection.distanceMeters == null) {
        continue;
      }
      if (nearest == null) {
        nearest = detection;
        continue;
      }
      final double distance = detection.distanceMeters!;
      final double nearestDistance = nearest.distanceMeters!;
      if (distance < nearestDistance ||
          (distance == nearestDistance &&
              detection.confidence > nearest.confidence)) {
        nearest = detection;
      }
    }
    if (nearest != null) {
      return nearest;
    }

    Detection? closestKnown;
    for (final Detection detection in detections) {
      if (closestKnown == null ||
          detection.confidence > closestKnown.confidence) {
        closestKnown = detection;
      }
    }
    return closestKnown;
  }

  bool _isCoolingDown(DateTime now, String label) {
    final DateTime? last = _lastAnnouncementAt;
    if (last == null) {
      return false;
    }
    final int elapsedMs = now.difference(last).inMilliseconds;
    if (label == _lastLabel) {
      return elapsedMs < _sameLabelCooldownMs;
    }
    return elapsedMs < DetectionConstants.announceChangedLabelMs;
  }

  String _phraseFor(Detection detection) {
    final String direction = switch (directionFor(detection.box)) {
      DetectionDirection.left => Copy.directionLeft,
      DetectionDirection.ahead => Copy.directionAhead,
      DetectionDirection.right => Copy.directionRight,
    };
    final DistancePhrase? distance = distancePhrase(detection.distanceMeters);
    if (distance == null) {
      return fillTemplate(_distanceFreeTemplate, <String, String>{
        'object': detection.label,
        'direction': direction,
      });
    }
    return fillTemplate(Copy.announcementTemplate, <String, String>{
      'object': detection.label,
      'direction': direction,
      'distance': _distanceText(distance),
    });
  }

  /// The announcement template minus its distance clause, so a
  /// distance-less detection speaks "object ahead" rather than a
  /// fabricated distance.
  String get _distanceFreeTemplate =>
      Copy.announcementTemplate.replaceAll(RegExp(r',?\s*\{distance\}'), '');

  String _distanceText(DistancePhrase phrase) {
    return switch (phrase) {
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
}
