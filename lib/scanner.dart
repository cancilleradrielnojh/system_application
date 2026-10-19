// ========================= lib/scanner.dart =========================
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'result_screen.dart';
import 'detection/inference_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_widgets.dart';

class ScannerScreen extends StatefulWidget {
  final Function(
    String imagePath,
    List<DetectionResult> detections,
    ImageAnalysisResult? analysis,
  ) onScanComplete;

  const ScannerScreen({super.key, required this.onScanComplete});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  CameraController? controller;
  bool isCameraReady = false;
  bool isProcessing  = false;
  bool _initializingCamera = false;
  Future<void>? _releasing;
  String? _cameraErrorMessage;

  final ImagePicker picker = ImagePicker();

  // ── Live detection (preview overlay only; capture flow is untouched) ────
  //
  // Frame scheduling contract:
  //   • At most one `analyzeCameraFrame` call is ever in flight (`_liveBusy`
  //     gates dispatch). No queue is kept — every frame that arrives while
  //     busy, or before `_liveInterval` has elapsed, is simply dropped and
  //     the *next* fresh frame is used instead, so the scanner always works
  //     on the newest useful frame rather than a backlog.
  //   • `_liveInterval` targets about one result per second. After each
  //     completed inference it is recalculated from measured latency and
  //     clamped to [_minLiveInterval]–[_maxLiveInterval] so a slow device
  //     still tries for ~1 Hz without flooding a fast one.
  //   • `_frameSeq`/`isProcessing` guard against a result for an old frame
  //     landing after a newer dispatch or after the capture button was
  //     pressed (so live boxes can never flash back over a captured photo).
  final ValueNotifier<LiveFrameResult?> _liveResultNotifier =
      ValueNotifier<LiveFrameResult?>(null);

  bool _liveBusy = false;
  int _frameSeq = 0;
  DateTime? _lastLiveDispatch;

  Duration _liveInterval = const Duration(milliseconds: 1000);
  static const Duration _minLiveInterval = Duration(milliseconds: 800);
  static const Duration _maxLiveInterval = Duration(milliseconds: 1000);

  // Brief hold so a single missed detection doesn't make boxes flicker off.
  DateTime? _lastNonEmptyAt;
  static const Duration _detectionHoldDuration = Duration(milliseconds: 200);
  DateTime? _lastAppliedDispatch;

  // ── Dev-only performance instrumentation (no-op in release builds) ─────
  final ValueNotifier<_LiveMetrics> _metricsNotifier =
      ValueNotifier<_LiveMetrics>(const _LiveMetrics());
  Timer? _metricsTimer;
  int _cameraFrameCounter = 0;
  int _droppedFrameCounter = 0;
  int _inferenceCompletionCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initCamera();
    if (kDebugMode || kProfileMode) _startMetricsTimer();
  }

  Future<void> initCamera() async {
    if (kIsWeb) {
      setState(() => isCameraReady = false);
      return;
    }
    if (_initializingCamera) return;
    _initializingCamera = true;
    try {
      // If the camera is still being released (app just went to background
      // / gallery opened), wait for that to finish before re-opening it.
      if (_releasing != null) await _releasing;
      if (!mounted) return;
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final cam = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        // Only affects startImageStream (used for the live overlay below);
        // takePicture() always uses its own JPEG capture path regardless
        // of this setting, so the actual capture flow is unaffected.
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      controller = cam;
      setState(() {
        isCameraReady = true;
        _cameraErrorMessage = null;
      });
      if (!isProcessing) {
        await inferenceService.startLivePreprocessWorker();
        await _startLiveStream();
      }
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        setState(() {
          isCameraReady = false;
          _cameraErrorMessage = _describeCameraError(e);
        });
      }
    } finally {
      _initializingCamera = false;
    }
  }

  String _describeCameraError(Object e) {
    if (e is CameraException) {
      switch (e.code) {
        case 'CameraAccessDenied':
        case 'CameraAccessDeniedWithoutPrompt':
        case 'CameraAccessRestricted':
          return 'Camera permission is required to scan live.';
        default:
          return 'Camera error: ${e.description ?? e.code}';
      }
    }
    return 'Camera unavailable.';
  }

  Future<void> _startLiveStream() async {
    if (controller == null || !controller!.value.isInitialized) {
      // Controller was torn down (e.g. app was backgrounded) — rebuild it
      // instead of trying to stream on a stale/null controller.
      await initCamera();
      return;
    }
    if (controller!.value.isStreamingImages) return;
    try {
      await controller!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('Live detection stream failed to start: $e');
    }
  }

  Future<void> _stopLiveStream() async {
    final cam = controller;
    if (cam != null && cam.value.isInitialized && cam.value.isStreamingImages) {
      try {
        await cam.stopImageStream();
      } catch (e) {
        debugPrint('Live detection stream failed to stop: $e');
      }
    }
  }

  /// Dispatched on (roughly) every incoming preview frame. Throttled and
  /// single-flight so the model only actually runs a few times per second
  /// on a background isolate/thread — the camera preview itself keeps
  /// streaming at full FPS regardless. Purely drives the live overlay;
  /// never touches the capture/save flow.
  void _onCameraFrame(CameraImage image) {
    _cameraFrameCounter++;

    if (!mounted || isProcessing) return;

    if (_liveBusy) {
      // Inference still busy with a previous frame — drop this one rather
      // than queuing it. The next frame that arrives once we're free will
      // be used instead, so we always work on the freshest frame.
      _droppedFrameCounter++;
      return;
    }

    final now = DateTime.now();
    if (_lastLiveDispatch != null &&
        now.difference(_lastLiveDispatch!) < _liveInterval) {
      _droppedFrameCounter++;
      return;
    }

    _lastLiveDispatch = now;
    _liveBusy = true;
    final int seq = ++_frameSeq;
    final int sensorOrientation = controller?.description.sensorOrientation ?? 0;

    _runLiveInference(image, seq, sensorOrientation, now);
  }

  Future<void> _runLiveInference(
    CameraImage image,
    int seq,
    int sensorOrientation,
    DateTime dispatchedAt,
  ) async {
    try {
      final result = await inferenceService.analyzeCameraFrame(
        image,
        sensorOrientation: sensorOrientation,
      );

      // Discard if superseded, if the widget is gone, or if the capture
      // button was pressed while this frame was still processing — this
      // is what stops a stale live box from ever flashing over a photo
      // that's already being analyzed.
      if (!mounted || isProcessing || seq != _frameSeq) return;
      if (_lastAppliedDispatch != null &&
          dispatchedAt.isBefore(_lastAppliedDispatch!)) {
        return;
      }

      if (result != null) {
        debugPrint('LIVE pre=${result.preprocessMs.toStringAsFixed(0)} '
            'inf=${result.inferenceMs.toStringAsFixed(0)} '
            'post=${result.postprocessMs.toStringAsFixed(0)} '
            'total=${result.totalMs.toStringAsFixed(0)} ms');
        _inferenceCompletionCounter++;
        _lastAppliedDispatch = dispatchedAt;

        final double measuredMs = result.totalMs > 0
            ? result.totalMs
            : DateTime.now().difference(dispatchedAt).inMilliseconds.toDouble();
        final double targetMs = (measuredMs * 1.15).clamp(
          _minLiveInterval.inMilliseconds.toDouble(),
          _maxLiveInterval.inMilliseconds.toDouble(),
        );
        _liveInterval = Duration(milliseconds: targetMs.round());

        _updateLiveResult(result);
      }
    } catch (e) {
      // One bad frame must never crash or freeze the scanner — just skip it.
      debugPrint('Live detection error: $e');
    } finally {
      _liveBusy = false;
    }
  }

  /// Lightweight temporal smoothing: a single frame with no detections
  /// (e.g. a brief hand shake) doesn't immediately clear the overlay —
  /// we hold the last detection for [_detectionHoldDuration] before
  /// dropping to the empty state, which removes most flicker without any
  /// heavier tracking logic.
  void _updateLiveResult(LiveFrameResult result) {
    if (result.detections.isNotEmpty) {
      _lastNonEmptyAt = DateTime.now();
      _liveResultNotifier.value = result;
      return;
    }
    if (_lastNonEmptyAt != null &&
        DateTime.now().difference(_lastNonEmptyAt!) < _detectionHoldDuration) {
      return; // keep showing the still-recent previous result
    }
    _liveResultNotifier.value = result; // genuinely empty — clear overlay
  }

  void _startMetricsTimer() {
    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final last = _liveResultNotifier.value;
      _metricsNotifier.value = _LiveMetrics(
        cameraFps: _cameraFrameCounter.toDouble(),
        aiFps: _inferenceCompletionCounter.toDouble(),
        droppedFramesPerSec: _droppedFrameCounter,
        preprocessMs: last?.preprocessMs ?? 0,
        inferenceMs: last?.inferenceMs ?? 0,
        postprocessMs: last?.postprocessMs ?? 0,
        totalMs: last?.totalMs ?? 0,
        intervalMs: _liveInterval.inMilliseconds,
        diag: last?.diag ?? '',
        maxScore: last?.maxScore ?? 0,
      );
      _cameraFrameCounter = 0;
      _inferenceCompletionCounter = 0;
      _droppedFrameCounter = 0;
    });
  }

  // ── App lifecycle: release the camera in background, rebuild on resume ──
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        final cam = controller;
        if (cam != null) _releasing = _releaseCamera();
        break;
      case AppLifecycleState.resumed:
        // NOTE: controller is null here after a release, so we must not
        // early-return on that — that was why the preview stayed dead after
        // coming back from the gallery picker.
        _ensureCameraActive();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Re-opens the camera (and live stream, when not busy with a capture or
  /// gallery pick) if it isn't currently running.
  Future<void> _ensureCameraActive() async {
    if (!mounted || kIsWeb) return;
    final cam = controller;
    if (cam == null || !cam.value.isInitialized) {
      await initCamera();
    } else if (!isProcessing) {
      await _startLiveStream();
    }
  }

  Future<void> _releaseCamera() async {
    final cam = controller;
    controller = null;
    _liveBusy = false;
    _lastAppliedDispatch = null;
    _liveResultNotifier.value = null;
    if (mounted) setState(() => isCameraReady = false);
    if (cam != null) {
      if (cam.value.isStreamingImages) {
        try {
          await cam.stopImageStream();
        } catch (_) {}
      }
      await cam.dispose();
    }
    await inferenceService.stopLivePreprocessWorker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _metricsTimer?.cancel();
    if (controller != null && controller!.value.isStreamingImages) {
      controller!.stopImageStream();
    }
    controller?.dispose();
    unawaited(inferenceService.stopLivePreprocessWorker());
    _liveResultNotifier.dispose();
    _metricsNotifier.dispose();
    super.dispose();
  }

  // ── Shared result handler ─────────────────────────────────────────────
  Future<void> _openResultScreen(String imagePath) async {
    final payload = await Navigator.push<ResultPayload?>(
      context,
      PageRouteBuilder<ResultPayload?>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ResultScreen(imagePath: imagePath),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(fade);
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );

    if (!mounted) return;

    if (payload == null) {
      // User tapped Try Again — stay in scanner
      setState(() => isProcessing = false);
      await _startLiveStream();
      return;
    }

    // Save all detections for this image (multiple calamansi per photo).
    if (payload.detections.isNotEmpty) {
      widget.onScanComplete(imagePath, payload.detections, payload.analysis);
    }

    if (payload.action == ResultAction.done) {
      // Done → close scanner, return to home
      Navigator.pop(context);
    } else {
      // Scan New → stay in scanner, reset processing flag
      setState(() => isProcessing = false);
      await _startLiveStream();
    }
  }

  Future<void> captureImage() async {
    if (!isCameraReady || isProcessing) return;
    setState(() {
      isProcessing = true;
    });
    // Pause live inference immediately so it can never conflict with the
    // photo-capture path; any in-flight live frame will see `isProcessing`
    // true when it completes and discard its result (see _runLiveInference).
    _liveResultNotifier.value = null;
    _lastNonEmptyAt = null;
    try {
      await _stopLiveStream();
      final image = await controller!.takePicture();
      if (!mounted) return;
      await _openResultScreen(image.path);
    } catch (e) {
      debugPrint('Capture error: $e');
      setState(() => isProcessing = false);
      await _startLiveStream();
    }
  }

  /// Fill the screen like a stock camera: crop if needed, never stretch.
  Widget _buildCameraPreview() {
    final cam = controller!;
    if (!cam.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final preview = cam.value.previewSize;
    if (preview == null) {
      return CameraPreview(cam);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // previewSize is landscape (sensor). Swap for portrait display.
        final previewW = preview.height;
        final previewH = preview.width;
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;
        final screenAspect = screenW / screenH;
        final previewAspect = previewW / previewH;

        double drawW = screenW;
        double drawH = screenH;
        if (screenAspect > previewAspect) {
          drawW = screenW;
          drawH = screenW / previewAspect;
        } else {
          drawH = screenH;
          drawW = screenH * previewAspect;
        }

        return ClipRect(
          child: OverflowBox(
            maxWidth: drawW,
            maxHeight: drawH,
            alignment: Alignment.center,
            child: SizedBox(
              width: drawW,
              height: drawH,
              // RepaintBoundary isolates the camera texture from repaints
              // triggered by the overlay above it.
              child: RepaintBoundary(child: CameraPreview(cam)),
            ),
          ),
        );
      },
    );
  }

  Future<void> uploadFromGallery() async {
    if (isProcessing) return;
    setState(() => isProcessing = true);
    try {
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) {
        // Cancelled — go back to the live camera.
        if (mounted) {
          setState(() => isProcessing = false);
          await _ensureCameraActive();
        }
        return;
      }
      await _openResultScreen(picked.path);
    } catch (e) {
      debugPrint('Gallery error: $e');
      if (mounted) {
        setState(() => isProcessing = false);
        await _ensureCameraActive();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'SCAN FRAME',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            fontSize: 14,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          if (!kIsWeb && isCameraReady)
            Positioned.fill(child: _buildCameraPreview()),

          if (kIsWeb || !isCameraReady)
            Positioned.fill(
              child: Container(
                color: AppColors.darkBg,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_camera_outlined,
                          color: AppColors.lime.withValues(alpha: 0.7),
                          size: 56),
                      const SizedBox(height: 14),
                      Text(
                        'Camera unavailable',
                        style: GoogleFonts.spaceGrotesk(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _cameraErrorMessage ??
                            'Upload a leaf photo from your gallery',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(
                          color: AppColors.darkMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                    ],
                    radius: 0.95,
                  ),
                ),
              ),
            ),
          ),

          if (!kIsWeb && isCameraReady)
            Center(
              child: SizedBox(
                width: 270,
                height: 270,
                child: Stack(
                  children: [
                    CustomPaint(
                      size: const Size(270, 270),
                      painter: ScanFramePainter(color: AppColors.lime),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(
                          'Align leaf inside brackets',
                          style: GoogleFonts.dmSans(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Live detection overlay ───────────────────────────────────────
          // Everything inside this subtree is driven by ValueListenableBuilders
          // fed from `_liveResultNotifier`/`_metricsNotifier`, so a new live
          // frame result only repaints this small overlay — never the
          // CameraPreview, buttons, or the rest of the screen.
          if (!kIsWeb && isCameraReady && !isProcessing)
            Positioned.fill(
              child: IgnorePointer(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final previewSize = controller!.value.previewSize;
                    if (previewSize == null) return const SizedBox.shrink();
                    final t = _computeCoverTransform(
                      previewSize,
                      Size(constraints.maxWidth, constraints.maxHeight),
                    );
                    return ValueListenableBuilder<LiveFrameResult?>(
                      valueListenable: _liveResultNotifier,
                      builder: (context, liveResult, _) {
                        final hasDetections = liveResult != null &&
                            liveResult.detections.isNotEmpty;
                        return Stack(
                          children: [
                            CustomPaint(
                              size: Size(constraints.maxWidth, constraints.maxHeight),
                              painter: _LiveDetectionPainter(
                                result: liveResult,
                                drawW: t.drawW,
                                drawH: t.drawH,
                                offsetX: t.offsetX,
                                offsetY: t.offsetY,
                              ),
                            ),
                            Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 100),
                                child: _LiveStatusPill(
                                  text: hasDetections
                                      ? '${liveResult.detections.length} sapling'
                                          '${liveResult.detections.length == 1 ? '' : 's'} detected'
                                      : 'No sapling detected',
                                  icon: hasDetections
                                      ? Icons.check_circle_outline_rounded
                                      : Icons.search_off_rounded,
                                  accent: hasDetections,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),

          // ── Dev-only performance overlay ────────────────────────────────
          if ((kDebugMode || kProfileMode) && !kIsWeb && isCameraReady && !isProcessing)
            Positioned(
              left: 12,
              bottom: 210,
              child: IgnorePointer(
                child: ValueListenableBuilder<_LiveMetrics>(
                  valueListenable: _metricsNotifier,
                  builder: (context, m, _) => _DevMetricsOverlay(metrics: m),
                ),
              ),
            ),

          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 36),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppColors.darkBg,
                    AppColors.darkBg.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!kIsWeb)
                    ElevatedButton.icon(
                      onPressed: isProcessing ? null : captureImage,
                      icon: Icon(
                        isProcessing
                            ? Icons.hourglass_top_rounded
                            : Icons.camera_alt_rounded,
                      ),
                      label: Text(isProcessing ? 'Processing…' : 'Capture'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.lime,
                        foregroundColor: AppColors.ink,
                        disabledBackgroundColor:
                            AppColors.lime.withValues(alpha: 0.4),
                      ),
                    ),
                  if (!kIsWeb) const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isProcessing ? null : uploadFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Upload from gallery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.55),
                        width: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Live detection overlay helpers ─────────────────────────────────────────

/// Mirrors the "fill screen, crop overflow" transform in
/// `_buildCameraPreview`, so live overlay boxes land exactly where the
/// cropped/scaled preview actually draws them on screen.
class _CoverTransform {
  final double drawW, drawH, offsetX, offsetY;
  const _CoverTransform({
    required this.drawW,
    required this.drawH,
    required this.offsetX,
    required this.offsetY,
  });
}

_CoverTransform _computeCoverTransform(Size previewSize, Size screenSize) {
  // previewSize is landscape (sensor). Swap for portrait display, exactly
  // like _buildCameraPreview does.
  final previewW = previewSize.height;
  final previewH = previewSize.width;
  final screenAspect = screenSize.width / screenSize.height;
  final previewAspect = previewW / previewH;

  double drawW = screenSize.width;
  double drawH = screenSize.height;
  if (screenAspect > previewAspect) {
    drawW = screenSize.width;
    drawH = screenSize.width / previewAspect;
  } else {
    drawH = screenSize.height;
    drawW = screenSize.height * previewAspect;
  }
  return _CoverTransform(
    drawW: drawW,
    drawH: drawH,
    offsetX: (screenSize.width  - drawW) / 2,
    offsetY: (screenSize.height - drawH) / 2,
  );
}

/// Draws the outline/box + "#number classification confidence%" label for
/// each sapling the live camera frame currently detects.
class _LiveDetectionPainter extends CustomPainter {
  final LiveFrameResult? result;
  final double drawW, drawH, offsetX, offsetY;

  _LiveDetectionPainter({
    required this.result,
    required this.drawW,
    required this.drawH,
    required this.offsetX,
    required this.offsetY,
  });

  double? _unletterX(double? lx, LiveFrameResult r) {
    if (lx == null) return null;
    return (lx - r.padX) / r.letterboxScale;
  }

  double? _unletterY(double? ly, LiveFrameResult r) {
    if (ly == null) return null;
    return (ly - r.padY) / r.letterboxScale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = result;
    if (r == null || r.detections.isEmpty) return;

    // Same left-to-right/top-to-bottom numbering convention used when a
    // scan is actually saved, so live numbers read consistently.
    final sorted = List<DetectionResult>.from(r.detections)
      ..sort((a, b) {
        final aTop  = a.bboxTop  ?? double.infinity;
        final bTop  = b.bboxTop  ?? double.infinity;
        final aLeft = a.bboxLeft ?? double.infinity;
        final bLeft = b.bboxLeft ?? double.infinity;
        final topDiff = aTop - bTop;
        if (topDiff.abs() > 50) return topDiff < 0 ? -1 : 1;
        return aLeft.compareTo(bLeft);
      });

    final boxStroke = Paint()
      ..color = AppColors.lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final outlineFill = Paint()
      ..color = AppColors.lime.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    double sx(double frameX) => offsetX + (frameX / r.frameWidth) * drawW;
    double sy(double frameY) => offsetY + (frameY / r.frameHeight) * drawH;

    for (var i = 0; i < sorted.length; i++) {
      final d = sorted[i];
      final left   = _unletterX(d.bboxLeft, r);
      final top    = _unletterY(d.bboxTop, r);
      final right  = _unletterX(d.bboxRight, r);
      final bottom = _unletterY(d.bboxBottom, r);
      if (left == null || top == null || right == null || bottom == null) {
        continue;
      }

      final rect = Rect.fromLTRB(sx(left), sy(top), sx(right), sy(bottom));

      final poly = d.maskPolygon;
      if (poly != null && poly.length >= 3) {
        final path = Path();
        for (var j = 0; j < poly.length; j++) {
          final px = sx(_unletterX(poly[j][0], r)!);
          final py = sy(_unletterY(poly[j][1], r)!);
          if (j == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        canvas.drawPath(path, outlineFill);
        canvas.drawPath(path, boxStroke);
      } else {
        canvas.drawRect(rect, boxStroke);
      }

      final label =
          '#${i + 1} ${d.className}  ${(d.confidence * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: AppColors.ink,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelY = rect.top - tp.height - 4;
      tp.paint(canvas, Offset(rect.left, labelY < 0 ? rect.bottom + 4 : labelY));
    }
  }

  @override
  bool shouldRepaint(covariant _LiveDetectionPainter oldDelegate) =>
      oldDelegate.result != result;
}

/// Small pill shown at the top of the live camera view: either
/// a "searching" hint or a count of what's currently in frame.
class _LiveStatusPill extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool accent;

  const _LiveStatusPill({
    required this.text,
    required this.icon,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: accent
            ? AppColors.lime.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accent ? AppColors.lime : Colors.white24,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent ? AppColors.ink : Colors.white70),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.dmSans(
              color: accent ? AppColors.ink : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dev-only snapshot of live-scanner performance, refreshed once a second.
class _LiveMetrics {
  final double cameraFps;
  final double aiFps;
  final int droppedFramesPerSec;
  final double preprocessMs;
  final double inferenceMs;
  final double postprocessMs;
  final double totalMs;
  final int intervalMs;
  final String diag;
  final double maxScore;

  const _LiveMetrics({
    this.cameraFps = 0,
    this.aiFps = 0,
    this.droppedFramesPerSec = 0,
    this.preprocessMs = 0,
    this.inferenceMs = 0,
    this.postprocessMs = 0,
    this.totalMs = 0,
    this.intervalMs = 0,
    this.diag = '',
    this.maxScore = 0,
  });
}

/// Small monospace HUD, debug builds only, for benchmarking the live
/// scanner on a real device (camera FPS, AI FPS, per-stage latency, and
/// dropped frames per second).
class _DevMetricsOverlay extends StatelessWidget {
  final _LiveMetrics metrics;
  const _DevMetricsOverlay({required this.metrics});

  @override
  Widget build(BuildContext context) {
    String ms(double v) => '${v.toStringAsFixed(0)}ms';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'cam ${metrics.cameraFps.toStringAsFixed(0)}fps  '
        'ai ${metrics.aiFps.toStringAsFixed(0)}fps  '
        'drop ${metrics.droppedFramesPerSec}/s\n'
        'pre ${ms(metrics.preprocessMs)}  '
        'inf ${ms(metrics.inferenceMs)}  '
        'post ${ms(metrics.postprocessMs)}\n'
        'total ${ms(metrics.totalMs)}  interval ${metrics.intervalMs}ms\n'
        'maxScore ${metrics.maxScore.toStringAsFixed(2)}  ${metrics.diag}',
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 10,
          fontFamily: 'monospace',
          height: 1.4,
        ),
      ),
    );
  }
}