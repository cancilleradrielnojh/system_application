// ========================= lib/scanner.dart =========================
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
  ) onScanComplete;

  const ScannerScreen({super.key, required this.onScanComplete});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  CameraController? controller;
  bool isCameraReady = false;
  bool isProcessing  = false;

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    if (kIsWeb) {
      setState(() => isCameraReady = false);
      return;
    }
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller!.initialize();
      if (!mounted) return;
      setState(() => isCameraReady = true);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
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
      return;
    }

    // Save all detections for this image (multiple calamansi per photo).
    if (payload.detections.isNotEmpty) {
      widget.onScanComplete(imagePath, payload.detections);
    }

    if (payload.action == ResultAction.done) {
      // Done → close scanner, return to home
      Navigator.pop(context);
    } else {
      // Scan New → stay in scanner, reset processing flag
      setState(() => isProcessing = false);
    }
  }

  Future<void> captureImage() async {
    if (!isCameraReady || isProcessing) return;
    setState(() => isProcessing = true);
    try {
      final image = await controller!.takePicture();
      if (!mounted) return;
      await _openResultScreen(image.path);
    } catch (e) {
      debugPrint('Capture error: $e');
      setState(() => isProcessing = false);
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
              child: CameraPreview(cam),
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
        if (mounted) setState(() => isProcessing = false);
        return;
      }
      await _openResultScreen(picked.path);
    } catch (e) {
      debugPrint('Gallery error: $e');
      if (mounted) setState(() => isProcessing = false);
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