// ========================= lib/detection/inference_service.dart =========================
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'live_preprocess_worker.dart';

enum SaplingClass { healthy, pestDamaged, wilting, yellowing }

/// Lightweight result for a single live camera preview frame — used only
/// for the on-screen live overlay in ScannerScreen. No blur-check and no
/// display-JPEG re-encode (unlike [ImageAnalysisResult]), since neither is
/// needed just to draw a box/outline on the live preview; the full
/// [InferenceService.analyzeImage] pipeline still runs, unchanged, on the
/// actual captured photo.
class LiveFrameResult {
  final List<DetectionResult> detections;

  /// Pixel size of the upright RGB frame these detections' bbox/mask
  /// coordinates were computed against (post sensor-rotation correction).
  final int frameWidth;
  final int frameHeight;

  /// Letterbox params used during preprocess (must match overlay un-letterbox).
  final double letterboxScale;
  final double padX;
  final double padY;

  // ── Dev-only performance metrics (all in milliseconds) ──────────────────
  // Populated by [InferenceService.analyzeCameraFrame] so the live scanner
  // can show/benchmark real on-device timings without any extra plumbing.
  // Cost of the Stopwatch calls themselves is negligible, but callers that
  // don't care can simply ignore these fields.
  final double preprocessMs;
  final double inferenceMs;
  final double postprocessMs;
  final double totalMs;

  /// Dev-only: frame format/size/rotation used, and best raw class score
  /// seen in the model output (0 in release builds).
  final String diag;
  final double maxScore;

  const LiveFrameResult({
    required this.detections,
    required this.frameWidth,
    required this.frameHeight,
    required this.letterboxScale,
    required this.padX,
    required this.padY,
    this.preprocessMs  = 0,
    this.inferenceMs   = 0,
    this.postprocessMs = 0,
    this.totalMs       = 0,
    this.diag          = '',
    this.maxScore      = 0,
  });
}

/// Full analysis payload: detections + letterbox metadata for accurate overlays.
class ImageAnalysisResult {
  final List<DetectionResult> detections;

  /// EXIF-baked source size used by the model (matches [displayBytes]).
  final int imageWidth;
  final int imageHeight;

  /// Letterbox params used during preprocess (must match overlay un-letterbox).
  final double letterboxScale;
  final double padX;
  final double padY;

  /// JPEG of the EXIF-corrected image so UI boxes/masks align with pixels.
  final Uint8List displayBytes;

  /// Pixel size of [displayBytes] (may be downscaled vs [imageWidth]/[imageHeight]).
  final int displayWidth;
  final int displayHeight;

  const ImageAnalysisResult({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.letterboxScale,
    required this.padX,
    required this.padY,
    required this.displayBytes,
    required this.displayWidth,
    required this.displayHeight,
  });
}

class DetectionResult {
  final SaplingClass? saplingClass;
  final double        confidence;
  final double        boxAreaPx;
  final bool          isCalamansi;

  // Secondary condition when two classes score above threshold.
  final SaplingClass? secondaryClass;
  final double?       secondaryConfidence;

  /// Bounding box in model input space (letterboxed 640×640), in pixels.
  final double? bboxLeft;
  final double? bboxTop;
  final double? bboxRight;
  final double? bboxBottom;

  /// Leaf outline polygon in letterbox space: each point is [x, y].
  final List<List<double>>? maskPolygon;

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
    this.maskPolygon,
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
  static const double confThreshold              = 0.70;
  /// Final keep gate on class score. Not a true species check 
  static const double calamansiPresenceThreshold = 0.80;

  // Minimum confidence for a secondary class to be reported.
  static const double secondaryClassThreshold    = 0.60;

   /// Same-class IoU suppress threshold (lower = keep more nearby leaves).
  static const double iouThreshold = 0.15;
  /// Cross-class suppress only when boxes almost completely overlap.
  static const double crossClassIouThreshold = 0.40;

  // ── Box geometry filters ──────────────────────────────────────────────────
  static const double minBoxAreaPx   = 300;
  /// Cap oversized boxes that often swallow multiple adjacent leaves.
  static const double maxBoxAreaPx   = 55000;
  static const double minSidePx      = 10;
  static const double maxSidePx      = 1024;
  static const double maxAspectRatio = 3.0;

  // ── Mask gating thresholds ────────────────────────────────────────────────
  static const double minMaskAreaRatioWithinBbox = 0.12;
  static const double minMaskMeanWithinBbox      = 0.25;
  static const double maskBinaryThreshold        = 0.5;

  // ── Blur detection ────────────────────────────────────────────────
  static const double blurThreshold = 80.0;

  /// Full model (boxes + 32x160x160 mask prototypes). Used by capture/gallery.
  OrtSession? _session;

  /// Detection-only model (output0 only; Proto branch removed). Used by the
  /// live overlay, which never reads masks. Falls back to [_session] if the
  /// asset is missing, so the app still works without it.
  OrtSession? _liveSession;

  /// ORT tuning knobs — benchmark 2 / 4 / 6 on the real phone and keep the best.
  static const int  _ortThreads = 4;
  /// Dev-only: best raw class score of the last decoded live frame.
  static double _debugMaxScore = 0;
  static const String _ep = 'cpu'; // 'cpu' | 'xnnpack' | 'nnapi'

  bool _isLoaded = false;
  final LivePreprocessWorker _liveWorker = LivePreprocessWorker();

  bool get isLoaded => _isLoaded;

  Future<void> startLivePreprocessWorker() => _liveWorker.start();

  Future<void> stopLivePreprocessWorker() => _liveWorker.stop();

  // ── loadModel ─────────────────────────────────────────────────────────────

  Future<void> loadModel() async {
    if (_isLoaded) return;
    try {
      final ort = OnnxRuntime();
      try {
        debugPrint('ORT available providers: '
            '${await ort.getAvailableProviders()}');
      } catch (_) {}
      _session = await _createSession(ort, 'assets/models/best_flutter.onnx');
      try {
        _liveSession = await _createSession(
          ort,
          'assets/models/best_flutter_live_det.onnx',
        );
      } catch (e) {
        debugPrint('Live det-only model unavailable ($e); using full model.');
        _liveSession = null;
      }
      _isLoaded = true;
      debugPrint('✅ ONNX segmentation model loaded');
    } catch (e) {
      debugPrint('❌ Model load failed: $e');
      rethrow;
    }
  }

  /// Creates a session with explicit thread count and (optionally) XNNPACK,
  /// falling back to the plugin's default CPU session if that fails.
  Future<OrtSession> _createSession(OnnxRuntime ort, String asset) async {
    try {
      return await ort.createSessionFromAsset(
        asset,
        options: OrtSessionOptions(
          intraOpNumThreads: _ortThreads,
          providers: _ep == 'nnapi'
              ? [OrtProvider.NNAPI, OrtProvider.CPU]
              : _ep == 'xnnpack'
                  ? [OrtProvider.XNNPACK, OrtProvider.CPU]
                  : [OrtProvider.CPU],
        ),
      );
    } catch (e) {
      debugPrint('Session options failed for $asset ($e); using defaults.');
      return ort.createSessionFromAsset(asset);
    }
  }

  /// Avoids boxing ~820K floats into a List< double > of Dart objects.
  static List<double> _toDoubleList(List<dynamic> raw) {
    if (raw is Float32List) return raw;
    final out = Float32List(raw.length);
    for (var i = 0; i < raw.length; i++) {
      out[i] = (raw[i] as num).toDouble();
    }
    return out;
  }

  Future<void> dispose() async {
    await _liveWorker.stop();
    if (_liveSession != null && !identical(_liveSession, _session)) {
      await _liveSession?.close();
    }
    _liveSession = null;
    await _session?.close();
    _session = null;
    _isLoaded = false;
  }

  // ── analyzeCameraFrame (live preview overlay) ───────────────────────────

  /// Runs a fast detection pass on a single live camera preview frame.
  /// Intended to be called on a throttled interval (not every frame) by
  /// the scanner screen, purely to drive the live outline/number/
  /// classification overlay. Returns null if the model isn't loaded yet
  /// or the frame couldn't be decoded; never touches [analyzeImage]'s
  /// state or the actual photo-capture path.
  ///
  /// Pixel conversion runs on a long-lived worker isolate. Only
  /// `session.run()` (plugin requirement) and a cheap box/NMS scan run here.
  Future<LiveFrameResult?> analyzeCameraFrame(
    CameraImage image, {
    required int sensorOrientation,
  }) async {
    if (!_isLoaded || _session == null) return null;

    final swTotal = Stopwatch()..start();
    final swStage = Stopwatch()..start();

    final Map<String, dynamic>? pre = await _liveWorker.process(
      image: image,
      sensorOrientation: sensorOrientation,
      inputSize: inputSize,
    );
    if (pre == null) return null;
    final double preprocessMs = swStage.elapsedMicroseconds / 1000.0;
    swStage
      ..reset()
      ..start();

    final inputData      = pre['inputData']      as Float32List;
    final frameWidth      = pre['frameWidth']      as int;
    final frameHeight     = pre['frameHeight']     as int;
    final letterboxScale  = pre['letterboxScale']  as double;
    final padXi           = pre['padX']            as double;
    final padYi           = pre['padY']            as double;

    // ── 2) ONNX inference — must run on the main isolate ──
    final inputTensor =
        await OrtValue.fromList(inputData, [1, 3, inputSize, inputSize]);
    final inputs  = <String, OrtValue>{'images': inputTensor};
    final outputs = await (_liveSession ?? _session)!.run(inputs);
 
    final detValue = outputs['output0'];
    // output1 (the 32×160×160 mask prototypes) is not read here — the live
    // overlay only shows a bounding box, so there's no need to pay for
    // fetching that ~820K-element array on every frame. It's still
    // disposed below like every other output to avoid a native leak.

    if (detValue == null) {
      await inputTensor.dispose();
      for (final out in outputs.values) {
        await out.dispose();
      }
      final double inferenceMs = swStage.elapsedMicroseconds / 1000.0;
      return LiveFrameResult(
        detections:     const [],
        frameWidth:     frameWidth,
        frameHeight:    frameHeight,
        letterboxScale: letterboxScale,
        padX:           padXi,
        padY:           padYi,
        preprocessMs:   preprocessMs,
        inferenceMs:    inferenceMs,
        postprocessMs:  0,
        totalMs:        swTotal.elapsedMicroseconds / 1000.0,
      );
    }

    final detShape = detValue.shape;
    // Android already returns Float32List through the plugin. Keep that
    // typed buffer and skip the 336k-element `.map().toList()` boxing.
    final rawDetRaw = await detValue.asFlattenedList();

    await inputTensor.dispose();
    for (final out in outputs.values) {
      await out.dispose();
    }
    final double inferenceMs = swStage.elapsedMicroseconds / 1000.0;
    swStage
      ..reset()
      ..start();

    final detections = _decodeBoxesOnly(rawDetRaw, detShape);
    final double postprocessMs = swStage.elapsedMicroseconds / 1000.0;
    final String diag = (pre['diag'] as String?) ?? '';

    return LiveFrameResult(
      detections:     detections,
      frameWidth:     frameWidth,
      frameHeight:    frameHeight,
      letterboxScale: letterboxScale,
      padX:           padXi,
      padY:           padYi,
      preprocessMs:   preprocessMs,
      inferenceMs:    inferenceMs,
      postprocessMs:  postprocessMs,
      totalMs:        swTotal.elapsedMicroseconds / 1000.0,
      diag:           diag,
      maxScore:       (kDebugMode || kProfileMode) ? _debugMaxScore : 0,
    );
  }

  /// Lightweight box-only counterpart to [_decodeOutput], used only by the
  /// live camera overlay. Same candidate extraction, geometry/aspect
  /// filters, and class-aware NMS as the full pipeline — it just skips
  /// mask evaluation entirely, so every returned [DetectionResult] has
  /// `maskPolygon: null` (the live overlay already falls back to drawing
  /// a plain box in that case). The actual captured photo still runs the
  /// full [_decodeOutput] pipeline, unchanged, with the real outline.
  static List<DetectionResult> _decodeBoxesOnly(
    List rawDet,
    List<int> detShape,
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

    double at(int row, int anchor) {
      final v = rawDet[idx(row, anchor)];
      return v is double ? v : (v as num).toDouble();
    }

    if (kDebugMode || kProfileMode) {
      double m = 0;
      for (int i = 0; i < numAnchors; i++) {
        for (int c = 0; c < numClasses; c++) {
          final s = at(4 + c, i);
          if (s > m) m = s;
        }
      }
      _debugMaxScore = m;
    }

    final candidates = <_Candidate>[];

    for (int i = 0; i < numAnchors; i++) {
      final double cx = at(0, i);
      final double cy = at(1, i);
      final double w  = at(2, i);
      final double h  = at(3, i);

      final bool bboxIsNormalized =
          (w <= 1.0 && h <= 1.0 && cx.abs() <= 1.0 && cy.abs() <= 1.0);
      final double cxU = bboxIsNormalized ? (cx * inputSize) : cx;
      final double cyU = bboxIsNormalized ? (cy * inputSize) : cy;
      final double wU  = bboxIsNormalized ? (w  * inputSize) : w;
      final double hU  = bboxIsNormalized ? (h  * inputSize) : h;

      final double wAbs = wU.abs();
      final double hAbs = hU.abs();

      final double areaPx = wAbs * hAbs;
      if (areaPx < minBoxAreaPx || areaPx > maxBoxAreaPx) continue;
      if (wAbs < minSidePx     || wAbs > maxSidePx)      continue;
      if (hAbs < minSidePx     || hAbs > maxSidePx)      continue;

      final double aspectRatio = max(wAbs, hAbs) / min(wAbs, hAbs);
      if (aspectRatio > maxAspectRatio) continue;

      double maxScore = 0; int maxClass = 0;
      for (int c = 0; c < numClasses; c++) {
        final score = at(4 + c, i);
        if (score > maxScore) {
          maxScore = score;
          maxClass = c;
        }
      }

      if (maxScore >= confThreshold) {
        candidates.add(_Candidate(
          cx: cxU, cy: cyU, w: wAbs, h: hAbs,
          confidence:     maxScore,
          classIndex:     maxClass,
          areaPx:         areaPx,
          anchorIndex:    i,
          secondaryScore: 0,
          secondaryClass: maxClass,
        ));
      }
    }

    if (candidates.isEmpty) return const [];

    final kept = _nms(candidates);
    if (kept.isEmpty) return const [];

    final results = <DetectionResult>[];
    for (final c in kept) {
      if (c.confidence < calamansiPresenceThreshold) continue;

      final double x1 = (c.cx - c.w / 2).clamp(0.0, inputSize - 1);
      final double y1 = (c.cy - c.h / 2).clamp(0.0, inputSize - 1);
      final double x2 = (c.cx + c.w / 2).clamp(0.0, inputSize - 1);
      final double y2 = (c.cy + c.h / 2).clamp(0.0, inputSize - 1);

      results.add(DetectionResult(
        saplingClass: _toEnum(c.classIndex),
        confidence:   c.confidence,
        boxAreaPx:    c.areaPx,
        isCalamansi:  true,
        bboxLeft:     x1,
        bboxTop:      y1,
        bboxRight:    x2,
        bboxBottom:   y2,
        maskPolygon:  null,
      ));
    }

    if (results.isEmpty) return const [];

    results.sort((a, b) => b.confidence.compareTo(a.confidence));
    const int maxDetectionsToReturn = 10;
    return results.length > maxDetectionsToReturn
        ? results.sublist(0, maxDetectionsToReturn)
        : results;
  }

  // ── analyzeImage ──────────────────────────────────────────────────────────

  Future<ImageAnalysisResult> analyzeImage(String imagePath) async {
    if (!_isLoaded || _session == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    // Preprocess with EXIF rotation and blur check in isolate.
    final result = await compute<Map<String, dynamic>, Map<String, dynamic>>(
      _preprocessAndCheckIsolate,
      {
        'imagePath':     imagePath,
        'inputSize':     inputSize,
        'blurThreshold': blurThreshold,
      },
    );

    final isBlurry     = result['isBlurry']     as bool;
    final blurVariance = result['blurVariance'] as double;

    if (isBlurry) {
      debugPrint('⚠️  Image too blurry (variance=$blurVariance). Skipping inference.');
      throw Exception(
        'Image is too blurry (sharpness score: ${blurVariance.toStringAsFixed(1)}). '
        'Please retake the photo with better focus.',
      );
    }

    final inputData = result['inputData'] as List<double>;
    final imageWidth = result['imageWidth'] as int;
    final imageHeight = result['imageHeight'] as int;
    final letterboxScale = result['letterboxScale'] as double;
    final padX = result['padX'] as double;
    final padY = result['padY'] as double;
    final displayBytes = result['displayBytes'] as Uint8List;

    final inputTensor = await OrtValue.fromList(
      inputData is Float32List ? inputData : Float32List.fromList(inputData),
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
      return ImageAnalysisResult(
        detections: const [],
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        letterboxScale: letterboxScale,
        padX: padX,
        padY: padY,
        displayBytes: displayBytes,
        displayWidth: result['displayWidth'] as int,
        displayHeight: result['displayHeight'] as int,
      );
    }

    final detShape   = detValue.shape;
    final protoShape = protoValue.shape;
    final rawDet   = _toDoubleList(await detValue.asFlattenedList());
    final rawProto = _toDoubleList(await protoValue.asFlattenedList());

    await inputTensor.dispose();
    for (final out in outputs.values) {
      await out.dispose();
    }

    final detections = _decodeOutput(rawDet, detShape, rawProto, protoShape);
    return ImageAnalysisResult(
      detections: detections,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      letterboxScale: letterboxScale,
      padX: padX,
      padY: padY,
      displayBytes: displayBytes,
      displayWidth: result['displayWidth'] as int,
      displayHeight: result['displayHeight'] as int,
    );
  }

  // ── _decodeOutput ─────────────────────────────────────────────────────────

  static List<DetectionResult> _decodeOutput(
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

      // Track best AND second-best class scores per anchor
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

      final maskEval = _evaluateMask(
        best:       c,
        rawDet:     rawDet,
        rawProto:   rawProto,
        detShape:   detShape,
        protoShape: protoShape,
      );
      if (maskEval == null || !maskEval.ok) {
        maskFailCount++;
        continue;
      }

      final double x1 = (c.cx - c.w / 2).clamp(0.0, inputSize - 1);
      final double y1 = (c.cy - c.h / 2).clamp(0.0, inputSize - 1);
      final double x2 = (c.cx + c.w / 2).clamp(0.0, inputSize - 1);
      final double y2 = (c.cy + c.h / 2).clamp(0.0, inputSize - 1);

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
        // Model has no species class — true only after score + mask gates.
        isCalamansi:         true,
        secondaryClass:      secondaryClass,
        secondaryConfidence: secondaryConfidence,
        bboxLeft:            x1,
        bboxTop:             y1,
        bboxRight:           x2,
        bboxBottom:          y2,
        maskPolygon:         maskEval.polygon,
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
    const int maxDetectionsToReturn = 20;
    return results.length > maxDetectionsToReturn
        ? results.sublist(0, maxDetectionsToReturn)
        : results;
  }

  // ── _evaluateMask ─────────────────────────────────────────────────────────

  static _MaskEval? _evaluateMask({
    required _Candidate   best,
    required List<double> rawDet,
    required List<double> rawProto,
    required List<int>    detShape,
    required List<int>    protoShape,
  }) {
    if (protoShape.length != 4 || protoShape[1] != 32) return null;
    final int H = protoShape[2];
    final int W = protoShape[3];
    const int numClasses  = 4;
    const int numMaskCoef = 32;
    const int rows        = 4 + numClasses + numMaskCoef;

    final bool rowFirst  = detShape[1] == rows;
    if (!rowFirst && detShape[2] != rows) return null;
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

    if (px2 <= px1 || py2 <= py1) return null;

    final int bw = px2 - px1 + 1;
    final int bh = py2 - py1 + 1;
    final int total = bw * bh;
    final sigs = List<double>.filled(total, 0.0);

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
        final int li = (y - py1) * bw + (x - px1);
        sigs[li] = sig;
        if (sig > maskBinaryThreshold) countAbove++;
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

    final bool ok = maskAreaRatio >= minMaskAreaRatioWithinBbox &&
        maskMean >= minMaskMeanWithinBbox;
    if (!ok) return const _MaskEval(ok: false, polygon: null);

    final polygon = _maskBoundaryPolygon(
      sigs: sigs,
      bw: bw,
      bh: bh,
      px1: px1,
      py1: py1,
      protoW: W,
      protoH: H,
    );

    return _MaskEval(ok: true, polygon: polygon);
  }

  /// Trace the outer silhouette of the proto mask (not a radial fan of edge pixels).
  static List<List<double>>? _maskBoundaryPolygon({
    required List<double> sigs,
    required int bw,
    required int bh,
    required int px1,
    required int py1,
    required int protoW,
    required int protoH,
  }) {
    const int scale = 3;
    final int uw = bw * scale;
    final int uh = bh * scale;
    final binary = List<bool>.filled(uw * uh, false);

    bool sampleOn(double fx, double fy) {
      final x0 = fx.floor().clamp(0, bw - 1);
      final y0 = fy.floor().clamp(0, bh - 1);
      final x1 = min(x0 + 1, bw - 1);
      final y1 = min(y0 + 1, bh - 1);
      final tx = fx - x0;
      final ty = fy - y0;
      final v00 = sigs[y0 * bw + x0];
      final v10 = sigs[y0 * bw + x1];
      final v01 = sigs[y1 * bw + x0];
      final v11 = sigs[y1 * bw + x1];
      final v = v00 * (1 - tx) * (1 - ty) +
          v10 * tx * (1 - ty) +
          v01 * (1 - tx) * ty +
          v11 * tx * ty;
      return v > maskBinaryThreshold;
    }

    for (int y = 0; y < uh; y++) {
      for (int x = 0; x < uw; x++) {
        final fx = (x + 0.5) / scale - 0.5;
        final fy = (y + 0.5) / scale - 0.5;
        binary[y * uw + x] = sampleOn(fx, fy);
      }
    }

    final contour = _traceOuterContour(binary, uw, uh);
    if (contour == null || contour.length < 8) return null;

    final mapped = <List<double>>[];
    for (final p in contour) {
      final protoX = px1 + (p[0] + 0.5) / scale;
      final protoY = py1 + (p[1] + 0.5) / scale;
      mapped.add([
        protoX / protoW * inputSize,
        protoY / protoH * inputSize,
      ]);
    }

    return _rdpClosed(mapped, 1.8);
  }

  /// Moore-neighbor walk around the largest connected blob.
  static List<List<int>>? _traceOuterContour(List<bool> binary, int w, int h) {
    bool at(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return false;
      return binary[y * w + x];
    }

    int sx = -1, sy = -1;
    findStart:
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (at(x, y)) {
          sx = x;
          sy = y;
          break findStart;
        }
      }
    }
    if (sx < 0) return null;

    // Clockwise 8-neighborhood: E, SE, S, SW, W, NW, N, NE
    const dx = [1, 1, 0, -1, -1, -1, 0, 1];
    const dy = [0, 1, 1, 1, 0, -1, -1, -1];

    final contour = <List<int>>[];
    int px = sx, py = sy;
    int bx = sx - 1, by = sy;
    final int maxSteps = w * h * 2;

    for (int step = 0; step < maxSteps; step++) {
      contour.add([px, py]);

      int startK = 4;
      for (int k = 0; k < 8; k++) {
        if (px + dx[k] == bx && py + dy[k] == by) {
          startK = k;
          break;
        }
      }

      bool found = false;
      int nx = px, ny = py, nbx = bx, nby = by;
      for (int i = 1; i <= 8; i++) {
        final k = (startK + i) % 8;
        final cx = px + dx[k];
        final cy = py + dy[k];
        if (at(cx, cy)) {
          final pk = (k + 7) % 8;
          nbx = px + dx[pk];
          nby = py + dy[pk];
          nx = cx;
          ny = cy;
          found = true;
          break;
        }
      }
      if (!found) break;

      bx = nbx;
      by = nby;
      px = nx;
      py = ny;
      if (px == sx && py == sy && step > 2) break;
    }

    return contour.length >= 8 ? contour : null;
  }

  /// Closed-polygon RDP: split at the farthest vertex from the start, then simplify each arc.
  static List<List<double>> _rdpClosed(List<List<double>> pts, double epsilon) {
    if (pts.length < 6) return pts;
    var maxD = 0.0;
    var idx = 1;
    for (int i = 1; i < pts.length; i++) {
      final dx = pts[i][0] - pts[0][0];
      final dy = pts[i][1] - pts[0][1];
      final d = sqrt(dx * dx + dy * dy);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (idx <= 1 || idx >= pts.length - 1) return _rdp(pts, epsilon);
    final left = _rdp(pts.sublist(0, idx + 1), epsilon);
    final right = _rdp([...pts.sublist(idx), pts.first], epsilon);
    return [...left.sublist(0, left.length - 1), ...right.sublist(0, right.length - 1)];
  }

  ///  keep leaf silhouette, drop proto-grid jaggies.
  static List<List<double>> _rdp(List<List<double>> pts, double epsilon) {
    if (pts.length < 3) return pts;

    double dist(List<double> p, List<double> a, List<double> b) {
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final len2 = dx * dx + dy * dy;
      if (len2 <= 1e-9) {
        final ex = p[0] - a[0];
        final ey = p[1] - a[1];
        return sqrt(ex * ex + ey * ey);
      }
      var t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final qx = a[0] + t * dx;
      final qy = a[1] + t * dy;
      final ex = p[0] - qx;
      final ey = p[1] - qy;
      return sqrt(ex * ex + ey * ey);
    }

    var maxD = 0.0;
    var idx = 0;
    final end = pts.length - 1;
    for (int i = 1; i < end; i++) {
      final d = dist(pts[i], pts.first, pts[end]);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }

    if (maxD > epsilon) {
      final left = _rdp(pts.sublist(0, idx + 1), epsilon);
      final right = _rdp(pts.sublist(idx), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [pts.first, pts.last];
  }

  // ── _nms (class-aware) ────────────────────────────────────────────────────

  static List<_Candidate> _nms(List<_Candidate> list) {
    list.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <_Candidate>[];
    for (final c in list) {
      bool suppressed = false;
      for (final k in kept) {
        final iou = _iou(c, k);
        if (c.classIndex == k.classIndex) {
          if (iou > iouThreshold) {
            suppressed = true;
            break;
          }
        } else if (iou > crossClassIouThreshold) {
          // Only collapse near-identical boxes of different classes.
          suppressed = true;
          break;
        }
      }
      if (!suppressed) kept.add(c);
    }
    return kept;
  }

  // ── _iou ──────────────────────────────────────────────────────────────────

  static double _iou(_Candidate a, _Candidate b) {
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

  static SaplingClass _toEnum(int idx) {
    switch (idx) {
      case 0:  return SaplingClass.healthy;
      case 1:  return SaplingClass.pestDamaged;
      case 2:  return SaplingClass.wilting;
      case 3:  return SaplingClass.yellowing;
      default: return SaplingClass.healthy;
    }
  }
}

// ── _Candidate / _MaskEval ────────────────────────────────────────────────────

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

class _MaskEval {
  final bool ok;
  final List<List<double>>? polygon;
  const _MaskEval({required this.ok, required this.polygon});
}

// ── Singleton ─────────────────────────────────────────────────────────────────

final inferenceService = InferenceService();

// ── Isolate: (EXIF rotation) +  (blur detection) ──────────────────

/// Runs in a background isolate to avoid UI jank.
/// Runs in a background isolate (called via `compute` from
/// [InferenceService.analyzeCameraFrame]): converts a raw camera preview
/// frame (YUV420 or BGRA8888 plane bytes) to RGB, rotates it upright using
/// the camera's sensor orientation, letterboxes it to the model's input
/// size, and normalizes it. This is the genuinely CPU-heavy, synchronous
/// per-frame work — moved off the UI thread so the live camera preview
/// never stutters. Returns null if the frame's format isn't supported or
/// conversion fails, so the caller just skips that frame.
/// Applies bakeOrientation so portrait photos arrive upright.
/// Computes Laplacian variance; rejects images below blurThreshold.
/// Returns map with keys: inputData, isBlurry, blurVariance, letterbox meta,
/// and displayBytes (EXIF-baked JPEG for overlay alignment).
Map<String, dynamic> _preprocessAndCheckIsolate(Map<String, dynamic> args) {
  final String imagePath  = args['imagePath']     as String;
  final int    inputSize  = args['inputSize']     as int;
  final double blurThresh = args['blurThreshold'] as double;

  final bytes = File(imagePath).readAsBytesSync();
  final raw   = img.decodeImage(bytes);
  if (raw == null) throw Exception('Cannot decode image');

  /// EXIF rotation so the model always sees an upright image.
  final source = img.bakeOrientation(raw);

  /// Blur detection via Laplacian variance on a small greyscale copy.
  final grey     = img.grayscale(img.copyResize(source, width: 256));
  final variance = _laplacianVariance(grey);
  final isBlurry = variance < blurThresh;

  // Letterbox resize to inputSize × inputSize
  final double scale = min(inputSize / source.width, inputSize / source.height);
  final int nw = (source.width  * scale).round();
  final int nh = (source.height * scale).round();
  final int padX = (inputSize - nw) ~/ 2;
  final int padY = (inputSize - nh) ~/ 2;

  final img.Image resized = img.copyResize(source, width: nw, height: nh);
  final img.Image canvas  = img.Image(width: inputSize, height: inputSize);
  img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
  img.compositeImage(
    canvas, resized,
    dstX: padX,
    dstY: padY,
  );

  // CHW normalised float tensor
  final data = Float32List(3 * inputSize * inputSize);
  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final pixel      = canvas.getPixel(x, y);
      final int offset = y * inputSize + x;
      data[offset]                             = pixel.r / 255.0;
      data[inputSize * inputSize + offset]     = pixel.g / 255.0;
      data[2 * inputSize * inputSize + offset] = pixel.b / 255.0;
    }
  }

  // Downscale display JPEG if huge to keep memory low; keep aspect.
  img.Image displaySrc = source;
  const int maxDisplaySide = 1280;
  if (source.width > maxDisplaySide || source.height > maxDisplaySide) {
    final ds = min(maxDisplaySide / source.width, maxDisplaySide / source.height);
    displaySrc = img.copyResize(
      source,
      width: (source.width * ds).round(),
      height: (source.height * ds).round(),
    );
  }
  final displayBytes = Uint8List.fromList(img.encodeJpg(displaySrc, quality: 90));

  return {
    'inputData':       data,
    'isBlurry':        isBlurry,
    'blurVariance':    variance,
    'imageWidth':      source.width,
    'imageHeight':     source.height,
    'letterboxScale':  scale,
    'padX':            padX.toDouble(),
    'padY':            padY.toDouble(),
    'displayBytes':    displayBytes,
    'displayWidth':    displaySrc.width,
    'displayHeight':   displaySrc.height,
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