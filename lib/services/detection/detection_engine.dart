import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show Size;

import '../../constants/detection.dart';
import '../../models/detection.dart';
import 'camera_source.dart';
import 'frame_processor.dart';
import 'motion_gate.dart';

enum DetectionEngineStatus { idle, starting, running, error }

/// Pumps camera frames through the processor under the plan's gates:
/// cadence, backpressure, motion, and the thermal backoff ladder.
///
/// All time comes from [now], so every test is deterministic.
class DetectionEngine {
  DetectionEngine({
    required CameraSource camera,
    required FrameProcessor processor,
    required DateTime Function() now,
    double Function()? motionMad,
    void Function(List<Detection> detections, FrameResult result)? onResult,
    void Function(DetectionEngineStatus status, String? error)? onStatus,
  }) : _camera = camera,
       _processor = processor,
       _now = now,
       _motionMad = motionMad,
       _onResult = onResult,
       _onStatus = onStatus;

  final CameraSource _camera;
  final FrameProcessor _processor;
  final DateTime Function() _now;

  /// Test seam: replaces the measured MAD with a fixed score. Production
  /// leaves it null and the engine measures the downsampled planes.
  final double Function()? _motionMad;
  final void Function(List<Detection> detections, FrameResult result)?
  _onResult;
  final void Function(DetectionEngineStatus status, String? error)? _onStatus;

  DetectionEngineStatus _status = DetectionEngineStatus.idle;
  bool _disposed = false;
  bool _busy = false;
  bool _torchOn = false;
  int _run = 0;
  int _nextFrameId = 0;
  int _tier = 0;
  int _slowStreak = 0;
  DateTime? _fastSince;
  DateTime? _lastAcceptedAt;
  Uint8List? _previousGray;

  DetectionEngineStatus get status => _status;
  bool get hasTorch => _camera.hasTorch;
  bool get torchOn => _torchOn;
  Size? get frameSize => _camera.frameSize;

  int get _intervalMs => _tier == 0
      ? DetectionConstants.frameMinIntervalMs
      : DetectionConstants.thermalBackoffMs[_tier - 1];

  Future<void> start() async {
    if (_disposed ||
        _status == DetectionEngineStatus.starting ||
        _status == DetectionEngineStatus.running) {
      return;
    }
    final int run = ++_run;
    _busy = false;
    _torchOn = false;
    _lastAcceptedAt = null;
    _previousGray = null;
    _resetLadder();
    _setStatus(DetectionEngineStatus.starting, null);
    try {
      await _camera.initialize();
      if (run != _run) {
        return;
      }
      await _processor.initialize();
      if (run != _run) {
        return;
      }
      await _camera.start(_onFrame);
      if (run != _run) {
        return;
      }
      _setStatus(DetectionEngineStatus.running, null);
    } catch (error) {
      if (run != _run) {
        return;
      }
      await _stopCameraQuietly();
      _setStatus(DetectionEngineStatus.error, error.toString());
    }
  }

  Future<void> retry() async {
    if (_disposed) {
      return;
    }
    await stop();
    await start();
  }

  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    _run++;
    _busy = false;
    _torchOn = false;
    _lastAcceptedAt = null;
    _previousGray = null;
    _resetLadder();
    await _stopCameraQuietly();
    _setStatus(DetectionEngineStatus.idle, null);
  }

  Future<void> toggleTorch() async {
    if (!_camera.hasTorch) {
      return;
    }
    _torchOn = !_torchOn;
    await _camera.setTorch(_torchOn);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _run++;
    _busy = false;
    _torchOn = false;
    _lastAcceptedAt = null;
    _previousGray = null;
    _resetLadder();
    await _stopCameraQuietly();
    await _camera.dispose();
    await _processor.dispose();
    _status = DetectionEngineStatus.idle;
  }

  void _onFrame(CameraFrame frame) {
    if (_disposed || _status != DetectionEngineStatus.running || _busy) {
      return;
    }
    final DateTime acceptedAt = _now();
    final DateTime? last = _lastAcceptedAt;
    if (last != null &&
        acceptedAt.difference(last).inMilliseconds < _intervalMs) {
      return;
    }
    // Skipped frames still consume a cadence slot, so the motion check
    // runs at the pump rate rather than at the camera's frame rate.
    _lastAcceptedAt = acceptedAt;
    try {
      final Uint8List gray = downsampleGray(
        frame.planes,
        size: DetectionConstants.motionSize,
      );
      final Uint8List? previous = _previousGray;
      if (previous != null) {
        final double measured =
            _motionMad?.call() ?? meanAbsoluteDifference(previous, gray);
        if (measured < DetectionConstants.motionMad) {
          return;
        }
      }
      _previousGray = gray;
    } catch (error) {
      unawaited(_fail(error));
      return;
    }
    _busy = true;
    unawaited(_process(frame, ++_nextFrameId));
  }

  Future<void> _process(CameraFrame frame, int frameId) async {
    final int run = _run;
    try {
      final FrameResult? result = await _processor.process(
        FrameRequest(
          planes: frame.planes,
          frameId: frameId,
          capturedAt: frame.capturedAt,
        ),
      );
      if (!_isCurrent(run) || result == null) {
        return;
      }
      _updateThermal(result);
      if (!_isCurrent(run)) {
        return;
      }
      _onResult?.call(result.detections, result);
    } catch (error) {
      if (!_isCurrent(run)) {
        return;
      }
      await _fail(error);
    } finally {
      if (run == _run) {
        _busy = false;
      }
    }
  }

  /// Updates the thermal tier from one finished run:
  ///
  /// - two consecutive runs slower than [DetectionConstants.thermalSlowMs]
  ///   escalate one tier, up to the last backoff step;
  /// - a run faster than [DetectionConstants.thermalFastMs] extends a fast
  ///   streak, and [DetectionConstants.thermalRecoverMs] of uninterrupted
  ///   fast runs drops the engine straight back to the base interval.
  ///
  /// The 250–350 ms band and slow runs reset the fast streak; a fast run
  /// resets the slow streak. Recovery is evaluated on the next result
  /// instead of a timer, so nothing can outlive [dispose].
  void _updateThermal(FrameResult result) {
    final int totalMs = result.totalMs;
    if (totalMs > DetectionConstants.thermalSlowMs) {
      _fastSince = null;
      _slowStreak++;
      if (_slowStreak >= 2) {
        _slowStreak = 0;
        if (_tier < DetectionConstants.thermalBackoffMs.length) {
          _tier++;
        }
      }
      return;
    }
    _slowStreak = 0;
    if (totalMs >= DetectionConstants.thermalFastMs) {
      _fastSince = null;
      return;
    }
    final DateTime? since = _fastSince;
    if (since == null) {
      _fastSince = _now();
      return;
    }
    if (_now().difference(since).inMilliseconds >=
        DetectionConstants.thermalRecoverMs) {
      _tier = 0;
      _fastSince = null;
    }
  }

  Future<void> _fail(Object error) async {
    if (_disposed) {
      return;
    }
    _run++;
    _busy = false;
    _lastAcceptedAt = null;
    _previousGray = null;
    _resetLadder();
    await _stopCameraQuietly();
    _setStatus(DetectionEngineStatus.error, error.toString());
  }

  bool _isCurrent(int run) => !_disposed && run == _run;

  void _resetLadder() {
    _tier = 0;
    _slowStreak = 0;
    _fastSince = null;
  }

  void _setStatus(DetectionEngineStatus status, String? error) {
    _status = status;
    _onStatus?.call(status, error);
  }

  Future<void> _stopCameraQuietly() async {
    try {
      await _camera.stop();
    } catch (_) {
      // A camera that failed to start may also fail to stop; the engine
      // only needs to know it is no longer receiving frames.
    }
  }
}
