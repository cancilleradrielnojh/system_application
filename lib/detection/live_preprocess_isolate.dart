import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

/// Same letterbox geometry as the previous img.copyResize path:
/// scale = min(input/uprightW, input/uprightH), nw/nh rounded, pad via ~/ 2.
class LiveLetterbox {
  final int frameWidth;
  final int frameHeight;
  final int nw;
  final int nh;
  final double scale;
  final double padX;
  final double padY;

  const LiveLetterbox({
    required this.frameWidth,
    required this.frameHeight,
    required this.nw,
    required this.nh,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}

LiveLetterbox computeLiveLetterbox({
  required int cameraWidth,
  required int cameraHeight,
  required int sensorOrientation,
  required int inputSize,
  bool preRotated = false,
}) {
  final angle = preRotated ? 0 : normalizeSensorAngle(sensorOrientation);
  final int frameWidth;
  final int frameHeight;
  if (angle == 90 || angle == 270) {
    frameWidth = cameraHeight;
    frameHeight = cameraWidth;
  } else {
    frameWidth = cameraWidth;
    frameHeight = cameraHeight;
  }
  final double scale = min(inputSize / frameWidth, inputSize / frameHeight);
  final int nw = (frameWidth * scale).round();
  final int nh = (frameHeight * scale).round();
  final int padXi = (inputSize - nw) ~/ 2;
  final int padYi = (inputSize - nh) ~/ 2;
  return LiveLetterbox(
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    nw: nw,
    nh: nh,
    scale: scale,
    padX: padXi.toDouble(),
    padY: padYi.toDouble(),
  );
}

int normalizeSensorAngle(int sensorOrientation) {
  var a = sensorOrientation % 360;
  if (a < 0) a += 360;
  if (a >= 45 && a < 135) return 90;
  if (a >= 135 && a < 225) return 180;
  if (a >= 225 && a < 315) return 270;
  return 0;
}

@pragma('vm:entry-point')
void livePreprocessIsolateMain(SendPort handshake) {
  final commands = ReceivePort();
  handshake.send(commands.sendPort);

  commands.listen((raw) {
    if (raw is! Map) return;
    final msg = Map<String, dynamic>.from(raw);
    final cmd = msg['cmd'];
    if (cmd == 'shutdown') {
      commands.close();
      Isolate.exit();
    }
    if (cmd != 'process') return;

    final SendPort reply = msg['reply'] as SendPort;
    try {
      reply.send(preprocessOnePass(msg));
    } catch (e) {
      reply.send(<String, dynamic>{'ok': false, 'error': e.toString()});
    }
  });
}

/// One-pass YUV/BGRA → rotate → letterbox → CHW float tensor.
/// [format] is `'yuv420'` or `'bgra8888'`.
Map<String, dynamic> preprocessOnePass(Map<String, dynamic> msg) {
  final planeTtds = (msg['planes'] as List).cast<TransferableTypedData>();
  final planeMeta = (msg['planeMeta'] as List).cast<Map>();
  final planes = <Uint8List>[];
  for (final ttd in planeTtds) {
    planes.add(ttd.materialize().asUint8List());
  }

  final width = msg['width'] as int;
  final height = msg['height'] as int;
  final format = msg['format'] as String;
  final sensorOrientation = msg['sensorOrientation'] as int;
  final inputSize = msg['inputSize'] as int;

  // iOS (BGRA8888) frames can arrive already upright (portrait: height > width).
  // Rotating them again by the sensor orientation turns the image sideways and
  // the model finds nothing. Android YUV420 frames are unaffected by this rule.
  final bool preRotated = format == 'bgra8888' && height > width;
  final box = computeLiveLetterbox(
    cameraWidth: width,
    cameraHeight: height,
    sensorOrientation: sensorOrientation,
    inputSize: inputSize,
    preRotated: preRotated,
  );
  final angle = preRotated ? 0 : normalizeSensorAngle(sensorOrientation);

  const padColor = 114.0 / 255.0;
  final data = Float32List(3 * inputSize * inputSize);
  data.fillRange(0, data.length, padColor);

  final planeSize = inputSize * inputSize;
  final padXi = box.padX.toInt();
  final padYi = box.padY.toInt();
  final nw = box.nw;
  final nh = box.nh;
  final uprightW = box.frameWidth;
  final uprightH = box.frameHeight;

  if (nw <= 0 || nh <= 0) {
    return <String, dynamic>{'ok': false};
  }

  late final void Function(int cx, int cy, int offset) writeSample;
  if (format == 'bgra8888') {
    final bytes = planes.first;
    final meta = planeMeta.first;
    final rowStride = meta['bytesPerRow'] as int;
    // BGRA8888 is always 4 bytes per pixel. Do not read it from the plane
    // metadata: iOS reports bytesPerPixel as null, and the worker turns null
    // into 1, which made the sampler step 1 byte per pixel (a smeared image).
    const bpp = 4;
    writeSample = (cx, cy, offset) {
      final i = cy * rowStride + cx * bpp;
      if (i + 2 >= bytes.length) return;
      data[offset] = bytes[i + 2] / 255.0;
      data[planeSize + offset] = bytes[i + 1] / 255.0;
      data[2 * planeSize + offset] = bytes[i] / 255.0;
    };
  } else if (format == 'yuv420') {
    if (planes.length < 3) {
      return <String, dynamic>{'ok': false};
    }
    final yBytes = planes[0];
    final uBytes = planes[1];
    final vBytes = planes[2];
    final yRowStride = planeMeta[0]['bytesPerRow'] as int;
    final uvRowStride = planeMeta[1]['bytesPerRow'] as int;
    final uvPixelStride = (planeMeta[1]['bytesPerPixel'] as int?) ?? 1;
    writeSample = (cx, cy, offset) {
      final yi = cy * yRowStride + cx;
      if (yi >= yBytes.length) return;
      final uvi = (cy >> 1) * uvRowStride + (cx >> 1) * uvPixelStride;
      if (uvi >= uBytes.length || uvi >= vBytes.length) return;
      final yVal = yBytes[yi].toDouble();
      final uVal = uBytes[uvi].toDouble() - 128.0;
      final vVal = vBytes[uvi].toDouble() - 128.0;
      final r = (yVal + 1.402 * vVal).clamp(0.0, 255.0) / 255.0;
      final g =
          (yVal - 0.344136 * uVal - 0.714136 * vVal).clamp(0.0, 255.0) / 255.0;
      final b = (yVal + 1.772 * uVal).clamp(0.0, 255.0) / 255.0;
      data[offset] = r;
      data[planeSize + offset] = g;
      data[2 * planeSize + offset] = b;
    };
  } else {
    return <String, dynamic>{'ok': false};
  }

  for (int dy = 0; dy < nh; dy++) {
    final uy = (dy * uprightH) ~/ nh;
    final destY = padYi + dy;
    final rowOff = destY * inputSize;
    for (int dx = 0; dx < nw; dx++) {
      final ux = (dx * uprightW) ~/ nw;
      late final int cx;
      late final int cy;
      switch (angle) {
        case 90:
          cx = uy;
          cy = height - 1 - ux;
          break;
        case 270:
          cx = width - 1 - uy;
          cy = ux;
          break;
        case 180:
          cx = width - 1 - ux;
          cy = height - 1 - uy;
          break;
        default:
          cx = ux;
          cy = uy;
      }
      if (cx < 0 || cy < 0 || cx >= width || cy >= height) continue;
      writeSample(cx, cy, rowOff + padXi + dx);
    }
  }

  return <String, dynamic>{
    'ok': true,
    'inputData': TransferableTypedData.fromList([data]),
    'frameWidth': box.frameWidth,
    'frameHeight': box.frameHeight,
    'letterboxScale': box.scale,
    'padX': box.padX,
    'padY': box.padY,
    'diag': '$format ${width}x$height so$sensorOrientation rot$angle',
  };
}
