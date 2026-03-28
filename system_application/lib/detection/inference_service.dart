// ========================= lib/detection/inference_service.dart =========================
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

enum SaplingClass { healthy, pestDamaged, wilting, yellowing }

class DetectionResult {
  final SaplingClass? saplingClass;
  final double confidence;
  final double boxAreaPx;
  final bool isCalamansi;

  /// Bounding box in **model input space** (letterboxed `640×640`), in pixels.
  /// Used to draw the overlay on the original photo. Null when not calamansi.
  final double? bboxLeft;
  final double? bboxTop;  
  final double? bboxRight;
  final double? bboxBottom;

  DetectionResult({
    required this.saplingClass,
    required this.confidence,
    required this.boxAreaPx,
    required this.isCalamansi,
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
  static const int    inputSize     = 640;
  // Decision thresholds affect false positives significantly.
  static const double confThreshold = 0.10;
  static const double calamansiPresenceThreshold = 0.30;
  static const double iouThreshold  = 0.60;
  static const double minBoxAreaPx  = 600;
  static const double maxBoxAreaPx  = 80000;
  static const double minSidePx     = 20;
  static const double maxSidePx     = 640;

  // Mask gating thresholds computed from the predicted instance mask.
  static const double minMaskAreaRatioWithinBbox = 0.005;
  static const double minMaskMeanWithinBbox      = 0.18;

  OrtSession? _session;
  bool _isLoaded = false;
  /// Output: whether the ONNX session is ready to run.
  bool get isLoaded => _isLoaded;

  /// Input: none.
  /// Output: initializes ONNX session from asset model file.
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

  /// Input: none.
  /// Output: closes and clears ONNX session resources.
  Future<void> dispose() async {
    await _session?.close();
    _session = null;
    _isLoaded = false;
  }

  /// Input: image file path.
  /// Output: filtered list of detections for that image.
  Future<List<DetectionResult>> analyzeImage(String imagePath) async {
    if (!_isLoaded || _session == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    final inputData = await compute<Map<String, dynamic>, List<double>>(
      _preprocessImageIsolate,
      {
        'imagePath': imagePath,
        'inputSize': inputSize,
      },
    );

    final inputTensor = await OrtValue.fromList(
      Float32List.fromList(inputData),
      [1, 3, inputSize, inputSize],
    );

    final inputs = <String, OrtValue>{
      'images': inputTensor,
    };

    final outputs = await _session!.run(inputs);

    OrtValue? detValue;
    OrtValue? protoValue;
    for (final entry in outputs.entries) {
      final shape = entry.value.shape;
      if (shape.length == 3 && shape[1] == 40) {
        detValue = entry.value;
      } else if (shape.length == 4 && shape[1] == 32) {
        protoValue = entry.value;
      }
    }

    if (detValue == null || protoValue == null) {
      // Output format isn't what we expect; fail safely.
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

    // Best-effort cleanup.
    await inputTensor.dispose();
    for (final out in outputs.values) {
      await out.dispose();
    }

    return _decodeOutput(rawDet, detShape, rawProto, protoShape);
  }

  // ── Decode segmentation output0 ───────────────────────────────────────
  // output0 shape: [1, 40, numAnchors] (ultralytics YOLO-seg)
  // output1 shape: [1, 32, 160, 160] (mask prototypes)
  /// Input: flattened model outputs (rawDet, rawProto) and their shapes.
  /// Output: final detection list after size/confidence filters, NMS, and mask gating.
  List<DetectionResult> _decodeOutput(
    List<double> rawDet,
    List<int> detShape,
    List<double> rawProto,
    List<int> protoShape,
  ) {
    const numClasses  = 4;
    const numMaskCoef = 32;
    const rows        = 4 + numClasses + numMaskCoef; // 40
    if (detShape.length != 3) return const [];

    // Determine whether rawDet layout is [1, rows, anchors] or [1, anchors, rows].
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

      // Heuristic: if w/h look normalized (~<=1), scale them to pixels.
      final bool bboxIsNormalized = (w <= 1.0 && h <= 1.0 && cx.abs() <= 1.0 && cy.abs() <= 1.0);
      final double cxU = bboxIsNormalized ? (cx * inputSize) : cx;
      final double cyU = bboxIsNormalized ? (cy * inputSize) : cy;
      final double wU  = bboxIsNormalized ? (w * inputSize) : w;
      final double hU  = bboxIsNormalized ? (h * inputSize) : h;

      // Exported heads can output slightly negative sizes; use abs to make
      // geometric computations stable.
      final double wAbs = wU.abs();
      final double hAbs = hU.abs();

      final double areaPx = wAbs * hAbs;
      if (areaPx < minBoxAreaPx || areaPx > maxBoxAreaPx) continue;
      if (wAbs < minSidePx || wAbs > maxSidePx) continue;
      if (hAbs < minSidePx || hAbs > maxSidePx) continue;

      double maxScore = 0;
      int    maxClass = 0;
      for (int c = 0; c < numClasses; c++) {
        final score = rawDet[idx(4 + c, i)];
        if (score > maxScore) {
          maxScore = score;
          maxClass = c;
        }
      }

      if (maxScore >= confThreshold) {
        candidates.add(_Candidate(
          cx: cxU, cy: cyU, w: wAbs, h: hAbs,
          confidence: maxScore,
          classIndex: maxClass,
          areaPx: areaPx,
          anchorIndex: i,
        ));
      }
    }

    if (candidates.isEmpty) return const [];

    final kept = _nms(candidates);
    if (kept.isEmpty) return const [];

    // Mask gating + box generation for every candidate.
    final results = <DetectionResult>[];
    int maskFailCount = 0;
    int confPassCount = 0;
    for (final c in kept) {
      if (c.confidence < calamansiPresenceThreshold) continue;

      confPassCount++;
      final bool maskOk = _maskLooksCalamansi(
        best: c,
        rawDet: rawDet,
        rawProto: rawProto,
        detShape: detShape,
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

      results.add(
        DetectionResult(
          saplingClass: _toEnum(c.classIndex),
          confidence: c.confidence,
          boxAreaPx: c.areaPx,
          isCalamansi: true,
          bboxLeft: x1,
          bboxTop: y1,
          bboxRight: x2,
          bboxBottom: y2,
        ),
      );
    }

    if (kDebugMode) {
      // Helpful when you see fewer boxes than expected in an image.
      debugPrint(
        'Decode counts: candidates=${candidates.length}, kept=${kept.length}, '
        'confPass=$confPassCount, confFail=${kept.length - confPassCount}, '
        'maskFail=$maskFailCount, results=${results.length}',
      );
    }

    if (results.isEmpty) return const [];

    // Sort by confidence descending and optionally cap output count.
    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    const int maxDetectionsToReturn = 10;
    return results.length > maxDetectionsToReturn
        ? results.sublist(0, maxDetectionsToReturn)
        : results;
  }

  /// Input: one candidate + raw detection/prototype tensors.
  /// Output: true if candidate mask statistics look like a valid calamansi instance.
  bool _maskLooksCalamansi({
    required _Candidate best,
    required List<double> rawDet,
    required List<double> rawProto,
    required List<int> detShape,
    required List<int> protoShape,
  }) {
    // Expected proto shape: [1,32,160,160]
    if (protoShape.length != 4 || protoShape[1] != 32) return false;
    final int H = protoShape[2];
    final int W = protoShape[3];
    const int numClasses  = 4;
    const int numMaskCoef = 32;
    const int rows        = 4 + numClasses + numMaskCoef; // 40

    final bool rowFirst = detShape[1] == rows;
    if (!rowFirst && detShape[2] != rows) return false;
    final int numAnchors = rowFirst ? detShape[2] : detShape[1];

    int idxDet(int row, int anchor) => rowFirst
        ? row * numAnchors + anchor
        : anchor * rows + row;

    final List<double> coeffs = List<double>.filled(
      numMaskCoef,
      0.0,
    );
    for (int k = 0; k < numMaskCoef; k++) {
      coeffs[k] = rawDet[idxDet(4 + numClasses + k, best.anchorIndex)];
    }

    // bbox -> proto coords
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
    int countAbove = 0;
    double sumSig = 0.0;

    // proto is [1,32,160,160] flattened: proto[k,y,x] = rawProto[k*H*W + y*W + x]
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
    final double maskMean = sumSig / total;

    if (kDebugMode) {
      debugPrint(
        'Mask gate: ratio=${maskAreaRatio.toStringAsFixed(3)}, mean=${maskMean.toStringAsFixed(3)}',
      );
    }

    return maskAreaRatio >= minMaskAreaRatioWithinBbox &&
        maskMean >= minMaskMeanWithinBbox;
  }

  /// Input: candidate detection list.
  /// Output: candidate list after IoU-based duplicate suppression.
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

  /// Input: two candidate boxes.
  /// Output: IoU score used by NMS.
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

  /// Input: numeric class index from model output.
  /// Output: corresponding app enum class.
  SaplingClass _toEnum(int idx) {
    switch (idx) {
      case 0:  return SaplingClass.healthy;
      case 1:  return SaplingClass.pestDamaged;
      case 2:  return SaplingClass.wilting;
      case 3:  return SaplingClass.yellowing;
      default: return SaplingClass.healthy;
    }
  }

  // (intentionally no multi-object fallback here; empty list means no detections)
}

class _Candidate {
  final double cx, cy, w, h, confidence, areaPx;
  final int classIndex;
  final int anchorIndex;
  _Candidate({
    required this.cx, required this.cy,
    required this.w,  required this.h,
    required this.confidence,
    required this.classIndex,
    required this.areaPx,
    required this.anchorIndex,
  });
}

final inferenceService = InferenceService();

// Runs in a background isolate to avoid UI jank.
/// Input: map with `imagePath` and `inputSize`.
/// Output: CHW float list (normalized) for ONNX input tensor.
List<double> _preprocessImageIsolate(Map<String, dynamic> args) {
  final String imagePath = args['imagePath'] as String;
  final int inputSize = args['inputSize'] as int;

  final bytes = File(imagePath).readAsBytesSync();
  final source = img.decodeImage(bytes);
  if (source == null) {
    throw Exception('Cannot decode image');
  }

  final double scale = min(inputSize / source.width, inputSize / source.height);
  final int nw = (source.width * scale).round();
  final int nh = (source.height * scale).round();
  final img.Image resized = img.copyResize(source, width: nw, height: nh);
  final img.Image canvas = img.Image(width: inputSize, height: inputSize);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(
    canvas,
    resized,
    dstX: (inputSize - nw) ~/ 2,
    dstY: (inputSize - nh) ~/ 2,
  );

  final data = List<double>.filled(3 * inputSize * inputSize, 0.0);
  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final pixel = canvas.getPixel(x, y);
      final int offset = y * inputSize + x;
      data[offset] = pixel.r / 255.0;
      data[inputSize * inputSize + offset] = pixel.g / 255.0;
      data[2 * inputSize * inputSize + offset] = pixel.b / 255.0;
    }
  }

  return data;
}