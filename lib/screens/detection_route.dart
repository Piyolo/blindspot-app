import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/detection.dart';
import '../providers/auth_provider.dart';
import '../providers/detection_provider.dart';
import '../services/detection/camera_plugin_source.dart';
import '../services/detection/detection_announcer.dart';
import '../services/detection/detection_engine.dart';
import '../services/detection/frame_processor.dart';
import '../services/detection/platform_alarm_output.dart';
import '../services/detection/proximity_alarm.dart';
import '../services/flutter_tts_engine.dart';
import '../services/tts_service.dart';
import 'detection_screen.dart';

/// The `/detection` route: builds the real detection stack for one screen
/// session and tears it down when the route leaves the tree.
///
/// The provider (and with it the camera, processor and alarm) is created
/// here rather than in `main.dart`'s provider graph, so the camera is
/// bound to the screen's lifetime (plan Task 12). Assets are read from
/// the bundle on first mount; the screen shows its starting state until
/// they are ready.
class DetectionRoute extends StatefulWidget {
  const DetectionRoute({super.key});

  @override
  State<DetectionRoute> createState() => _DetectionRouteState();
}

class _DetectionRouteState extends State<DetectionRoute> {
  late final AuthProvider _auth;
  DetectionProvider? _provider;
  CameraPluginSource? _camera;
  TtsService? _tts;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    unawaited(_boot());
  }

  @override
  void dispose() {
    _provider?.dispose();
    final TtsService? tts = _tts;
    if (tts != null) {
      unawaited(tts.dispose());
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final ByteData model = await rootBundle.load('assets/ml/yolov8nV5.tflite');
    final String rawLabels = await rootBundle.loadString(
      'assets/ml/labelsV5.txt',
    );
    if (!mounted) {
      return;
    }
    final List<String> labels = rawLabels
        .split(RegExp(r'\r?\n'))
        .map((String label) => label.trim())
        .where((String label) => label.isNotEmpty)
        .toList(growable: false);

    final TtsService tts = TtsService(FlutterTtsEngine());
    final CameraPluginSource camera = CameraPluginSource();
    final ProximityAlarm alarm = ProximityAlarm(
      output: PlatformAlarmOutput(),
      tts: tts,
    );
    final DetectionAnnouncer announcer = DetectionAnnouncer(
      tts: tts,
      now: DateTime.now,
      alarmActive: () => alarm.isActive,
    );
    final DetectionEngine engine = DetectionEngine(
      camera: camera,
      processor: IsolateFrameProcessor(
        modelBytes: model.buffer.asUint8List(
          model.offsetInBytes,
          model.lengthInBytes,
        ),
        labels: labels,
      ),
      now: DateTime.now,
    );
    final DetectionProvider provider = DetectionProvider(
      engine: engine,
      announcer: announcer,
      alarm: alarm,
      isSignedIn: () => _auth.status == AuthStatus.signedIn,
    );

    if (!mounted) {
      provider.dispose();
      unawaited(tts.dispose());
      return;
    }
    _tts = tts;
    _camera = camera;
    setState(() => _provider = provider);
    unawaited(provider.start());
  }

  @override
  Widget build(BuildContext context) {
    final DetectionProvider? provider = _provider;
    if (provider == null) {
      return DetectionScreen(
        status: DetectionEngineStatus.starting,
        detections: const <Detection>[],
        frameSize: null,
        hasTorch: false,
        torchOn: false,
        onStop: _noop,
        onRetry: _noop,
        onToggleTorch: _noop,
        previewBuilder: (_) => const ColoredBox(color: Color(0xFF000000)),
      );
    }
    return ListenableBuilder(
      listenable: provider,
      builder: (BuildContext context, Widget? child) => DetectionScreen(
        status: provider.status,
        detections: provider.detections,
        frameSize: provider.frameSize,
        hasTorch: provider.hasTorch,
        torchOn: provider.torchOn,
        onStop: provider.stop,
        onRetry: provider.retry,
        onToggleTorch: provider.toggleTorch,
        previewBuilder: (BuildContext context) => _preview(provider),
      ),
    );
  }

  /// The live preview, cover-fitted to the preview area exactly like the
  /// overlay's [mapBoxToView] math: the frame keeps its aspect ratio and
  /// the excess is cropped.
  Widget _preview(DetectionProvider provider) {
    final CameraController? controller = _camera?.controller;
    final Size? frameSize = provider.frameSize;
    if (controller == null ||
        !controller.value.isInitialized ||
        frameSize == null) {
      return const ColoredBox(color: Color(0xFF000000));
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: frameSize.width,
        height: frameSize.height,
        child: CameraPreview(controller),
      ),
    );
  }

  Future<void> _noop() async {}
}
