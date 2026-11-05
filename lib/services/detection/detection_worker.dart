import 'dart:isolate';
import 'dart:typed_data';

import 'frame_converter.dart';

/// One conversion job for the long-lived frame isolate.
///
/// The planes travel as [TransferableTypedData] so the camera buffers are
/// copied once, on this side, and moved to the worker without another
/// copy (plan Task 5).
class ConversionRequest {
  const ConversionRequest({
    required this.id,
    required this.format,
    required this.y,
    this.u,
    this.v,
    this.vu,
    required this.width,
    required this.height,
    required this.yBytesPerRow,
    required this.uvBytesPerRow,
    required this.uvPixelStride,
    required this.rotationDegrees,
  });

  factory ConversionRequest.fromPlanes({
    required int id,
    required FramePlanes planes,
  }) {
    TransferableTypedData transfer(Uint8List bytes) =>
        TransferableTypedData.fromList(<TypedData>[bytes]);
    final Uint8List? u = planes.u;
    final Uint8List? v = planes.v;
    final Uint8List? vu = planes.vu;
    return ConversionRequest(
      id: id,
      format: planes.format,
      y: transfer(planes.y),
      u: u == null ? null : transfer(u),
      v: v == null ? null : transfer(v),
      vu: vu == null ? null : transfer(vu),
      width: planes.width,
      height: planes.height,
      yBytesPerRow: planes.yBytesPerRow,
      uvBytesPerRow: planes.uvBytesPerRow,
      uvPixelStride: planes.uvPixelStride,
      rotationDegrees: planes.rotationDegrees,
    );
  }

  final int id;
  final FrameFormat format;
  final TransferableTypedData y;
  final TransferableTypedData? u;
  final TransferableTypedData? v;
  final TransferableTypedData? vu;
  final int width;
  final int height;
  final int yBytesPerRow;
  final int uvBytesPerRow;
  final int uvPixelStride;
  final int rotationDegrees;

  /// Rebuilds sendable planes inside the worker. Each transferable can be
  /// materialized exactly once, and the request is handled exactly once.
  FramePlanes toPlanes() => FramePlanes(
    format: format,
    y: y.materialize().asUint8List(),
    u: u?.materialize().asUint8List(),
    v: v?.materialize().asUint8List(),
    vu: vu?.materialize().asUint8List(),
    width: width,
    height: height,
    yBytesPerRow: yBytesPerRow,
    uvBytesPerRow: uvBytesPerRow,
    uvPixelStride: uvPixelStride,
    rotationDegrees: rotationDegrees,
  );
}

/// The worker's reply: either the converted tensor or a readable failure.
class ConversionResponse {
  const ConversionResponse({required this.id, this.pixels, this.error});

  final int id;

  /// NHWC float32 bytes, `640 * 640 * 3 * 4` long, moved back to the
  /// main isolate without a copy.
  final TransferableTypedData? pixels;

  /// `null` on success; the exception's text otherwise.
  final String? error;
}

/// Long-lived conversion isolate: owns [convertFrame] for the lifetime of
/// the processor, so no per-frame isolate spawn is paid.
///
/// Protocol: the worker sends its [SendPort] first, then answers every
/// [ConversionRequest] with one [ConversionResponse]. A malformed frame
/// produces a failure response, never a dead isolate.
void conversionWorkerMain(SendPort ready) {
  final ReceivePort requests = ReceivePort();
  ready.send(requests.sendPort);
  requests.listen((Object? message) {
    if (message is! ConversionRequest) {
      return;
    }
    try {
      final ConvertedFrame converted = convertFrame(message.toPlanes());
      ready.send(
        ConversionResponse(
          id: message.id,
          pixels: TransferableTypedData.fromList(<TypedData>[converted.input]),
        ),
      );
    } catch (error) {
      ready.send(ConversionResponse(id: message.id, error: error.toString()));
    }
  });
}
