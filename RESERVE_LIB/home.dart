// ========================= lib/home.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:google_fonts/google_fonts.dart';

import 'history.dart';
import 'market.dart';
import 'account_settings.dart';
import 'scanner.dart';
import 'profile_settings/notification_service.dart';
import 'profile_settings/name_notifier.dart';
import 'detection/inference_service.dart';
import 'data/database_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_widgets.dart';

class Home extends StatefulWidget {
  final String name;
  const Home({super.key, required this.name});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int    currentIndex  = 0;
  int    scansToday    = 0;
  int    totalScans    = 0;
  String _displayName  = '';
  List<Map<String, dynamic>> _recentScans = [];

  @override
  void initState() {
    super.initState();
    _displayName = widget.name;
    loadStats();
    NotificationService.init();
    nameNotifier.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    nameNotifier.removeListener(_onNameChanged);
    super.dispose();
  }

  void _onNameChanged() {
    if (!mounted) return;
    setState(() => _displayName = nameNotifier.value);
  }

  Future<void> loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('username');

    final todayCount = await DatabaseService.countToday();
    final totalCount = await DatabaseService.countAll();
    final recent     = await DatabaseService.getRecentScans(3);

    if (!mounted) return;
    setState(() {
      scansToday   = todayCount;
      totalScans   = totalCount;
      _recentScans = recent;
      if (saved != null && saved.isNotEmpty) _displayName = saved;
    });
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String get _todayLabel {
    final now = DateTime.now();
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[now.weekday]}, ${months[now.month]} ${now.day}';
  }

  String _formatTime(String raw) {
    try {
      final dt = DateTime.parse(raw);
      const months = [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final h    = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final m    = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month]} ${dt.day}, ${dt.year} · $h:$m $ampm';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeUI(),
      HistoryPage(onHistoryChanged: loadStats),
      const MarketScreen(),
      AccountSettingsScreen(name: widget.name, onDataCleared: loadStats),
    ];

    return Scaffold(
      body: AppBackdrop(
        child: SafeArea(child: pages[currentIndex]),
      ),
      bottomNavigationBar: FuturisticNavBar(
        index: currentIndex,
        onTap: (i) => setState(() => currentIndex = i),
      ),
    );
  }

  Widget homeUI() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? AppColors.darkText : AppColors.ink;
    final muted = isDark ? AppColors.darkMuted : AppColors.steel;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const BrandMark(size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Q-LAMANSI',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.6,
                        color: muted,
                      ),
                    ),
                    Text(
                      '$_greeting, $_displayName',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _todayLabel,
            style: GoogleFonts.dmSans(fontSize: 13, color: muted),
          ),

          const SizedBox(height: 22),

          Row(
            children: [
              Expanded(
                child: _metricTile(
                  label: 'Today',
                  value: scansToday.toString(),
                  accent: AppColors.lime,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metricTile(
                  label: 'All time',
                  value: totalScans.toString(),
                  accent: AppColors.teal,
                  isDark: isDark,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          LimeCta(
            label: 'START SCAN',
            icon: Icons.center_focus_strong_rounded,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScannerScreen(
                    onScanComplete: (imagePath, detections, analysis) =>
                        saveScan(imagePath, detections, analysis),
                  ),
                ),
              );
              loadStats();
            },
          ),

          const SizedBox(height: 28),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent scans',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              if (totalScans > 0)
                GestureDetector(
                  onTap: () => setState(() => currentIndex = 1),
                  child: Text(
                    'See all',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.lime : AppColors.tealDeep,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          _recentScans.isEmpty
              ? _emptyScansPlaceholder(isDark)
              : Column(
                  children: _recentScans
                      .map((scan) => _recentScanCard(scan, isDark))
                      .toList(),
                ),
        ],
      ),
    );
  }

  Widget _metricTile({
    required String label,
    required String value,
    required Color accent,
    required bool isDark,
  }) {
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: isDark ? AppColors.darkMuted : AppColors.steel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              color: isDark ? AppColors.darkText : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentScanCard(Map<String, dynamic> scan, bool isDark) {
    final imagePath = scan['image'] as String? ?? '';
    final label     = scan['label']  as String? ?? 'Unknown';
    final time      = _formatTime(scan['time'] as String? ?? '');
    final detCount  = (scan['detections'] as List?)?.length ?? 0;
    final color     = AppTheme.healthColor(label);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 58,
                height: 58,
                child: (!kIsWeb && imagePath.isNotEmpty)
                    ? Image.file(File(imagePath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                              color: isDark
                                  ? AppColors.darkLine
                                  : AppColors.mistDeep,
                              child: const Icon(Icons.image_not_supported,
                                  size: 26),
                            ))
                    : Container(
                        color: isDark ? AppColors.darkLine : AppColors.mistDeep,
                        child: Icon(Icons.image,
                            size: 26,
                            color: isDark
                                ? AppColors.darkMuted
                                : AppColors.steel),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Calamansi · $detCount sapling${detCount == 1 ? '' : 's'}',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isDark ? AppColors.darkText : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    time,
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      color: isDark ? AppColors.darkMuted : AppColors.steel,
                    ),
                  ),
                ],
              ),
            ),
            StatusChip(label: label, color: color),
          ],
        ),
      ),
    );
  }

  Widget _emptyScansPlaceholder(bool isDark) {
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        children: [
          Icon(
            Icons.eco_outlined,
            size: 42,
            color: (isDark ? AppColors.lime : AppColors.teal)
                .withValues(alpha: 0.55),
          ),
          const SizedBox(height: 12),
          Text(
            'No scans yet',
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: isDark ? AppColors.darkText : AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Frame a leaf and start your first scan',
            style: GoogleFonts.dmSans(
              color: isDark ? AppColors.darkMuted : AppColors.steel,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Maps a letterbox-space X coordinate into pixel space of the saved
  /// display image (mirrors ResultScreen's `_ScanImageWithBboxes._toDisplay`).
  double? _outlineX(double? lx, ImageAnalysisResult a) {
    if (lx == null) return null;
    final srcX = (lx - a.padX) / a.letterboxScale;
    final scaleX = a.displayWidth / a.imageWidth;
    return (srcX * scaleX).clamp(0.0, a.displayWidth.toDouble());
  }

  /// Maps a letterbox-space Y coordinate into pixel space of the saved
  /// display image (mirrors ResultScreen's `_ScanImageWithBboxes._toDisplay`).
  double? _outlineY(double? ly, ImageAnalysisResult a) {
    if (ly == null) return null;
    final srcY = (ly - a.padY) / a.letterboxScale;
    final scaleY = a.displayHeight / a.imageHeight;
    return (srcY * scaleY).clamp(0.0, a.displayHeight.toDouble());
  }

  Future<void> saveScan(String imagePath, List<DetectionResult> detections,
      ImageAnalysisResult? analysis) async {

    final detectionsSafe = detections.where((d) => d.isCalamansi).toList();
    if (detectionsSafe.isEmpty) return;

    String permanentPath = imagePath;
    if (!kIsWeb) {
      try {
        final appDir  = await getApplicationDocumentsDirectory();
        final scanDir = Directory(p.join(appDir.path, 'scan_images'));
        if (!await scanDir.exists()) await scanDir.create(recursive: true);

        final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destFile = File(p.join(scanDir.path, fileName));
        if (analysis != null) {
          // Use the same EXIF-corrected, upright image the outline
          // coordinates below were computed against, so the overlay
          // drawn later in History lines up pixel-for-pixel.
          await destFile.writeAsBytes(analysis.displayBytes);
        } else {
          await File(imagePath).copy(destFile.path);
        }
        permanentPath = destFile.path;
      } catch (e) {
        debugPrint('Image save failed, using original path: $e');
      }
    }

    // Sort by spatial position — left-to-right, top-to-bottom — so that
    // "Sapling 1, 2, 3…" in history always matches the numbered overlay.
    detectionsSafe.sort((a, b) {
      final aTop  = a.bboxTop  ?? double.infinity;
      final bTop  = b.bboxTop  ?? double.infinity;
      final aLeft = a.bboxLeft ?? double.infinity;
      final bLeft = b.bboxLeft ?? double.infinity;
      final topDiff = aTop - bTop;
      if (topDiff.abs() > 50) return topDiff < 0 ? -1 : 1;
      return aLeft.compareTo(bLeft);
    });

    final top = detectionsSafe
        .reduce((a, b) => a.confidence > b.confidence ? a : b);
    final double imageAvgHealth =
        detectionsSafe.map((d) => d.healthScore).reduce((a, b) => a + b) /
        detectionsSafe.length;

    final newScan = {
      'image':          permanentPath,
      'health':         top.healthScore,
      'label':          top.className,
      'confidence':     top.confidence,
      'boxAreaPx':      top.boxAreaPx,
      'recommendation': top.recommendation,
      'detections':     detectionsSafe
          .asMap()
          .entries
          .map((entry) {
            final d = entry.value;
            return {
              'number':         entry.key + 1,
              'label':          d.className,
              'health':         d.healthScore,
              'confidence':     d.confidence,
              'boxAreaPx':      d.boxAreaPx,
              'recommendation': d.recommendation,
              'outline': analysis == null
                  ? null
                  : {
                      // Pixel dimensions of the saved image these
                      // coordinates are relative to.
                      'imageWidth':  analysis.displayWidth,
                      'imageHeight': analysis.displayHeight,
                      'bboxLeft':    _outlineX(d.bboxLeft, analysis),
                      'bboxTop':     _outlineY(d.bboxTop, analysis),
                      'bboxRight':   _outlineX(d.bboxRight, analysis),
                      'bboxBottom':  _outlineY(d.bboxBottom, analysis),
                      'polygon': d.maskPolygon
                          ?.map((pt) => [
                                _outlineX(pt[0], analysis),
                                _outlineY(pt[1], analysis),
                              ])
                          .toList(),
                    },
            };
          })
          .toList(),
      'time': DateTime.now().toString(),
    };

    await DatabaseService.insertScan(newScan);

    await NotificationService.sendScanNotification(
      success: true,
      health: imageAvgHealth,
      detections: detectionsSafe,
    );

    await loadStats();
  }
}