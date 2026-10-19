import 'dart:typed_data';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:system_application/detection/live_preprocess_isolate.dart';

void main() {
  test('letterbox contract matches rotate-then-min-scale for 1280x720 @ 90°', () {
    final box = computeLiveLetterbox(
      cameraWidth: 1280,
      cameraHeight: 720,
      sensorOrientation: 90,
      inputSize: 640,
    );
    expect(box.frameWidth, 720);
    expect(box.frameHeight, 1280);
    expect(box.scale, 640 / 1280);
    expect(box.nw, 360);
    expect(box.nh, 640);
    expect(box.padX, 140);
    expect(box.padY, 0);
  });

  test('iOS pre-rotated portrait frame is not rotated again', () {
    final box = computeLiveLetterbox(
      cameraWidth: 720,
      cameraHeight: 1280,
      sensorOrientation: 90,
      inputSize: 640,
      preRotated: true,
    );
    expect(box.frameWidth, 720);
    expect(box.frameHeight, 1280);
    expect(box.scale, 640 / 1280);
    expect(box.padX, 140);
    expect(box.padY, 0);
  });

  test('one-pass YUV fills pad color and samples content', () {
    const w = 8;
    const h = 6;
    final y = Uint8List(w * h)..fillRange(0, w * h, 128);
    final u = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
    final v = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
    y[0] = 255;

    final result = preprocessOnePass({
      'planes': [
        TransferableTypedData.fromList([y]),
        TransferableTypedData.fromList([u]),
        TransferableTypedData.fromList([v]),
      ],
      'planeMeta': [
        {'bytesPerRow': w, 'bytesPerPixel': 1},
        {'bytesPerRow': w ~/ 2, 'bytesPerPixel': 1},
        {'bytesPerRow': w ~/ 2, 'bytesPerPixel': 1},
      ],
      'width': w,
      'height': h,
      'format': 'yuv420',
      'sensorOrientation': 0,
      'inputSize': 16,
    });

    expect(result['ok'], true);
    expect(result['frameWidth'], w);
    expect(result['frameHeight'], h);
    final ttd = result['inputData'] as TransferableTypedData;
    final data = ttd.materialize().asFloat32List();
    expect(data.length, 3 * 16 * 16);
    // Corner pad (letterbox) stays 114/255.
    expect(data[0], closeTo(114 / 255.0, 1e-6));
  });

  test('one-pass BGRA8888 uses R from byte 2 and keeps letterbox meta', () {
    const w = 4;
    const h = 4;
    final bytes = Uint8List(w * h * 4);
    for (int i = 0; i < w * h; i++) {
      bytes[i * 4] = 10; // B
      bytes[i * 4 + 1] = 20; // G
      bytes[i * 4 + 2] = 30; // R
      bytes[i * 4 + 3] = 255;
    }
    final result = preprocessOnePass({
      'planes': [TransferableTypedData.fromList([bytes])],
      'planeMeta': [
        {'bytesPerRow': w * 4, 'bytesPerPixel': 4},
      ],
      'width': w,
      'height': h,
      'format': 'bgra8888',
      'sensorOrientation': 0,
      'inputSize': 8,
    });
    expect(result['ok'], true);
    expect(result['frameWidth'], w);
    expect(result['frameHeight'], h);
    final data =
        (result['inputData'] as TransferableTypedData).materialize().asFloat32List();
    final padX = (result['padX'] as double).toInt();
    final padY = (result['padY'] as double).toInt();
    final offset = padY * 8 + padX;
    expect(data[offset], closeTo(30 / 255.0, 1e-6));
    expect(data[8 * 8 + offset], closeTo(20 / 255.0, 1e-6));
    expect(data[2 * 8 * 8 + offset], closeTo(10 / 255.0, 1e-6));
  });

  test('one-pass 1280x720 yuv420 preprocess is well under 1s on host', () {
    const w = 1280;
    const h = 720;
    final y = Uint8List(w * h);
    final u = Uint8List((w ~/ 2) * (h ~/ 2));
    final v = Uint8List((w ~/ 2) * (h ~/ 2));
    for (int i = 0; i < y.length; i++) {
      y[i] = i % 256;
    }
    u.fillRange(0, u.length, 128);
    v.fillRange(0, v.length, 128);

    Map<String, dynamic> msg() => {
          'planes': [
            TransferableTypedData.fromList([Uint8List.fromList(y)]),
            TransferableTypedData.fromList([Uint8List.fromList(u)]),
            TransferableTypedData.fromList([Uint8List.fromList(v)]),
          ],
          'planeMeta': [
            {'bytesPerRow': w, 'bytesPerPixel': 1},
            {'bytesPerRow': w ~/ 2, 'bytesPerPixel': 1},
            {'bytesPerRow': w ~/ 2, 'bytesPerPixel': 1},
          ],
          'width': w,
          'height': h,
          'format': 'yuv420',
          'sensorOrientation': 90,
          'inputSize': 640,
        };

    // Warmup
    preprocessOnePass(msg());

    final sw = Stopwatch()..start();
    const n = 5;
    for (int i = 0; i < n; i++) {
      final r = preprocessOnePass(msg());
      expect(r['ok'], true);
      expect(r['padX'], 140);
      expect(r['padY'], 0);
    }
    final avgMs = sw.elapsedMicroseconds / 1000.0 / n;
    // Host desktop; phone will be slower, but this must not be hundreds of ms.
    expect(avgMs, lessThan(200));
    // ignore: avoid_print
    print('one-pass preprocess avg ${avgMs.toStringAsFixed(1)}ms');
  });
}
