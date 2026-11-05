import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../constants/detection.dart';
import '../../models/detection.dart';
import 'detection_worker.dart';
import 'frame_converter.dart';
import 'yolo_postprocess.dart';

/// One frame waiting to be converted and run through the model.
class FrameRequest {
  const FrameRequest({
    required this.planes,
    required this.frameId,
    required this.capturedAt,
  });

  final FramePlanes planes;

  /// Monotonic id assigned by the engine; echoed in [FrameResult] so the
  /// caller can drop a stale result.
  final int frameId;

  /// When the camera produced the frame.
  final DateTime capturedAt;
}

/// The outcome of one [FrameRequest], with per-stage timings for the
/// thermal ladder in Task 10.
class FrameResult {
  const FrameResult({
    required this.frameId,
    required this.detections,
    required this.convertMs,
    required this.inferenceMs,
    required this.totalMs,
  });

  final int frameId;
  final List<Detection> detections;
  final int convertMs;
  final int inferenceMs;
  final int totalMs;
}

/// The seam between the engine and the native pipeline.
///
/// Implementations are serialised internally; the engine still drops
/// frames rather than queueing them, so at most one request is in flight
/// in production.
abstract class FrameProcessor {
  Future<void> initialize();

  /// Returns `null` when the processor could not dispatch the run (for
  /// example a still-loading interpreter); the caller simply gets no
  /// result for [request]. Errors are thrown and never kill the worker.
  Future<FrameResult?> process(FrameRequest request);

  Future<void> dispose();
}

/// Production processor: conversion in a long-lived isolate, inference in
/// tflite_flutter's own isolate, postprocessing on the main isolate.
class IsolateFrameProcessor implements FrameProcessor {
  IsolateFrameProcessor({
    required Uint8List modelBytes,
    required List<String> labels,
    String? modelAsset = 'assets/ml/yolov8nV5.tflite',
  }) : _modelBytes = modelBytes,
       _labels = List<String>.unmodifiable(labels),
       _modelAsset = modelAsset;

  final Uint8List _modelBytes;
  final List<String> _labels;
  final String? _modelAsset;

  final _SerialQueue _queue = _SerialQueue();
  final Map<int, Completer<ConversionResponse>> _pending =
      <int, Completer<ConversionResponse>>{};

  Interpreter? _interpreter;
  IsolateInterpreter? _inference;
  ReceivePort? _fromWorker;
  Isolate? _worker;
  SendPort? _toWorker;
  Float32List? _output;
  int _dim1 = 0;
  int _dim2 = 0;
  bool _initialized = false;
  bool _disposed = false;
  Future<void>? _initializing;

  @override
  Future<void> initialize() async {
    if (_disposed) {
      throw StateError('IsolateFrameProcessor is disposed');
    }
    if (_initialized) {
      return;
    }
    final Future<void>? pending = _initializing;
    if (pending != null) {
      await pending;
      return;
    }
    final Future<void> future = _initializeOnce();
    _initializing = future;
    try {
      await future;
      _initialized = true;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _initializeOnce() async {
    if (_modelBytes.isEmpty) {
      throw StateError('model bytes are empty');
    }
    if (_labels.isEmpty) {
      throw StateError('no class labels were supplied');
    }

    final InterpreterOptions options = InterpreterOptions()..threads = 4;
    final Interpreter interpreter = Interpreter.fromBuffer(
      _modelBytes,
      options: options,
    );
    options.delete();

    IsolateInterpreter? inference;
    ReceivePort? fromWorker;
    Isolate? worker;
    try {
      final List<int> inputShape = interpreter.getInputTensor(0).shape;
      if (inputShape.length != 4 ||
          inputShape[0] != 1 ||
          inputShape[1] != DetectionConstants.inputSize ||
          inputShape[2] != DetectionConstants.inputSize ||
          inputShape[3] != 3) {
        throw StateError('unexpected model input shape: $inputShape');
      }

      final List<int> outputShape = interpreter.getOutputTensor(0).shape;
      if (outputShape.length < 2) {
        throw StateError('unexpected model output shape: $outputShape');
      }
      final int dim1 = outputShape[outputShape.length - 2];
      final int dim2 = outputShape[outputShape.length - 1];
      final YoloLayout layout = detectLayout(dim1, dim2, _labels.length);
      final int channels = layout == YoloLayout.channelsFirst ? dim1 : dim2;
      final int classStart = channels - 5 == _labels.length ? 5 : 4;
      if (channels - classStart != _labels.length) {
        throw StateError(
          'model outputs ${channels - classStart} classes but '
          '${_labels.length} labels were supplied'
          '${_modelAsset == null ? '' : ' for $_modelAsset'}',
        );
      }

      inference = await IsolateInterpreter.create(address: interpreter.address);

      fromWorker = ReceivePort();
      final Completer<SendPort> ready = Completer<SendPort>();
      fromWorker.listen((Object? message) {
        if (message is SendPort) {
          if (!ready.isCompleted) {
            ready.complete(message);
          }
          return;
        }
        if (message is ConversionResponse) {
          _pending.remove(message.id)?.complete(message);
          return;
        }
        if (message is List<Object?> && message.length == 2) {
          _failPending(
            StateError('conversion isolate failed: ${message.first}'),
          );
        }
      });

      worker = await Isolate.spawn<SendPort>(
        conversionWorkerMain,
        fromWorker.sendPort,
        debugName: 'BlindSpotFrameConverter',
      );
      worker.addErrorListener(fromWorker.sendPort);
      final SendPort toWorker = await ready.future;

      if (_disposed) {
        throw StateError('disposed during initialize');
      }

      _interpreter = interpreter;
      _inference = inference;
      _fromWorker = fromWorker;
      _worker = worker;
      _toWorker = toWorker;
      _dim1 = dim1;
      _dim2 = dim2;
      _output = Float32List(dim1 * dim2);
    } catch (error, stackTrace) {
      _failPending(StateError('conversion worker unavailable: $error'));
      await inference?.close();
      worker?.kill(priority: Isolate.immediate);
      fromWorker?.close();
      interpreter.close();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _failPending(Object error) {
    final List<Completer<ConversionResponse>> pending = _pending.values.toList(
      growable: false,
    );
    _pending.clear();
    for (final Completer<ConversionResponse> completer in pending) {
      completer.completeError(error);
    }
  }

  @override
  Future<FrameResult?> process(FrameRequest request) {
    return _queue.run<FrameResult?>(() => _processNow(request));
  }

  Future<FrameResult?> _processNow(FrameRequest request) async {
    if (_disposed) {
      throw StateError('IsolateFrameProcessor is disposed');
    }
    final IsolateInterpreter? inference = _inference;
    final SendPort? toWorker = _toWorker;
    final Float32List? output = _output;
    if (!_initialized ||
        inference == null ||
        toWorker == null ||
        output == null) {
      throw StateError('IsolateFrameProcessor.initialize() must complete');
    }
    // A run dispatched into a loading interpreter returns silently and
    // would leave the previous frame's values in the output buffer.
    if (inference.state != IsolateInterpreterState.idle) {
      return null;
    }

    final Stopwatch total = Stopwatch()..start();

    final Completer<ConversionResponse> conversion =
        Completer<ConversionResponse>();
    _pending[request.frameId] = conversion;
    toWorker.send(
      ConversionRequest.fromPlanes(id: request.frameId, planes: request.planes),
    );
    final ConversionResponse converted;
    try {
      converted = await conversion.future;
    } finally {
      _pending.remove(request.frameId);
    }
    if (converted.error != null) {
      throw Exception('frame conversion failed: ${converted.error}');
    }
    final TransferableTypedData? pixels = converted.pixels;
    if (pixels == null) {
      throw StateError('frame conversion returned no pixels');
    }
    final Float32List input = pixels.materialize().asFloat32List();
    final int convertMs = total.elapsedMilliseconds;

    if (inference.state != IsolateInterpreterState.idle) {
      return null;
    }

    final Stopwatch inferenceWatch = Stopwatch()..start();
    try {
      await inference.runForMultipleInputs(
        <Object>[Uint8List.view(input.buffer)],
        <int, Object>{0: Uint8List.view(output.buffer)},
      );
    } catch (error) {
      throw Exception('inference failed: $error');
    }
    final int inferenceMs = inferenceWatch.elapsedMilliseconds;

    final List<Detection> detections = postprocessYolo(
      output: output,
      dim1: _dim1,
      dim2: _dim2,
      labels: _labels,
      confidenceThreshold: DetectionConstants.confidenceBalanced,
    );

    return FrameResult(
      frameId: request.frameId,
      detections: detections,
      convertMs: convertMs,
      inferenceMs: inferenceMs,
      totalMs: total.elapsedMilliseconds,
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _failPending(StateError('IsolateFrameProcessor is disposed'));
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _fromWorker?.close();
    _fromWorker = null;
    _toWorker = null;
    final IsolateInterpreter? inference = _inference;
    _inference = null;
    await inference?.close();
    _interpreter?.close();
    _interpreter = null;
    _output = null;
    _initialized = false;
  }
}

/// Off-device double: records every call, serialises like the real
/// processor, and returns scripted results.
class FakeFrameProcessor implements FrameProcessor {
  FakeFrameProcessor({
    List<FrameResult>? script,
    this.delay = Duration.zero,
    this.respond,
  }) : _script = <FrameResult>[...?script];

  final List<FrameResult> _script;
  final Duration delay;

  /// Overrides the script when set; may throw to simulate a frame error.
  final FrameResult Function(FrameRequest request)? respond;

  final _SerialQueue _queue = _SerialQueue();

  final List<FrameRequest> requests = <FrameRequest>[];
  final List<int> startedFrameIds = <int>[];
  final List<int> completedFrameIds = <int>[];
  int initializeCalls = 0;
  int disposeCalls = 0;
  int active = 0;
  int maxConcurrent = 0;
  Object? initializeError;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    final Object? error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<FrameResult?> process(FrameRequest request) {
    requests.add(request);
    return _queue.run<FrameResult?>(() async {
      active++;
      if (active > maxConcurrent) {
        maxConcurrent = active;
      }
      startedFrameIds.add(request.frameId);
      try {
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        final FrameResult result = respond != null
            ? respond!(request)
            : (_script.isNotEmpty
                  ? _script.removeAt(0)
                  : FrameResult(
                      frameId: request.frameId,
                      detections: const <Detection>[],
                      convertMs: 0,
                      inferenceMs: 0,
                      totalMs: 0,
                    ));
        completedFrameIds.add(request.frameId);
        return result;
      } finally {
        active--;
      }
    });
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

/// Runs actions one at a time, in call order. A failing action completes
/// its own future with the error and leaves the queue usable.
class _SerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final Completer<T> completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
