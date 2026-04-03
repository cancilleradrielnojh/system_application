// ========================= lib/detection/inference_service.dart =========================
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

enum SaplingClass { healthy, pestDamaged, wilting, yellowing }

class DetectionResult {
  final SaplingClass? saplingClass;
  final double        confidence;
  final double        boxAreaPx;
  final bool          isCalamansi;

  //Secondary condition when two classes score above threshold.
  final SaplingClass? secondaryClass;
  final double?       secondaryConfidence;

  /// Bounding box in model input space (letterboxed 640×640), in pixels.
  final double? bboxLeft;
  final double? bboxTop;
  final double? bboxRight;
  final double? bboxBottom;

  DetectionResult({
    required this.saplingClass,
    required this.confidence,
    required this.boxAreaPx,
    required this.isCalamansi,
    this.secondaryClass,
    this.secondaryConfidence,
    this.bboxLeft,
    this.bboxTop,
    this.bboxRight,
    this.bboxBottom,
  });

  /// Input: internal enum value (`saplingClass`).
  /// Output: user-facing class label string.
  String get className {
    switch (saplingClass) {
      case SaplingClass.healthy:     return 'Healthy';
      case SaplingClass.pestDamaged: return 'Pest-Damaged';
      case SaplingClass.wilting:     return 'Wilting';
      case SaplingClass.yellowing:   return 'Yellowing';
      case null:                     return 'Unknown';
    }
  }

  /// Input: internal enum value (`saplingClass`).
  /// Output: class-specific recommendation text shown in UI.
  String get recommendation {
    switch (saplingClass) {
      case SaplingClass.healthy:
        return '- Keep 6-8 hours of morning sunlight when possible.\n'
            '- Water only when the top soil feels dry; avoid daily overwatering.\n'
            '- Add light compost or balanced citrus fertilizer every 3-4 weeks.\n'
            '- Remove weak inner shoots to improve airflow and prevent disease.';
      case SaplingClass.pestDamaged:
        return '- Remove heavily damaged leaves and dispose away from the nursery.\n'
            '- Spray neem oil or approved insecticidal soap in late afternoon.\n'
            '- Check underside of leaves every 2-3 days for eggs and soft pests.\n'
            '- Keep nearby weeds controlled to reduce pest hosts.';
      case SaplingClass.wilting:
        return '- Check root zone moisture first; wilt can come from both dry and soggy soil.\n'
            '- Improve drainage by loosening compacted media and clearing blocked holes.\n'
            '- Water deeply, then wait until topsoil dries before next watering.\n'
            '- Provide temporary partial shade during extreme midday heat.';
      case SaplingClass.yellowing:
        return '- Apply mild nitrogen feed or seaweed/compost tea at low dose.\n'
            '- Check pH (target around 5.5-6.5) to improve nutrient uptake.\n'
            '- Avoid waterlogging; keep moisture even but not saturated.\n'
            '- Prune severely yellow leaves after new healthy growth appears.';
      case null:
        return 'No recommendation available.';
    }
  }

  /// Input: detected class + confidence.
  /// Output: simple numeric health score for summaries/stats.
  double get healthScore {
    switch (saplingClass) {
      case SaplingClass.healthy:     return 90 + (confidence * 10).clamp(0, 10);
      case SaplingClass.yellowing:   return 60 + (confidence * 15).clamp(0, 15);
      case SaplingClass.wilting:     return 40 + (confidence * 20).clamp(0, 20);
      case SaplingClass.pestDamaged: return 20 + (confidence * 20).clamp(0, 20);
      case null:                     return 0;
    }
  }
}

class InferenceService {
  static const int inputSize = 640;

  // ── Confidence gates ──────────────────────────────────────────────────────
  static const double confThreshold             = 0.70;
  static const double calamansiPresenceThreshold = 0.85;

  //Minimum confidence for a secondary class to be reported.
  static const double secondaryClassThreshold   = 0.60;

  // ── NMS ───────────────────────────────────────────────────────────────────
  static const double iouThreshold = 0.60;

  // ── Box geometry filters ──────────────────────────────────────────────────
  static const double minBoxAreaPx   = 300;
  static const double maxBoxAreaPx   = 90000;
  static const double minSidePx      = 10;
  static const double maxSidePx      = 1024;
  static const double maxAspectRatio = 3.0;

  // ── Mask gating thresholds ────────────────────────────────────────────────
  static const double minMaskAreaRatioWithinBbox = 0.05;
  static const double minMaskMeanWithinBbox      = 0.18;

  // ── Blur detection ────────────────────────────────────────────────
  static const double blurThreshold = 80.0;

  OrtSession? _session;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  // ── loadModel ─────────────────────────────────────────────────────────────

  Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      final ort = OnnxRuntime();
      _session = await ort.createSessionFromAsset(
        'assets/models/best_flutter.onnx',
      );
      _isLoaded = true;
      debugPrint('✅ ONNX segmentation model loaded');
    } catch (e) {
      debugPrint('❌ Model load failed: $e');
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _isLoaded = false;
  }

  // ── analyzeImage ──────────────────────────────────────────────────────────

  Future<List<DetectionResult>> analyzeImage(String imagePath) async {
    if (!_isLoaded || _session == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    // Preprocess with EXIF rotation and blur check in isolate.
    final result = await compute<Map<String, dynamic>, Map<String, dynamic>>(
      _preprocessAndCheckIsolate,
      {
        'imagePath':    imagePath,
        'inputSize':    inputSize,
        'blurThreshold': blurThreshold,
      },
    );

    final isBlurry     = result['isBlurry']     as bool;
    final blurVariance = result['blurVariance']  as double;

    if (isBlurry) {
      debugPrint('⚠️  Image too blurry (variance=$blurVariance). Skipping inference.');
      throw Exception(
        'Image is too blurry (sharpness score: ${blurVariance.toStringAsFixed(1)}). '
        'Please retake the photo with better focus.',
      );
    }

    final inputData = result['inputData'] as List<double>;

    final inputTensor = await OrtValue.fromList(
      Float32List.fromList(inputData),
      [1, 3, inputSize, inputSize],
    );

    final inputs  = <String, OrtValue>{'images': inputTensor};
    final outputs = await _session!.run(inputs);

    // Named tensor lookup — output0 = [1,40,8400], output1 = [1,32,160,160]
    OrtValue? detValue   = outputs['output0'];
    OrtValue? protoValue = outputs['output1'];

    if (detValue == null || protoValue == null) {
      debugPrint('❌ Expected output keys "output0"/"output1" not found. '
          'Available keys: ${outputs.keys.toList()}');
      return const [];
    }

    final detShape   = detValue.shape;
    final protoShape = protoValue.shape;
    final rawDet = (await detValue.asFlattenedList())
        .map<double>((e) => (e as num).toDouble())
        .toList();
    final rawProto = (await protoValue.asFlattenedList())
        .map<double>((e) => (e as num).toDouble())
        .toList();

    await inputTensor.dispose();
    for (final out in outputs.values) {
      await out.dispose();
    }

    return _decodeOutput(rawDet, detShape, rawProto, protoShape);
  }

  // ── _decodeOutput ─────────────────────────────────────────────────────────

  List<DetectionResult> _decodeOutput(
    List<double> rawDet,
    List<int>    detShape,
    List<double> rawProto,
    List<int>    protoShape,
  ) {
    const numClasses  = 4;
    const numMaskCoef = 32;
    const rows        = 4 + numClasses + numMaskCoef; // 40

    if (detShape.length != 3) return const [];

    final bool rowFirst = detShape[1] == rows;
    if (!rowFirst && detShape[2] != rows) return const [];

    final int numAnchors = rowFirst ? detShape[2] : detShape[1];
    if (numAnchors <= 0) return const [];

    int idx(int row, int anchor) => rowFirst
        ? row * numAnchors + anchor
        : anchor * rows + row;

    final candidates = <_Candidate>[];

    for (int i = 0; i < numAnchors; i++) {
      final double cx = rawDet[idx(0, i)];
      final double cy = rawDet[idx(1, i)];
      final double w  = rawDet[idx(2, i)];
      final double h  = rawDet[idx(3, i)];

      final bool bboxIsNormalized =
          (w <= 1.0 && h <= 1.0 && cx.abs() <= 1.0 && cy.abs() <= 1.0);
      final double cxU = bboxIsNormalized ? (cx * inputSize) : cx;
      final double cyU = bboxIsNormalized ? (cy * inputSize) : cy;
      final double wU  = bboxIsNormalized ? (w  * inputSize) : w;
      final double hU  = bboxIsNormalized ? (h  * inputSize) : h;

      final double wAbs = wU.abs();
      final double hAbs = hU.abs();

      // Geometry filter
      final double areaPx = wAbs * hAbs;
      if (areaPx < minBoxAreaPx || areaPx > maxBoxAreaPx) continue;
      if (wAbs < minSidePx     || wAbs > maxSidePx)      continue;
      if (hAbs < minSidePx     || hAbs > maxSidePx)      continue;

      // Aspect ratio filter
      final double aspectRatio = max(wAbs, hAbs) / min(wAbs, hAbs);
      if (aspectRatio > maxAspectRatio) continue;

      //Track best AND second-best class scores per anchor(not implemented yet in the UI but only in logic)
      double maxScore  = 0; int maxClass  = 0;
      double sec2Score = 0; int sec2Class = 0;
      for (int c = 0; c < numClasses; c++) {
        final score = rawDet[idx(4 + c, i)];
        if (score > maxScore) {
          sec2Score = maxScore; sec2Class = maxClass;
          maxScore  = score;   maxClass  = c;
        } else if (score > sec2Score) {
          sec2Score = score;   sec2Class = c;
        }
      }

      if (maxScore >= confThreshold) {
        candidates.add(_Candidate(
          cx: cxU, cy: cyU, w: wAbs, h: hAbs,
          confidence:     maxScore,
          classIndex:     maxClass,
          areaPx:         areaPx,
          anchorIndex:    i,
          secondaryScore: sec2Score,
          secondaryClass: sec2Class,
        ));
      }
    }

    if (candidates.isEmpty) return const [];

    final kept = _nms(candidates);
    if (kept.isEmpty) return const [];

    final results      = <DetectionResult>[];
    int maskFailCount  = 0;
    int confPassCount  = 0;

    for (final c in kept) {
      if (c.confidence < calamansiPresenceThreshold) continue;

      confPassCount++;

      final bool maskOk = _maskLooksCalamansi(
        best:       c,
        rawDet:     rawDet,
        rawProto:   rawProto,
        detShape:   detShape,
        protoShape: protoShape,
      );
      if (!maskOk) {
        maskFailCount++;
        continue;
      }

      final double x1 = (c.cx - c.w / 2).clamp(0.0, inputSize - 1);
      final double y1 = (c.cy - c.h / 2).clamp(0.0, inputSize - 1);
      final double x2 = (c.cx + c.w / 2).clamp(0.0, inputSize - 1);
      final double y2 = (c.cy + c.h / 2).clamp(0.0, inputSize - 1);

      //Attach secondary condition if it clears the threshold (not implemented in UI but working in logic)
      SaplingClass? secondaryClass;
      double?       secondaryConfidence;
      if (c.secondaryScore >= secondaryClassThreshold &&
          c.secondaryClass != c.classIndex) {
        secondaryClass      = _toEnum(c.secondaryClass);
        secondaryConfidence = c.secondaryScore;
      }

      results.add(DetectionResult(
        saplingClass:        _toEnum(c.classIndex),
        confidence:          c.confidence,
        boxAreaPx:           c.areaPx,
        isCalamansi:         true,
        secondaryClass:      secondaryClass,
        secondaryConfidence: secondaryConfidence,
        bboxLeft:            x1,
        bboxTop:             y1,
        bboxRight:           x2,
        bboxBottom:          y2,
      ));
    }

    if (kDebugMode) {
      debugPrint(
        'Decode counts: candidates=${candidates.length}, kept=${kept.length}, '
        'confPass=$confPassCount, confFail=${kept.length - confPassCount}, '
        'maskFail=$maskFailCount, results=${results.length}',
      );
    }

    if (results.isEmpty) return const [];

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    const int maxDetectionsToReturn = 10;
    return results.length > maxDetectionsToReturn
        ? results.sublist(0, maxDetectionsToReturn)
        : results;
  }

  // ── _maskLooksCalamansi ───────────────────────────────────────────────────

  bool _maskLooksCalamansi({
    required _Candidate   best,
    required List<double> rawDet,
    required List<double> rawProto,
    required List<int>    detShape,
    required List<int>    protoShape,
  }) {
    if (protoShape.length != 4 || protoShape[1] != 32) return false;
    final int H = protoShape[2];
    final int W = protoShape[3];
    const int numClasses  = 4;
    const int numMaskCoef = 32;
    const int rows        = 4 + numClasses + numMaskCoef;

    final bool rowFirst  = detShape[1] == rows;
    if (!rowFirst && detShape[2] != rows) return false;
    final int numAnchors = rowFirst ? detShape[2] : detShape[1];

    int idxDet(int row, int anchor) => rowFirst
        ? row * numAnchors + anchor
        : anchor * rows + row;

    final List<double> coeffs = List<double>.filled(numMaskCoef, 0.0);
    for (int k = 0; k < numMaskCoef; k++) {
      coeffs[k] = rawDet[idxDet(4 + numClasses + k, best.anchorIndex)];
    }

    double x1 = best.cx - best.w / 2;
    double y1 = best.cy - best.h / 2;
    double x2 = best.cx + best.w / 2;
    double y2 = best.cy + best.h / 2;
    x1 = x1.clamp(0.0, inputSize - 1);
    y1 = y1.clamp(0.0, inputSize - 1);
    x2 = x2.clamp(0.0, inputSize - 1);
    y2 = y2.clamp(0.0, inputSize - 1);

    final int px1 = ((x1 / inputSize) * (W - 1)).floor().clamp(0, W - 1);
    final int px2 = ((x2 / inputSize) * (W - 1)).floor().clamp(0, W - 1);
    final int py1 = ((y1 / inputSize) * (H - 1)).floor().clamp(0, H - 1);
    final int py2 = ((y2 / inputSize) * (H - 1)).floor().clamp(0, H - 1);

    if (px2 <= px1 || py2 <= py1) return false;

    final int total = (px2 - px1 + 1) * (py2 - py1 + 1);
    int    countAbove = 0;
    double sumSig     = 0.0;

    int protoIndex(int k, int y, int x) => k * H * W + y * W + x;

    for (int y = py1; y <= py2; y++) {
      for (int x = px1; x <= px2; x++) {
        double v = 0.0;
        for (int k = 0; k < numMaskCoef; k++) {
          v += coeffs[k] * rawProto[protoIndex(k, y, x)];
        }
        final double sig = 1.0 / (1.0 + exp(-v));
        sumSig += sig;
        if (sig > 0.5) countAbove++;
      }
    }

    final double maskAreaRatio = countAbove / total;
    final double maskMean      = sumSig / total;

    if (kDebugMode) {
      debugPrint(
        'Mask gate: ratio=${maskAreaRatio.toStringAsFixed(3)}, '
        'mean=${maskMean.toStringAsFixed(3)}',
      );
    }

    return maskAreaRatio >= minMaskAreaRatioWithinBbox &&
        maskMean >= minMaskMeanWithinBbox;
  }

  // ── _nms ──────────────────────────────────────────────────────────────────

  List<_Candidate> _nms(List<_Candidate> list) {
    list.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <_Candidate>[];
    for (final c in list) {
      bool suppressed = false;
      for (final k in kept) {
        if (_iou(c, k) > iouThreshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) kept.add(c);
    }
    return kept;
  }

  // ── _iou ──────────────────────────────────────────────────────────────────

  double _iou(_Candidate a, _Candidate b) {
    final ax1 = a.cx - a.w / 2, ax2 = a.cx + a.w / 2;
    final ay1 = a.cy - a.h / 2, ay2 = a.cy + a.h / 2;
    final bx1 = b.cx - b.w / 2, bx2 = b.cx + b.w / 2;
    final by1 = b.cy - b.h / 2, by2 = b.cy + b.h / 2;
    final ix1 = max(ax1, bx1), ix2 = min(ax2, bx2);
    final iy1 = max(ay1, by1), iy2 = min(ay2, by2);
    if (ix2 <= ix1 || iy2 <= iy1) return 0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    final union = a.w * a.h + b.w * b.h - inter;
    return union <= 0 ? 0 : inter / union;
  }

  // ── _toEnum ───────────────────────────────────────────────────────────────

  SaplingClass _toEnum(int idx) {
    switch (idx) {
      case 0:  return SaplingClass.healthy;
      case 1:  return SaplingClass.pestDamaged;
      case 2:  return SaplingClass.wilting;
      case 3:  return SaplingClass.yellowing;
      default: return SaplingClass.healthy;
    }
  }
}

// ── _Candidate ────────────────────────────────────────────────────────────────

class _Candidate {
  final double cx, cy, w, h, confidence, areaPx;
  final int    classIndex, anchorIndex;
  final double secondaryScore;
  final int    secondaryClass;

  _Candidate({
    required this.cx,             required this.cy,
    required this.w,              required this.h,
    required this.confidence,     required this.classIndex,
    required this.areaPx,         required this.anchorIndex,
    required this.secondaryScore, required this.secondaryClass,
  });
}

// ── Singleton ─────────────────────────────────────────────────────────────────

final inferenceService = InferenceService();

// ── Isolate: (EXIF rotation) +  (blur detection) ──────────────────

/// Runs in a background isolate to avoid UI jank.
/// Applies bakeOrientation so portrait photos arrive upright.
/// Computes Laplacian variance; rejects images below blurThreshold.
/// Returns map with keys: inputData, isBlurry, blurVariance.
Map<String, dynamic> _preprocessAndCheckIsolate(Map<String, dynamic> args) {
  final String imagePath  = args['imagePath']     as String;
  final int    inputSize  = args['inputSize']     as int;
  final double blurThresh = args['blurThreshold'] as double;

  final bytes = File(imagePath).readAsBytesSync();
  final raw   = img.decodeImage(bytes);
  if (raw == null) throw Exception('Cannot decode image');

  ///EXIF rotation so the model always sees an upright image.
  final source = img.bakeOrientation(raw);

  ///Blur detection via Laplacian variance on a small greyscale copy.
  final grey     = img.grayscale(img.copyResize(source, width: 256));
  final variance = _laplacianVariance(grey);
  final isBlurry = variance < blurThresh;

  // Letterbox resize to inputSize × inputSize
  final double scale = min(inputSize / source.width, inputSize / source.height);
  final int nw = (source.width  * scale).round();
  final int nh = (source.height * scale).round();

  final img.Image resized = img.copyResize(source, width: nw, height: nh);
  final img.Image canvas  = img.Image(width: inputSize, height: inputSize);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(
    canvas, resized,
    dstX: (inputSize - nw) ~/ 2,
    dstY: (inputSize - nh) ~/ 2,
  );

  // CHW normalised float tensor
  final data = List<double>.filled(3 * inputSize * inputSize, 0.0);
  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final pixel      = canvas.getPixel(x, y);
      final int offset = y * inputSize + x;
      data[offset]                             = pixel.r / 255.0;
      data[inputSize * inputSize + offset]     = pixel.g / 255.0;
      data[2 * inputSize * inputSize + offset] = pixel.b / 255.0;
    }
  }

  return {
    'inputData':    data,
    'isBlurry':     isBlurry,
    'blurVariance': variance,
  };
}

/// Computes the variance of a discrete Laplacian applied to a greyscale image.
/// High variance = sharp edges = not blurry.
/// Low variance = smooth, uniform = blurry.
double _laplacianVariance(img.Image grey) {
  final int w = grey.width;
  final int h = grey.height;

  final values = <double>[];
  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      final double lap =
          4 * grey.getPixel(x,     y    ).r.toDouble() -
              grey.getPixel(x - 1, y    ).r.toDouble() -
              grey.getPixel(x + 1, y    ).r.toDouble() -
              grey.getPixel(x,     y - 1).r.toDouble() -
              grey.getPixel(x,     y + 1).r.toDouble();
      values.add(lap);
    }
  }
  if (values.isEmpty) return 0;
  final double mean = values.reduce((a, b) => a + b) / values.length;
  final double variance = values
      .map((v) => (v - mean) * (v - mean))
      .reduce((a, b) => a + b) / values.length;
  return variance;
}