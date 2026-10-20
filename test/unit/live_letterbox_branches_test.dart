// White-box unit tests: live preprocessing geometry
// Source: lib/detection/live_preprocess_isolate.dart
//
// Technique: branch + boundary-value coverage.
//   normalizeSensorAngle: all four return branches, each range edge
//   (44/45, 134/135, 224/225, 314/315), negative and > 360 inputs.
//   computeLiveLetterbox: angle 0/90/180/270 branches, preRotated branch,
//   which side limits the scale (min), upscale, and integer padding rounding.
//
//   UT-LB-01..08
import 'package:flutter_test/flutter_test.dart';
import 'package:system_application/detection/live_preprocess_isolate.dart';

void main() {
  test('UT-LB-01 normalizeSensorAngle: exact angles', () {
    expect(normalizeSensorAngle(0), 0);
    expect(normalizeSensorAngle(90), 90);
    expect(normalizeSensorAngle(180), 180);
    expect(normalizeSensorAngle(270), 270);
  });

  test('UT-LB-02 normalizeSensorAngle: range edges (boundary values)', () {
    expect(normalizeSensorAngle(44), 0);
    expect(normalizeSensorAngle(45), 90);
    expect(normalizeSensorAngle(134), 90);
    expect(normalizeSensorAngle(135), 180);
    expect(normalizeSensorAngle(224), 180);
    expect(normalizeSensorAngle(225), 270);
    expect(normalizeSensorAngle(314), 270);
    expect(normalizeSensorAngle(315), 0);
    expect(normalizeSensorAngle(359), 0);
  });

  test('UT-LB-03 normalizeSensorAngle: wraps negative and >= 360 inputs', () {
    expect(normalizeSensorAngle(360), 0);
    expect(normalizeSensorAngle(450), 90);
    expect(normalizeSensorAngle(-90), 270);
    expect(normalizeSensorAngle(-180), 180);
    expect(normalizeSensorAngle(-360), 0);
  });

  test('UT-LB-04 landscape frame, angle 0/180: no swap, height is padded', () {
    for (final angle in [0, 180]) {
      final b = computeLiveLetterbox(
        cameraWidth: 1280,
        cameraHeight: 720,
        sensorOrientation: angle,
        inputSize: 640,
      );
      expect(b.frameWidth, 1280, reason: 'angle $angle');
      expect(b.frameHeight, 720, reason: 'angle $angle');
      expect(b.scale, 0.5);
      expect(b.nw, 640);
      expect(b.nh, 360);
      expect(b.padX, 0);
      expect(b.padY, 140);
    }
  });

  test('UT-LB-05 angle 270 swaps width/height like angle 90', () {
    final b90 = computeLiveLetterbox(
        cameraWidth: 1280, cameraHeight: 720, sensorOrientation: 90, inputSize: 640);
    final b270 = computeLiveLetterbox(
        cameraWidth: 1280, cameraHeight: 720, sensorOrientation: 270, inputSize: 640);
    expect(b270.frameWidth, 720);
    expect(b270.frameHeight, 1280);
    expect(b270.nw, b90.nw);
    expect(b270.nh, b90.nh);
    expect(b270.padX, b90.padX);
    expect(b270.padY, b90.padY);
  });

  test('UT-LB-06 preRotated ignores sensorOrientation', () {
    final b = computeLiveLetterbox(
      cameraWidth: 1280,
      cameraHeight: 720,
      sensorOrientation: 90, // would swap if preRotated were false
      inputSize: 640,
      preRotated: true,
    );
    expect(b.frameWidth, 1280);
    expect(b.frameHeight, 720);
  });

  test('UT-LB-07 square frame fills the input; small frame is upscaled', () {
    final sq = computeLiveLetterbox(
        cameraWidth: 640, cameraHeight: 640, sensorOrientation: 0, inputSize: 640);
    expect(sq.scale, 1.0);
    expect(sq.padX, 0);
    expect(sq.padY, 0);

    final small = computeLiveLetterbox(
        cameraWidth: 320, cameraHeight: 240, sensorOrientation: 0, inputSize: 640);
    expect(small.scale, 2.0); // limited by width: min(2.0, 2.667)
    expect(small.nw, 640);
    expect(small.nh, 480);
    expect(small.padY, 80);
  });

  test('UT-LB-08 rounding: odd padding floors, content always fits', () {
    final b = computeLiveLetterbox(
        cameraWidth: 600, cameraHeight: 400, sensorOrientation: 0, inputSize: 640);
    expect(b.nw, 640);
    expect(b.nh, 427); // 400 * 1.0667 = 426.67 -> 427
    expect(b.padY, 106); // (640 - 427) ~/ 2 = 106 (floors)
    expect(b.padX, 0);
    // Invariant for any frame: padding + content never exceeds the input.
    for (final size in [
      [1920, 1080],
      [1280, 720],
      [640, 480],
      [3000, 1000],
      [123, 457],
    ]) {
      for (final angle in [0, 90, 180, 270]) {
        final r = computeLiveLetterbox(
            cameraWidth: size[0],
            cameraHeight: size[1],
            sensorOrientation: angle,
            inputSize: 640);
        expect(r.padX * 2 + r.nw, lessThanOrEqualTo(640),
            reason: '$size @ $angle');
        expect(r.padY * 2 + r.nh, lessThanOrEqualTo(640),
            reason: '$size @ $angle');
        expect(r.padX, greaterThanOrEqualTo(0));
        expect(r.padY, greaterThanOrEqualTo(0));
      }
    }
  });
}