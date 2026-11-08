import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../constants/copy.dart';
import '../models/detection.dart';
import '../services/detection/detection_engine.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/bbox_overlay.dart';
import '../widgets/object_row.dart';

/// Keeps the screen awake while detection runs.
///
/// The plugin is reached through this seam because `WakelockPlus` talks to
/// a platform channel that does not exist in host tests.
abstract class ScreenWakelock {
  Future<void> enable();
  Future<void> disable();
}

/// The production wakelock: `wakelock_plus`'s static API.
class PluginWakelock implements ScreenWakelock {
  const PluginWakelock();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

/// The live detection view: camera preview under a scrim, boxes for the
/// current frame, the nearest-first object list, the flash toggle and the
/// big Stop.
///
/// The screen is a pure view over values and callbacks (Task 12's
/// `DetectionProvider` supplies them), so every state is testable without
/// a camera or a provider. The preview itself arrives through
/// [previewBuilder] for the same reason: the real `CameraPreview` needs a
/// plugin controller, which must never be built in a widget test.
class DetectionScreen extends StatefulWidget {
  const DetectionScreen({
    super.key,
    required this.status,
    required this.detections,
    required this.frameSize,
    required this.hasTorch,
    required this.torchOn,
    required this.onStop,
    required this.onRetry,
    required this.onToggleTorch,
    required this.previewBuilder,
    this.wakelock = const PluginWakelock(),
  });

  final DetectionEngineStatus status;
  final List<Detection> detections;

  /// The rotated camera frame size, or null before the camera reports one.
  final Size? frameSize;
  final bool hasTorch;
  final bool torchOn;
  final Future<void> Function() onStop;
  final Future<void> Function() onRetry;
  final Future<void> Function() onToggleTorch;
  final WidgetBuilder previewBuilder;
  final ScreenWakelock wakelock;

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  /// Set synchronously on the first Stop tap, so a double tap cannot stop
  /// twice while the awaited provider call is still in flight.
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    unawaited(_enableWakelock());
  }

  @override
  void dispose() {
    unawaited(_disableWakelock());
    super.dispose();
  }

  Future<void> _enableWakelock() async {
    try {
      await widget.wakelock.enable();
    } catch (_) {
      // Best-effort: a platform without wakelock support must still show
      // the camera screen.
    }
  }

  Future<void> _disableWakelock() async {
    try {
      await widget.wakelock.disable();
    } catch (_) {
      // Best-effort, same as enable.
    }
  }

  Future<void> _stop() async {
    if (_stopping) {
      return;
    }
    setState(() => _stopping = true);
    await widget.onStop();
    if (!mounted) {
      return;
    }
    try {
      await SemanticsService.sendAnnouncement(
        View.of(context),
        Copy.detectionStopped,
        Directionality.of(context),
      );
    } catch (_) {
      // Best-effort: the route change must never be blocked by audio.
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _retry() async {
    await widget.onRetry();
  }

  void _toggleTorch() {
    unawaited(widget.onToggleTorch());
  }

  /// Nearest first; a detection without a distance sinks below every one
  /// with a distance, and equal distances go to the higher confidence.
  List<Detection> get _sortedByNearest {
    final List<Detection> sorted = List<Detection>.of(widget.detections);
    sorted.sort((Detection a, Detection b) {
      final double? aDistance = a.distanceMeters;
      final double? bDistance = b.distanceMeters;
      if (aDistance == null && bDistance == null) {
        return b.confidence.compareTo(a.confidence);
      }
      if (aDistance == null) {
        return 1;
      }
      if (bDistance == null) {
        return -1;
      }
      final int byDistance = aDistance.compareTo(bDistance);
      if (byDistance != 0) {
        return byDistance;
      }
      return b.confidence.compareTo(a.confidence);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final bool running = widget.status == DetectionEngineStatus.running;
    final List<Detection> sorted = _sortedByNearest;
    // The shared dark status-bar style, as on the other screens (see
    // [AppTheme.statusBarStyle]).
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.statusBarStyle,
      child: Scaffold(
        appBar: AppBar(title: const Text(Copy.detectionTitle)),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The preview and the list share the leftover height as
              // 3:2. At 3.0x text the pinned controls grow, the flex
              // children shrink, and nothing overflows: the list scrolls
              // and the preview simply gets smaller.
              Expanded(flex: 3, child: _preview(running)),
              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: _statusContent(sorted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (running && widget.hasTorch) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: OutlinedButton.icon(
                          onPressed: _toggleTorch,
                          icon: Icon(
                            widget.torchOn ? Icons.flash_off : Icons.flash_on,
                          ),
                          label: Text(
                            widget.torchOn ? Copy.flashOff : Copy.flashOn,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // 56 dp minimum, growing with the label at large text
                    // scales instead of clipping.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: ElevatedButton(
                        onPressed: _stopping ? null : _stop,
                        child: const Text(Copy.stopDetection),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview(bool running) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size viewSize = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            KeyedSubtree(
              key: const ValueKey<String>('detectionPreview'),
              child: widget.previewBuilder(context),
            ),
            // The 40% scrim keeps the bright camera image from washing out
            // the overlay and the cream-on-dark UI.
            const ColoredBox(
              key: ValueKey<String>('detectionScrim'),
              color: Color(0x66000000),
            ),
            if (running && widget.frameSize != null)
              BboxOverlay(
                detections: widget.detections,
                frameSize: widget.frameSize!,
                viewSize: viewSize,
              ),
          ],
        );
      },
    );
  }

  Widget _statusContent(List<Detection> sorted) {
    switch (widget.status) {
      case DetectionEngineStatus.idle:
      case DetectionEngineStatus.starting:
        return _liveStatus(Copy.detectionStarting, AppTextStyles.status);
      case DetectionEngineStatus.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _liveStatus(
              Copy.cameraError,
              AppTextStyles.body.copyWith(color: AppColors.errorText),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: ElevatedButton(
                onPressed: _retry,
                child: const Text(Copy.retry),
              ),
            ),
          ],
        );
      case DetectionEngineStatus.running:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _liveStatus(
              sorted.isEmpty ? Copy.noObjects : Copy.watching,
              AppTextStyles.status,
            ),
            if (sorted.isNotEmpty) ...[
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: const Text(
                  Copy.objectsHeading,
                  style: AppTextStyles.section,
                ),
              ),
              const SizedBox(height: 4),
              for (final Detection detection in sorted)
                ObjectRow(detection: detection),
            ],
          ],
        );
    }
  }

  /// A live region on the state line, so the change is announced the
  /// moment it appears, not only when TalkBack focus reaches it.
  Widget _liveStatus(String text, TextStyle style) => Semantics(
    container: true,
    liveRegion: true,
    child: Text(text, style: style),
  );
}
