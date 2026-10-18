import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'live_preprocess_isolate.dart';

/// Long-lived isolate that converts a camera preview frame into a
/// letterboxed 640×640 CHW Float32 tensor. One request at a time;
/// the scanner never queues a second frame.
class LivePreprocessWorker {
  Isolate? _isolate;
  SendPort? _commands;
  Future<void>? _starting;
  Completer<Map<String, dynamic>?>? _pending;
  ReceivePort? _replyPort;
  int _generation = 0;

  bool get isRunning => _commands != null;

  Future<void> start() async {
    if (_commands != null) return;
    if (_starting != null) {
      await _starting;
      return;
    }
    _starting = _doStart();
    try {
      await _starting;
    } finally {
      _starting = null;
    }
  }

  Future<void> _doStart() async {
    final handshake = ReceivePort();
    try {
      _isolate = await Isolate.spawn(
        livePreprocessIsolateMain,
        handshake.sendPort,
        debugName: 'live-preprocess',
      );
      final first = await handshake.first;
      if (first is! SendPort) {
        throw StateError('Live preprocess isolate handshake failed');
      }
      _commands = first;
      _generation++;
    } catch (e) {
      debugPrint('Live preprocess isolate failed to start: $e');
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _commands = null;
      rethrow;
    } finally {
      handshake.close();
    }
  }

  /// Copies plane bytes once into [TransferableTypedData], then moves them
  /// to the worker (no second copy, no isolate respawn).
  Future<Map<String, dynamic>?> process({
    required CameraImage image,
    required int sensorOrientation,
    required int inputSize,
  }) async {
    if (_commands == null) {
      try {
        await start();
      } catch (_) {
        return null;
      }
    }
    final commands = _commands;
    if (commands == null) return null;

    if (_pending != null) return null;

    final format = image.format.group == ImageFormatGroup.bgra8888
        ? 'bgra8888'
        : 'yuv420';

    final planeTtds = <TransferableTypedData>[];
    final planeMeta = <Map<String, int>>[];
    for (final p in image.planes) {
      final src = p.bytes;
      final copy = Uint8List(src.length);
      copy.setRange(0, src.length, src);
      planeTtds.add(TransferableTypedData.fromList([copy]));
      planeMeta.add({
        'length': src.length,
        'bytesPerRow': p.bytesPerRow,
        'bytesPerPixel': p.bytesPerPixel ?? 1,
      });
    }

    final reply = ReceivePort();
    final pending = Completer<Map<String, dynamic>?>();
    _replyPort = reply;
    _pending = pending;
    final gen = _generation;

    reply.listen((msg) {
      if (pending.isCompleted) return;
      if (msg is Map<String, dynamic>) {
        pending.complete(msg);
      } else if (msg is Map) {
        pending.complete(Map<String, dynamic>.from(msg));
      } else {
        pending.complete(null);
      }
    });

    try {
      commands.send(<String, dynamic>{
        'cmd': 'process',
        'reply': reply.sendPort,
        'planes': planeTtds,
        'planeMeta': planeMeta,
        'width': image.width,
        'height': image.height,
        'format': format,
        'sensorOrientation': sensorOrientation,
        'inputSize': inputSize,
      });
      final result = await pending.future;
      if (gen != _generation) return null;
      if (result == null || result['ok'] != true) return null;

      final ttd = result['inputData'] as TransferableTypedData;
      final inputData = ttd.materialize().asFloat32List();
      return {
        'inputData': inputData,
        'frameWidth': result['frameWidth'] as int,
        'frameHeight': result['frameHeight'] as int,
        'letterboxScale': result['letterboxScale'] as double,
        'padX': result['padX'] as double,
        'padY': result['padY'] as double,
      };
    } catch (e) {
      debugPrint('Live preprocess request failed: $e');
      await stop();
      return null;
    } finally {
      if (identical(_replyPort, reply)) {
        _replyPort = null;
      }
      try {
        reply.close();
      } catch (_) {}
      if (identical(_pending, pending)) {
        _pending = null;
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
    _pending = null;
    try {
      _replyPort?.close();
    } catch (_) {}
    _replyPort = null;

    final commands = _commands;
    _commands = null;
    try {
      commands?.send(<String, dynamic>{'cmd': 'shutdown'});
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }
}
