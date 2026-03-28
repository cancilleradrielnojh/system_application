// ========================= lib/scanner.dart =========================
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'result_screen.dart';
import 'detection/inference_service.dart';

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
        ResolutionPreset.medium,
        enableAudio: false,
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Scan Sapling',
            style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          // Camera preview
          if (!kIsWeb && isCameraReady)
            Positioned.fill(child: CameraPreview(controller!)),

          // No-camera fallback
          if (kIsWeb || !isCameraReady)
            const Positioned.fill(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt,
                        color: Colors.white54, size: 60),
                    SizedBox(height: 12),
                    Text(
                      "Camera not available\n"
                      "Use 'Upload from Gallery' below",
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: Colors.white60, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),

          // Scanner frame overlay
          if (!kIsWeb && isCameraReady)
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Position sapling inside',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),

          // Bottom buttons
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Colors.transparent],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!kIsWeb)
                    ElevatedButton.icon(
                      onPressed: isProcessing ? null : captureImage,
                      icon: const Icon(Icons.camera_alt),
                      label: Text(
                        isProcessing ? 'Processing…' : 'Capture Image',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 55),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  if (!kIsWeb) const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: isProcessing ? null : uploadFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text(
                      'Upload from Gallery',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 55),
                      side: const BorderSide(
                          color: Colors.white, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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