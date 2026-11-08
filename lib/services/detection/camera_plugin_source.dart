import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;

import 'camera_source.dart';
import 'frame_converter.dart';

/// The production [CameraSource], backed by the `camera` plugin.
///
/// The controller is created lazily in [initialize] so constructing this
/// source never touches a platform channel. The preview screen reads
/// [controller] to build its `CameraPreview`; [frameSize] is the rotated
/// frame size (the orientation the preview shows), which is what the
/// overlay mapping expects.
///
/// Phase 2 targets Android. iOS camera images arrive as a single
/// bi-planar buffer, which [FramePlanes] does not model; [start] would
/// report an error through the engine's error state instead of decoding
/// garbage.
class CameraPluginSource implements CameraSource {
  CameraPluginSource({this.resolution = ResolutionPreset.medium});

  final ResolutionPreset resolution;

  CameraController? _controller;
  Size? _frameSize;

  /// The controller the preview builder needs; null until [initialize]
  /// completes.
  CameraController? get controller => _controller;

  @override
  Size? get frameSize => _frameSize;

  @override
  bool get hasTorch =>
      _controller?.description.lensDirection == CameraLensDirection.back;

  @override
  Future<void> initialize() async {
    if (_controller != null) {
      return;
    }
    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('no camera is available');
    }
    final CameraDescription description = cameras.firstWhere(
      (CameraDescription camera) =>
          camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final CameraController controller = CameraController(
      description,
      resolution,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    _controller = controller;
    _frameSize = _rotatedSize(
      controller.value.previewSize,
      _rotationFor(controller),
    );
  }

  @override
  Future<void> start(void Function(CameraFrame) onFrame) async {
    final CameraController? controller = _controller;
    if (controller == null) {
      throw StateError('CameraPluginSource.initialize() must complete');
    }
    await controller.startImageStream((CameraImage image) {
      final int rotation = _rotationFor(controller);
      _frameSize = _rotatedSize(
        Size(image.width.toDouble(), image.height.toDouble()),
        rotation,
      );
      onFrame(
        CameraFrame(
          planes: _planesFor(image, rotation),
          capturedAt: DateTime.now(),
        ),
      );
    });
  }

  @override
  Future<void> stop() async {
    final CameraController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } on CameraException {
        // Stopping a stream the platform already tore down is harmless.
      }
    }
    try {
      await controller.setFlashMode(FlashMode.off);
    } on CameraException {
      // No flash on this device; the camera is stopping anyway.
    }
  }

  @override
  Future<void> setTorch(bool on) async {
    final CameraController? controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      await controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } on CameraException {
      // A camera without a usable torch must not throw through the engine;
      // the toggle simply has no visible effect.
    }
  }

  @override
  Future<void> dispose() async {
    final CameraController? controller = _controller;
    _controller = null;
    _frameSize = null;
    if (controller == null) {
      return;
    }
    if (controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } on CameraException {
        // Already stopped is fine.
      }
    }
    try {
      await controller.setFlashMode(FlashMode.off);
    } on CameraException {
      // Best effort before closing the camera.
    }
    await controller.dispose();
  }

  FramePlanes _planesFor(CameraImage image, int rotation) {
    if (image.format.group != ImageFormatGroup.yuv420 ||
        image.planes.length < 3) {
      throw StateError(
        'camera image is ${image.format.group} with '
        '${image.planes.length} planes; yuv420 needs 3',
      );
    }
    final Plane y = image.planes[0];
    final Plane u = image.planes[1];
    final Plane v = image.planes[2];
    return FramePlanes(
      format: FrameFormat.yuv420,
      y: y.bytes,
      u: u.bytes,
      v: v.bytes,
      width: image.width,
      height: image.height,
      yBytesPerRow: y.bytesPerRow,
      uvBytesPerRow: u.bytesPerRow,
      uvPixelStride: u.bytesPerPixel ?? 1,
      rotationDegrees: rotation,
    );
  }

  /// Clockwise rotation that makes the sensor image upright on screen,
  /// mirroring the `CameraPreview` rotation for the current device
  /// orientation (the back camera's sensor is landscape on Android).
  int _rotationFor(CameraController controller) {
    final int sensor = controller.description.sensorOrientation;
    final int device = switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final int rotation =
        controller.description.lensDirection == CameraLensDirection.front
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
    return rotation;
  }

  Size? _rotatedSize(Size? size, int rotation) {
    if (size == null) {
      return null;
    }
    return rotation == 90 || rotation == 270
        ? Size(size.height, size.width)
        : size;
  }
}
