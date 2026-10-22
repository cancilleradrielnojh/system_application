// ========================= lib/history.dart =========================
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/database_service.dart';
import 'theme/app_theme.dart';

class HistoryPage extends StatefulWidget {
  final VoidCallback? onHistoryChanged;
  const HistoryPage({super.key, this.onHistoryChanged});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    // ── SQLite: getAllScans already returns newest-first ───────────────────
    final rows = await DatabaseService.getAllScans();
    if (!mounted) return;
    setState(() => _history = rows);
  }

  Future<void> _deleteScan(int id) async {
    // ── SQLite: delete by primary key ─────────────────────────────────────
    await DatabaseService.deleteScan(id);
    widget.onHistoryChanged?.call();
    if (!mounted) return;
    setState(() => _history.removeWhere((s) => s['id'] == id));
  }

  // ── Helpers ─────────────────────────────────────────────────────
  Color _healthColor(String label) => AppTheme.healthColor(label);

  Color _healthColorFromScore(double health) {
    if (health >= 90) return AppColors.healthy;
    if (health >= 60) return AppColors.warn;
    if (health >= 40) return AppColors.wilt;
    return AppColors.danger;
  }

  /// Input: class label string saved in the database.
  /// Output: matching emoji prefix so history numbering mirrors the result screen.
  String _statusEmoji(String label) {
    switch (label.toLowerCase()) {
      case 'healthy':      return '✅';
      case 'yellowing':    return '🟡';
      case 'wilting':      return '🥀';
      case 'pest-damaged': return '🐛';
      default:             return '❓';
    }
  }

  String _formatTime(String raw) {
    try {
      final dt     = DateTime.parse(raw);
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final h    = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m    = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month]} ${dt.day}, ${dt.year}  $h:$m $ampm';
    } catch (_) {
      return raw;
    }
  }

  /// Groups scans into Today / Yesterday / date-labelled buckets.
  String _groupLabel(String timeStr) {
    try {
      final dt    = DateTime.parse(timeStr);
      final today = DateTime.now();
      final diff  = DateTime(today.year, today.month, today.day)
          .difference(DateTime(dt.year, dt.month, dt.day))
          .inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[dt.month]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return 'Earlier';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Build grouped list
    final List<_Group> groups = [];
    String? currentLabel;
    for (int i = 0; i < _history.length; i++) {
      final scan  = _history[i];
      final label = _groupLabel(scan['time'] as String? ?? '');
      if (label != currentLabel) {
        currentLabel = label;
        groups.add(_Group(label: label, items: []));
      }
      groups.last.items.add(_GroupItem(scan: scan));
    }

    return RefreshIndicator(
      onRefresh: loadHistory,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Scan History',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                if (_history.isNotEmpty)
                  TextButton.icon(
                    onPressed: _confirmClearAll,
                    icon: const Icon(Icons.delete_sweep_rounded,
                        size: 18, color: Colors.redAccent),
                    label: const Text('Clear all',
                        style: TextStyle(
                            color: Colors.redAccent, fontSize: 13)),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
              ],
            ),
            Text(
              '${_history.length} scan${_history.length == 1 ? '' : 's'} recorded',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),

            // List
            _history.isEmpty
                ? Expanded(child: _emptyState(isDark))
                : Expanded(
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: groups.length,
                      itemBuilder: (context, gi) {
                        final group = groups[gi];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date group header
                            Padding(
                              padding: const EdgeInsets.fromLTRB(2, 8, 0, 6),
                              child: Text(
                                group.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            ...group.items.map((item) =>
                                _scanCard(item.scan, isDark)),
                          ],
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  // ── Full-screen image viewer ─────────────────────────────────────
  /// Input: saved image path for the selected history entry.
  /// Output: full-screen overlay with pinch-to-zoom so the user can
  ///         inspect the original scanned photo.
  void _showFullScreenImage(String imagePath, List<dynamic> detectionsList) {
    if (imagePath.isEmpty) return;
    final hasOutlines = detectionsList.any((d) =>
        d is Map && d['outline'] != null && (d['outline'] as Map)['bboxLeft'] != null);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 6.0,
                child: hasOutlines
                    ? _HistoryScanImageWithOverlay(
                        imagePath: imagePath,
                        detectionsList: detectionsList,
                      )
                    : Image.file(
                        File(imagePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Center(
                          child: Icon(Icons.image_not_supported,
                              color: Colors.white54, size: 64),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    shape: const CircleBorder(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Scan Card ───────────────────────────────────────────────────
  Widget _scanCard(Map<String, dynamic> scan, bool isDark) {
    final scanId         = scan['id'] as int;
    final imagePath      = scan['image'] as String? ?? '';
    final topLabel       = scan['label'] as String? ?? 'Unknown';
    final time           = _formatTime(scan['time'] as String? ?? '');
    final detectionsList = (scan['detections'] as List?) ?? [];
    final recommendation = scan['recommendation'] as String? ?? '';
    final labelColor     = _healthColor(topLabel);

    return Dismissible(
      key: ValueKey('scan_$scanId'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_rounded, color: Colors.white, size: 26),
            SizedBox(height: 4),
            Text('Delete', style: TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) => _deleteScan(scanId),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: isDark ? 0 : 2,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: GestureDetector(
            onTap: () => _showFullScreenImage(imagePath, detectionsList),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 54,
                height: 54,
                child: (!kIsWeb && imagePath.isNotEmpty)
                    ? Image.file(File(imagePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.image_not_supported))
                    : Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.image, size: 28, color: Colors.grey),
                      ),
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  'Calamansi · ${detectionsList.length} detected',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              // Status badge visible without expanding
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: labelColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: labelColor.withValues(alpha: 0.35)),
                ),
                child: Text(
                  topLabel,
                  style: TextStyle(
                      fontSize: 10,
                      color: labelColor,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              time,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkMuted : AppColors.steel,
                  letterSpacing: 0.4),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 16),
                  if (detectionsList.isNotEmpty) ...[
                    const Text(
                      'Recommendations per sapling',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ...detectionsList.asMap().entries.map((entry) {
                      final i      = entry.key;
                      final det    = entry.value as Map<String, dynamic>;
                      final dLabel = (det['label'] as String?) ?? 'Unknown';
                      final dHealth =
                          (det['health'] as num?)?.toDouble() ?? 0.0;
                      final dRec   = (det['recommendation'] as String?) ?? '';
                      final dConf  =
                          (det['confidence'] as num?)?.toDouble() ?? 0.0;
                      final dColor = _healthColorFromScore(dHealth);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: dColor.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: dColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Label + confidence row
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: dColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '#${i + 1} ${_statusEmoji(dLabel)} $dLabel',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: dColor,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${(dConf * 100).toStringAsFixed(0)}% confidence',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: dColor.withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                dRec.isNotEmpty
                                    ? dRec
                                    : 'No recommendation available.',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ] else if (recommendation.isNotEmpty) ...[
                    const Text('Recommendation',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(recommendation,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ] else
                    const Text('No recommendation available.',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ─────────────────────────────────────────────────
  Widget _emptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded,
              size: 64,
              color: Colors.grey.withValues(alpha: 0.35)),
          const SizedBox(height: 16),
          const Text('No history yet',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Your scan records will appear here',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  // ── Dialogs ─────────────────────────────────────────────────────
  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete scan?'),
        content: const Text(
            'This scan record will be permanently removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear all history?'),
        content: const Text(
            'All scan records will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear all',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      // ── SQLite: delete all scans ───────────────────────────────────────
      await DatabaseService.deleteAllScans();
      if (!mounted) return;
      setState(() => _history = []);
      widget.onHistoryChanged?.call();
    }
  }
}

// ── Data helpers ─────────────────────────────────────────────────
class _Group {
  final String label;
  final List<_GroupItem> items;
  _Group({required this.label, required this.items});
}

class _GroupItem {
  final Map<String, dynamic> scan;
  _GroupItem({required this.scan});
}

// ── Full-screen overlay: outline + number + classification per sapling ────
// Coordinates in each detection's `outline` map are already expressed in
// pixel space of the saved image (converted once in home.dart's saveScan),
// so no letterbox un-mapping is needed here — just scale to the on-screen
// widget size, mirroring result_screen.dart's `_ScanImageWithBboxes`.
class _HistoryScanImageWithOverlay extends StatelessWidget {
  final String imagePath;
  final List<dynamic> detectionsList;

  const _HistoryScanImageWithOverlay({
    required this.imagePath,
    required this.detectionsList,
  });

  @override
  Widget build(BuildContext context) {
    // Reference pixel size of the saved image, taken from the first
    // detection that carries outline data (shared by the whole scan).
    double? imgW;
    double? imgH;
    final boxes = <_HistoryMappedBox>[];

    for (final d in detectionsList) {
      if (d is! Map) continue;
      final outline = d['outline'];
      if (outline is! Map) continue;

      imgW ??= (outline['imageWidth'] as num?)?.toDouble();
      imgH ??= (outline['imageHeight'] as num?)?.toDouble();

      final left   = (outline['bboxLeft']   as num?)?.toDouble();
      final top    = (outline['bboxTop']    as num?)?.toDouble();
      final right  = (outline['bboxRight']  as num?)?.toDouble();
      final bottom = (outline['bboxBottom'] as num?)?.toDouble();
      if (left == null || top == null || right == null || bottom == null) {
        continue;
      }

      List<Offset>? polygon;
      final poly = outline['polygon'];
      if (poly is List && poly.length >= 3) {
        final pts = poly
            .whereType<List>()
            .where((p) => p.length >= 2)
            .map((p) => Offset(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList();
        if (pts.length >= 3) polygon = pts;
      }

      final number = (d['number'] as num?)?.toInt() ?? (boxes.length + 1);
      final label  = (d['label'] as String?) ?? 'Unknown';
      final conf   = (d['confidence'] as num?)?.toDouble() ?? 0.0;

      boxes.add(_HistoryMappedBox(
        rect: Rect.fromLTRB(
          math.min(left, right),
          math.min(top, bottom),
          math.max(left, right),
          math.max(top, bottom),
        ),
        label: '#$number $label  ${(conf * 100).toStringAsFixed(1)}%',
        outline: polygon,
      ));
    }

    final fallback = Image.file(
      File(imagePath),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.image_not_supported, color: Colors.white54, size: 64),
      ),
    );

    if (imgW == null || imgH == null || imgW <= 0 || imgH <= 0 || boxes.isEmpty) {
      return fallback;
    }
    final refW = imgW, refH = imgH;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;
        if (!cw.isFinite || !ch.isFinite) return fallback;

        final scale2 = math.min(cw / refW, ch / refH);
        final dx = (cw - refW * scale2) / 2;
        final dy = (ch - refH * scale2) / 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Image.file(
                File(imagePath),
                fit: BoxFit.contain,
                width: cw,
                height: ch,
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.image_not_supported,
                      color: Colors.white54, size: 64),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _HistoryOverlayPainter(
                  boxes: boxes,
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

class _HistoryMappedBox {
  final Rect rect;
  final String label;
  final List<Offset>? outline;
  _HistoryMappedBox({required this.rect, required this.label, this.outline});
}

class _HistoryOverlayPainter extends CustomPainter {
  _HistoryOverlayPainter({
    required this.boxes,
    required this.scale2,
    required this.dx,
    required this.dy,
  });

  final List<_HistoryMappedBox> boxes;
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

    for (final item in boxes) {
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
            fontSize: 8,
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
  bool shouldRepaint(covariant _HistoryOverlayPainter oldDelegate) {
    if (oldDelegate.scale2 != scale2 ||
        oldDelegate.dx != dx ||
        oldDelegate.dy != dy) {
      return true;
    }
    if (oldDelegate.boxes.length != boxes.length) return true;
    for (var i = 0; i < boxes.length; i++) {
      if (oldDelegate.boxes[i].label != boxes[i].label ||
          oldDelegate.boxes[i].rect != boxes[i].rect ||
          oldDelegate.boxes[i].outline?.length != boxes[i].outline?.length) {
        return true;
      }
    }
    return false;
  }
}