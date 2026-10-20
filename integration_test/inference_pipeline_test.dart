// Integration tests: capture -> preprocess -> ONNX inference -> decode
//
// Runs the REAL models on the device through the same entry point the
// Capture / Gallery flow uses: inferenceService.analyzeImage(path).
//
// What this proves: the pipeline runs end to end and every result respects
// the data contract the UI depends on (class names, coordinate spaces,
// letterbox math, thresholds).
//
// What this does NOT prove: that the model is ACCURATE. Accuracy (precision,
// recall, mAP, confusion matrix, mask IoU/Dice) needs a labeled held-out set
// and belongs to model validation. IT-PL-06 only PRINTS expected-vs-predicted
// for any sample photos you add; it does not pass or fail on accuracy.
//
//   IT-PL-01  analyzeImage on a sharp synthetic image: result contract
//   IT-PL-02  letterbox metadata is exact for a known image size
//   IT-PL-03  flat (blurry) image is rejected with the blur message
//   IT-PL-04  undecodable file fails cleanly (no crash)
//   IT-PL-05  same input gives the same output (determinism, no state leak)
//   IT-PL-06  optional real sample photos: invariants + expected vs predicted
//   IT-PL-07  latency distribution of analyzeImage (measured, not asserted)
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:system_application/detection/inference_service.dart';

const _classNames = {'Healthy', 'Pest-Damaged', 'Wilting', 'Yellowing'};
const _samplePrefix = 'integration_test/samples/';

late Directory _tmp;

Future<String> _writeJpg(img.Image im, String name) async {
  final f = File('${_tmp.path}/$name');
  await f.writeAsBytes(img.encodeJpg(im, quality: 95));
  return f.path;
}

/// High-frequency noise: passes the blur gate (Laplacian variance is high).
img.Image _noise(int w, int h, {int seed = 1}) {
  final r = Random(seed);
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      im.setPixelRgb(x, y, r.nextInt(256), r.nextInt(256), r.nextInt(256));
    }
  }
  return im;
}

/// Uniform colour: Laplacian variance is 0, so it must be rejected as blurry.
img.Image _flat(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(120, 160, 90));
  return im;
}

/// Contract every returned detection must satisfy, whatever the image.
void _expectValidDetections(ImageAnalysisResult res, {String reason = ''}) {
  final size = InferenceService.inputSize.toDouble();
  for (final d in res.detections) {
    final why = '$reason ${d.className}';
    expect(_classNames, contains(d.className), reason: why);
    expect(d.saplingClass, isNotNull, reason: why);
    expect(d.confidence, inInclusiveRange(InferenceService.confThreshold, 1.0),
        reason: why);
    expect(d.healthScore, inInclusiveRange(0.0, 100.0), reason: why);
    expect(d.recommendation, isNot('No recommendation available.'),
        reason: why);

    // Box is in letterbox (640x640) model space.
    if (d.bboxLeft != null) {
      expect(d.bboxLeft!, lessThan(d.bboxRight!), reason: why);
      expect(d.bboxTop!, lessThan(d.bboxBottom!), reason: why);
      expect(d.bboxLeft!, greaterThanOrEqualTo(-1), reason: why);
      expect(d.bboxTop!, greaterThanOrEqualTo(-1), reason: why);
      expect(d.bboxRight!, lessThanOrEqualTo(size + 1), reason: why);
      expect(d.bboxBottom!, lessThanOrEqualTo(size + 1), reason: why);
      final area = (d.bboxRight! - d.bboxLeft!) * (d.bboxBottom! - d.bboxTop!);
      expect(area, greaterThanOrEqualTo(InferenceService.minBoxAreaPx * 0.9),
          reason: why);
      expect(area, lessThanOrEqualTo(InferenceService.maxBoxAreaPx * 1.1),
          reason: why);
    }

    // Mask outline is a polygon in the same space.
    final poly = d.maskPolygon;
    if (poly != null) {
      expect(poly.length, greaterThanOrEqualTo(3), reason: why);
      for (final p in poly) {
        expect(p.length, 2, reason: why);
        expect(p[0], inInclusiveRange(-1.0, size + 1), reason: why);
        expect(p[1], inInclusiveRange(-1.0, size + 1), reason: why);
      }
    }
  }
}

double _percentile(List<int> sorted, double p) =>
    sorted[(p * (sorted.length - 1)).round()].toDouble();

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _tmp = await Directory(
            '${(await getTemporaryDirectory()).path}/it_pipeline')
        .create(recursive: true);
    await inferenceService.loadModel();
  });

  tearDownAll(() async {
    if (await _tmp.exists()) await _tmp.delete(recursive: true);
  });

  test('IT-PL-01 sharp synthetic image: result contract holds', () async {
    final path = await _writeJpg(_noise(800, 600), 'noise_800x600.jpg');
    final res = await inferenceService.analyzeImage(path);

    expect(res.displayBytes, isNotEmpty);
    expect(res.displayWidth, greaterThan(0));
    expect(res.displayHeight, greaterThan(0));
    // The display JPEG must decode and match the size it claims.
    final decoded = img.decodeImage(res.displayBytes)!;
    expect(decoded.width, res.displayWidth);
    expect(decoded.height, res.displayHeight);
    _expectValidDetections(res, reason: 'synthetic noise');
    // Random noise should not look like a calamansi sapling; report, don't
    // fail, because that is a model-quality statement.
    // ignore: avoid_print
    print('IT-PL-01 detections on noise: ${res.detections.length}');
  });

  test('IT-PL-02 letterbox metadata is exact for a known size', () async {
    final path = await _writeJpg(_noise(800, 600), 'noise_800x600_b.jpg');
    final res = await inferenceService.analyzeImage(path);

    expect(res.imageWidth, 800);
    expect(res.imageHeight, 600);
    expect(res.letterboxScale, closeTo(0.8, 1e-9)); // 640 / 800
    expect(res.padX, 0);
    expect(res.padY, 80); // (640 - 480) / 2

    final tall = await _writeJpg(_noise(600, 800), 'noise_600x800.jpg');
    final r2 = await inferenceService.analyzeImage(tall);
    expect(r2.letterboxScale, closeTo(0.8, 1e-9));
    expect(r2.padX, 80);
    expect(r2.padY, 0);
  });

  test('IT-PL-03 flat image is rejected as too blurry', () async {
    final path = await _writeJpg(_flat(640, 480), 'flat.jpg');
    await expectLater(
      inferenceService.analyzeImage(path),
      throwsA(predicate(
          (e) => e.toString().toLowerCase().contains('too blurry'))),
    );
  });

  test('IT-PL-04 a file that is not an image fails, and the service recovers',
      () async {
    final f = File('${_tmp.path}/not_an_image.jpg');
    await f.writeAsBytes([1, 2, 3, 4, 5, 6, 7, 8]);
    await expectLater(inferenceService.analyzeImage(f.path), throwsA(anything));
    // The service must still work afterwards.
    final ok = await _writeJpg(_noise(320, 240, seed: 3), 'after_error.jpg');
    final res = await inferenceService.analyzeImage(ok);
    expect(res.imageWidth, 320);
  });

  test('IT-PL-05 same input twice gives identical detections', () async {
    final path = await _writeJpg(_noise(640, 640, seed: 7), 'det.jpg');
    final a = await inferenceService.analyzeImage(path);
    final b = await inferenceService.analyzeImage(path);

    expect(b.detections.length, a.detections.length);
    for (var i = 0; i < a.detections.length; i++) {
      expect(b.detections[i].className, a.detections[i].className);
      expect(b.detections[i].confidence,
          closeTo(a.detections[i].confidence, 1e-6));
      expect(b.detections[i].bboxLeft, a.detections[i].bboxLeft);
    }
  });

  test('IT-PL-06 sample photos (optional): invariants + expected vs predicted',
      () async {
    // Add photos named  <class>_<n>.jpg  to integration_test/samples/  where
    // <class> is healthy | yellowing | pest | wilting  (e.g. wilting_03.jpg),
    // and list the folder under `assets:` in pubspec.yaml.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final samples = manifest
        .listAssets()
        .where((a) =>
            a.startsWith(_samplePrefix) &&
            RegExp(r'\.(jpe?g|png)$', caseSensitive: false).hasMatch(a))
        .toList()
      ..sort();
    if (samples.isEmpty) {
      markTestSkipped('No sample photos in $_samplePrefix (see header).');
      return;
    }

    final rows = <String>[];
    for (final asset in samples) {
      final name = asset.split('/').last;
      final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
      final f = File('${_tmp.path}/$name');
      await f.writeAsBytes(bytes);

      ImageAnalysisResult res;
      try {
        res = await inferenceService.analyzeImage(f.path);
      } catch (e) {
        rows.add('$name | expected ${name.split('_').first} | ERROR: $e');
        continue;
      }
      _expectValidDetections(res, reason: name);

      final expected = name.split('_').first.toLowerCase();
      final predicted = res.detections.isEmpty
          ? 'no detection'
          : (res.detections.toList()
                ..sort((a, b) => b.confidence.compareTo(a.confidence)))
              .first
              .className;
      rows.add('$name | expected $expected | predicted $predicted '
          '| ${res.detections.length} detection(s)');
    }
    // ignore: avoid_print
    print('IT-PL-06 expected vs predicted (NOT an accuracy metric):\n'
        '${rows.join('\n')}');
    binding.reportData = {...?binding.reportData, 'IT-PL-06': rows};
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('IT-PL-07 latency of analyzeImage on this device', () async {
    final path = await _writeJpg(_noise(1280, 960, seed: 11), 'lat.jpg');
    await inferenceService.analyzeImage(path); // warm-up, not counted

    const runs = 15;
    final ms = <int>[];
    for (var i = 0; i < runs; i++) {
      final sw = Stopwatch()..start();
      await inferenceService.analyzeImage(path);
      sw.stop();
      ms.add(sw.elapsedMilliseconds);
    }
    ms.sort();
    final stats = {
      'runs': runs,
      'min_ms': ms.first,
      'median_ms': _percentile(ms, 0.5),
      'p95_ms': _percentile(ms, 0.95),
      'max_ms': ms.last,
      'scope': 'analyzeImage end-to-end (decode + preprocess isolate + '
          'inference + decode + mask outline) on a 1280x960 JPEG',
    };
    // ignore: avoid_print
    print('IT-PL-07 latency: $stats');
    binding.reportData = {...?binding.reportData, 'IT-PL-07': stats};

    // Only a hang guard. No performance target is asserted because none has
    // been measured yet; use the printed numbers for the report.
    expect(ms.last, lessThan(30000), reason: 'analyzeImage hung or crawled');
  }, timeout: const Timeout(Duration(minutes: 5)));
}