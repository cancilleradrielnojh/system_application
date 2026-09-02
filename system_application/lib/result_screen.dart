// ========================= lib/result_screen.dart =========================
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'detection/inference_service.dart';
import 'theme/app_theme.dart';

enum ResultAction { done, scanNew }

class ResultPayload {
  final ResultAction action;
  final List<DetectionResult> detections;

  ResultPayload({
    required this.action,
    required this.detections,
  });
}

class ResultScreen extends StatefulWidget {
  final String imagePath;
  const ResultScreen({super.key, required this.imagePath});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _analyzing = true;
  List<DetectionResult> _results = const [];
  DetectionResult? _best;
  ImageAnalysisResult? _analysis;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _runInference();
    });
  }

  /// Input: selected/captured image path from scanner flow.
  /// Output: updates local UI state with detection list or error.
  Future<void> _runInference() async {
    try {
      final res = await inferenceService.analyzeImage(widget.imagePath);
      if (!mounted) return;
      setState(() {
        _analysis = res;
        _results = res.detections;
        _best = res.detections.isNotEmpty ? res.detections.first : null;
        _analyzing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _analyzing = false;
      });
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────
  /// Input: optional class enum.
  /// Output: display color used across badges/cards.
  Color _classColor(SaplingClass? cls) {
    switch (cls) {
      case SaplingClass.healthy:
        return AppColors.healthy;
      case SaplingClass.yellowing:
        return AppColors.warn;
      case SaplingClass.wilting:
        return AppColors.wilt;
      case SaplingClass.pestDamaged:
        return AppColors.danger;
      case null:
        return AppColors.steel;
    }
  }

  /// Input: optional class enum.
  /// Output: icon used in recommendation cards.
  IconData _classIcon(SaplingClass? cls) {
    switch (cls) {
      case SaplingClass.healthy:
        return Icons.spa;
      case SaplingClass.yellowing:
        return Icons.wb_sunny;
      case SaplingClass.wilting:
        return Icons.water_drop;
      case SaplingClass.pestDamaged:
        return Icons.bug_report;
      case null:
        return Icons.help_outline;
    }
  }

  /// Input: optional class enum.
  /// Output: small emoji prefix for quick status recognition.
  String _statusEmoji(SaplingClass? cls) {
    switch (cls) {
      case SaplingClass.healthy:
        return '✅';
      case SaplingClass.yellowing:
        return '🟡';
      case SaplingClass.wilting:
        return '🥀';
      case SaplingClass.pestDamaged:
        return '🐛';
      case null:
        return '❓';
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────
  /// Input: current detection list.
  /// Output: returns to scanner/home with Done action payload.
  void _onDone() => Navigator.pop(
      context,
      ResultPayload(action: ResultAction.done, detections: _results));

  /// Input: current detection list.
  /// Output: returns with Scan New action payload.
  void _onScanNew() => Navigator.pop(
      context,
      ResultPayload(action: ResultAction.scanNew, detections: _results));

  /// Input: none.
  /// Output: closes result screen with null payload (retry path).
  void _onTryAgain() => Navigator.pop(context, null);

  /// Input: current screen state (`_analyzing`, `_error`, `_results`).
  /// Output: plain image or image with mapped detection boxes / leaf outlines.
  Widget _buildImagePreview() {
    final analysis = _analysis;
    if (_analyzing ||
        _error != null ||
        analysis == null ||
        _results.isEmpty ||
        _results.every((d) =>
            d.bboxLeft == null ||
            d.bboxTop == null ||
            d.bboxRight == null ||
            d.bboxBottom == null)) {
      if (analysis != null) {
        return Image.memory(
          analysis.displayBytes,
          width: double.infinity,
          fit: BoxFit.contain,
        );
      }
      return Image.file(
        File(widget.imagePath),
        width: double.infinity,
        fit: BoxFit.contain,
      );
    }
    return _ScanImageWithBboxes(
      analysis: analysis,
      detections: _results,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool hasDetections = _best != null;

    // Non-detection states start taller (0.32) so content is immediately
    // visible. Detection state starts as a peek (0.14) to show the image.
    final double initialSize =
        _analyzing || _error != null || !hasDetections ? 0.32 : 0.14;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          'SCAN RESULT',
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
            fontSize: 14,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          // RepaintBoundary isolates the image from the sheet's drag
          // repaints — without this, the image redraws on every drag pixel.
          Positioned.fill(
            child: RepaintBoundary(
              child: _buildImagePreview(),
            ),
          ),
          DraggableScrollableSheet(
            minChildSize: 0.10,
            initialChildSize: initialSize,
            maxChildSize: 0.90,
            snap: true,
            // Two snap points only — fewer targets = smoother animation.
            snapSizes: const [0.14, 0.60],
            builder: (context, scrollController) {
              // Material is cheaper than Container + BoxDecoration on every
              // drag frame because it skips allocating new decoration objects.
              // The thin top border line replaces the blurry BoxShadow which
              // was recalculated on the GPU every drag pixel.
              return Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: Column(
                  children: [
                    // Lightweight top border (replaces the expensive BoxShadow)
                    Container(
                      height: 0.5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.2),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24)),
                      ),
                    ),
                    Expanded(
                      child: _analyzing
                          ? _buildAnalyzingSheet(scrollController)
                          : _error != null
                              ? _buildErrorSheet(scrollController)
                              : !hasDetections
                                  ? _buildNotDetectedSheet(scrollController)
                                  : _buildDetected(scrollController),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Shared drag handle ────────────────────────────────────────────────

  /// Output: pill-shaped drag handle shown at the top of every sheet state.
  Widget _dragHandle() => Center(
        child: Container(
          width: 38,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      );

  // ── States ────────────────────────────────────────────────────────────

  /// Input: sheet scroll controller.
  /// Output: draggable loading state while inference is running.
  Widget _buildAnalyzingSheet(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      children: [
        _dragHandle(),
        const SizedBox(height: 8),
        const Center(
            child: CircularProgressIndicator(color: AppColors.teal, strokeWidth: 2.4)),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            'Reading the leaf…',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            'Running AI detection model',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }

  /// Input: sheet scroll controller + `_error` text set by inference failure.
  /// Output: draggable error panel with retry action.
  Widget _buildErrorSheet(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      children: [
        _dragHandle(),
        const SizedBox(height: 8),
        const Center(
            child: Icon(Icons.error_outline, color: Colors.red, size: 48)),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'Analysis Failed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        _actionButton(
          label: 'Try Again',
          color: AppColors.ink,
          icon: Icons.refresh,
          onTap: _onTryAgain,
        ),
      ],
    );
  }

  /// Input: sheet scroll controller (used when final detection list is empty).
  /// Output: draggable no-detection message panel with retry action.
  Widget _buildNotDetectedSheet(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
      children: [
        _dragHandle(),
        const SizedBox(height: 8),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.search_off, size: 48, color: Colors.grey),
          ),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'No Calamansi Sapling Detected',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'No calamansi leaf was recognized. Other plants, blurry shots, '
            'or leaves that are too small / overlapping may be rejected.\n'
            'This scan will NOT be saved.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        _actionButton(
          label: 'Try Again',
          color: AppColors.ink,
          icon: Icons.camera_alt,
          onTap: _onTryAgain,
        ),
      ],
    );
  }

  /// Input: draggable sheet scroll controller + finalized detection list.
  /// Output: recommendation list content shown in the bottom sheet.
  Widget _buildDetected(ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _dragHandle(),
        const SizedBox(height: 4),
        Text(
          'Detected calamansi saplings: ${_results.length}',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._results.map((r) {
          final color = _classColor(r.saplingClass);
          final icon = _classIcon(r.saplingClass);
          final emoji = _statusEmoji(r.saplingClass);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: color.withValues(alpha: 0.14),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$emoji ${r.className}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      Text(
                        '${r.healthScore.toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Confidence Score : ${(r.confidence * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: color.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Recommended actions',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    r.recommendation,
                    style: const TextStyle(fontSize: 12.5, height: 1.45),
                  ),
                ],
              ),
            ),
          );
        }),
        Row(
          children: [
            Expanded(
              child: _outlineButton(
                label: 'Done',
                icon: Icons.check_circle_outline,
                onTap: _onDone,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _actionButton(
                label: 'Scan New',
                icon: Icons.camera_alt,
                color: AppColors.ink,
                onTap: _onScanNew,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Button helpers ────────────────────────────────────────────────────

  /// Input: button label, color, icon, and callback.
  /// Output: primary filled action button.
  Widget _actionButton({
    required String label,
    required VoidCallback onTap,
    required Color color,
    IconData? icon,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon ?? Icons.arrow_forward, size: 18),
      label:
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: color == AppColors.ink ? AppColors.lime : Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// Input: button label, optional icon, and callback.
  /// Output: outlined secondary action button.
  Widget _outlineButton({
    required String label,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon ?? Icons.check, size: 18),
      label:
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Letterboxed model coords (640×640) → original image → on-screen rect
// for [BoxFit.contain].
// ─────────────────────────────────────────────────────────────────────────────

class _ScanImageWithBboxes extends StatelessWidget {
  final ImageAnalysisResult analysis;
  final List<DetectionResult> detections;

  const _ScanImageWithBboxes({
    required this.analysis,
    required this.detections,
  });

  /// Map a letterbox-space point into display-image pixel coordinates.
  Offset _toDisplay(double lx, double ly) {
    final srcX = (lx - analysis.padX) / analysis.letterboxScale;
    final srcY = (ly - analysis.padY) / analysis.letterboxScale;
    final sx = analysis.displayWidth / analysis.imageWidth;
    final sy = analysis.displayHeight / analysis.imageHeight;
    return Offset(
      (srcX * sx).clamp(0.0, analysis.displayWidth.toDouble()),
      (srcY * sy).clamp(0.0, analysis.displayHeight.toDouble()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dwImg = analysis.displayWidth.toDouble();
    final dhImg = analysis.displayHeight.toDouble();

    final modelBoxes = detections.where((d) =>
        d.bboxLeft != null &&
        d.bboxTop != null &&
        d.bboxRight != null &&
        d.bboxBottom != null);

    final mapped = modelBoxes.map((d) {
      final tl = _toDisplay(d.bboxLeft!, d.bboxTop!);
      final br = _toDisplay(d.bboxRight!, d.bboxBottom!);
      final rect = Rect.fromLTRB(
        math.min(tl.dx, br.dx),
        math.min(tl.dy, br.dy),
        math.max(tl.dx, br.dx),
        math.max(tl.dy, br.dy),
      );

      List<Offset>? outline;
      final poly = d.maskPolygon;
      if (poly != null && poly.length >= 3) {
        outline = poly
            .map((p) => _toDisplay(p[0], p[1]))
            .toList(growable: false);
      }

      final label = '${d.className}  ${(d.confidence * 100).toStringAsFixed(1)}%';
      return _MappedBox(
        rect: rect,
        label: label,
        confidence: d.confidence,
        outline: outline,
      );
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;
        final scale2 = math.min(cw / dwImg, ch / dhImg);
        final dw = dwImg * scale2;
        final dh = dhImg * scale2;
        final dx = (cw - dw) / 2;
        final dy = (ch - dh) / 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Image.memory(
                analysis.displayBytes,
                fit: BoxFit.contain,
                width: cw,
                height: ch,
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _BboxesOverlayPainter(
                  mapped: mapped,
                  scale2: scale2,
                  dx: dx,
                  dy: dy,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MappedBox {
  final Rect rect;
  final String label;
  final double confidence;
  final List<Offset>? outline;
  _MappedBox({
    required this.rect,
    required this.label,
    required this.confidence,
    this.outline,
  });
}

class _BboxesOverlayPainter extends CustomPainter {
  _BboxesOverlayPainter({
    required this.mapped,
    required this.scale2,
    required this.dx,
    required this.dy,
  });

  final List<_MappedBox> mapped;
  final double scale2;
  final double dx;
  final double dy;

  @override
  void paint(Canvas canvas, Size size) {
    final boxStroke = Paint()
      ..color = AppColors.lime.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final outlineStroke = Paint()
      ..color = AppColors.lime
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final outlineFill = Paint()
      ..color = AppColors.lime.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    for (final item in mapped) {
      final r = Rect.fromLTRB(
        dx + item.rect.left * scale2,
        dy + item.rect.top * scale2,
        dx + item.rect.right * scale2,
        dy + item.rect.bottom * scale2,
      );

      final outline = item.outline;
      if (outline != null && outline.length >= 3) {
        final path = Path()
          ..moveTo(
            dx + outline.first.dx * scale2,
            dy + outline.first.dy * scale2,
          );
        for (var i = 1; i < outline.length; i++) {
          path.lineTo(
            dx + outline[i].dx * scale2,
            dy + outline[i].dy * scale2,
          );
        }
        path.close();
        canvas.drawPath(path, outlineFill);
        canvas.drawPath(path, outlineStroke);
      } else {
        canvas.drawRect(r, boxStroke);
      }

      final tp = TextPainter(
        text: TextSpan(
          text: item.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            backgroundColor: AppColors.ink,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelY = r.top - tp.height - 4;
      final labelDy = labelY < 0 ? r.bottom + 4 : labelY;
      tp.paint(canvas, Offset(r.left, labelDy));
    }
  }

  @override
  bool shouldRepaint(covariant _BboxesOverlayPainter oldDelegate) {
    if (oldDelegate.scale2 != scale2 ||
        oldDelegate.dx != dx ||
        oldDelegate.dy != dy) {
      return true;
    }
    if (oldDelegate.mapped.length != mapped.length) return true;
    for (var i = 0; i < mapped.length; i++) {
      if (oldDelegate.mapped[i].label != mapped[i].label ||
          oldDelegate.mapped[i].rect != mapped[i].rect ||
          oldDelegate.mapped[i].outline?.length !=
              mapped[i].outline?.length) {
        return true;
      }
    }
    return false;
  }
}