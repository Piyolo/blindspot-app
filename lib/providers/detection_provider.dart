import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import '../models/detection.dart';
import '../services/detection/detection_announcer.dart';
import '../services/detection/detection_engine.dart';
import '../services/detection/frame_processor.dart';
import '../services/detection/proximity_alarm.dart';

/// Owns the detection screen's camera session (plan Task 12).
///
/// Created inside the `/detection` route, never app-wide, so the camera
/// is bound to the screen's lifetime. The provider is the single place
/// where a finished frame fans out: it stores the list for the UI, then
/// feeds the announcer and the proximity alarm.
class DetectionProvider extends ChangeNotifier {
  DetectionProvider({
    required DetectionEngine engine,
    required DetectionAnnouncer announcer,
    required ProximityAlarm alarm,
    required bool Function() isSignedIn,
  }) : _engine = engine,
       _announcer = announcer,
       _alarm = alarm,
       _isSignedIn = isSignedIn {
    _engine.onResult = _handleResult;
    _engine.onStatus = _handleStatus;
    _status = _engine.status;
  }

  final DetectionEngine _engine;
  final DetectionAnnouncer _announcer;
  final ProximityAlarm _alarm;
  final bool Function() _isSignedIn;

  DetectionEngineStatus _status = DetectionEngineStatus.idle;
  List<Detection> _detections = const <Detection>[];
  Detection? _nearest;
  String? _error;
  bool _disposed = false;

  DetectionEngineStatus get status => _status;
  List<Detection> get detections => _detections;
  Detection? get nearest => _nearest;
  String? get error => _error;

  /// The rotated camera frame for the overlay; null until the camera
  /// reports its size.
  Size? get frameSize => _engine.frameSize;

  bool get torchOn => _engine.torchOn;
  bool get hasTorch => _engine.hasTorch;

  /// Starts a new screen session. A dead session never opens the camera.
  Future<void> start() async {
    if (_disposed || !_isSignedIn()) {
      return;
    }
    await _announcer.reset();
    if (_disposed) {
      return;
    }
    await _engine.start();
  }

  /// Ends the session: no frames, no alarm, no stale list.
  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    await _engine.stop();
    await _alarm.stop();
    if (_disposed) {
      return;
    }
    _detections = const <Detection>[];
    _nearest = null;
    notifyListeners();
  }

  /// Rebuilds a failed camera session (the screen's Try again).
  Future<void> retry() async {
    if (_disposed || !_isSignedIn()) {
      return;
    }
    _detections = const <Detection>[];
    _nearest = null;
    await _engine.retry();
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> toggleTorch() async {
    if (_disposed) {
      return;
    }
    await _engine.toggleTorch();
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    // Detach first: a frame that lands during teardown must never reach a
    // disposed ChangeNotifier.
    _engine.onResult = null;
    _engine.onStatus = null;
    unawaited(_engine.dispose());
    unawaited(_alarm.dispose());
    super.dispose();
  }

  void _handleResult(List<Detection> detections, FrameResult result) {
    if (_disposed) {
      return;
    }
    _detections = List<Detection>.unmodifiable(detections);
    _nearest = _nearestOf(detections);
    notifyListeners();
    unawaited(_announcer.onDetections(detections));
    unawaited(_alarm.onNearest(_nearest));
  }

  void _handleStatus(DetectionEngineStatus status, String? error) {
    if (_disposed) {
      return;
    }
    _status = status;
    _error = error;
    // Only a running engine has a current frame; anything else must not
    // leave last-frame boxes or rows on screen.
    if (status != DetectionEngineStatus.running) {
      _detections = const <Detection>[];
      _nearest = null;
    }
    notifyListeners();
  }

  /// The alarm's target: nearest by distance, ties to the higher
  /// confidence. A distance-less detection can never trigger the alarm,
  /// so it never becomes [nearest] either.
  Detection? _nearestOf(List<Detection> detections) {
    Detection? nearest;
    for (final Detection detection in detections) {
      final double? distance = detection.distanceMeters;
      if (distance == null) {
        continue;
      }
      final Detection? current = nearest;
      if (current == null ||
          distance < current.distanceMeters! ||
          (distance == current.distanceMeters! &&
              detection.confidence > current.confidence)) {
        nearest = detection;
      }
    }
    return nearest;
  }
}
