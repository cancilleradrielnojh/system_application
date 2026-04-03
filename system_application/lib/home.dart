// ========================= lib/home.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'history.dart';
import 'market.dart';
import 'account_settings.dart';
import 'scanner.dart';
import 'profile_settings/notification_service.dart';
import 'profile_settings/name_notifier.dart';
import 'detection/inference_service.dart';
import 'data/database_service.dart';

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
    // ── SharedPreferences: only for username (unchanged) ──────────────────
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('username');

    // ── SQLite: scan history ───────────────────────────────────────────────
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

  Color _healthColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('healthy')) return Colors.green;
    if (l.contains('yellow'))  return Colors.orange;
    if (l.contains('wilt'))    return const Color(0xFF7B5EA7);
    if (l.contains('pest'))    return Colors.red;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeUI(),
      HistoryPage(onHistoryChanged: loadStats),
      const MarketScreen(),
      AccountSettingsScreen(name: widget.name),
    ];

    return Scaffold(
      body: SafeArea(child: pages[currentIndex]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
        onTap: (i) => setState(() => currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded),    label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history_rounded),  label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart),       label: 'Market'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }

  Widget homeUI() {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_greeting,',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _displayName,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHighest
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        size: 13, color: Colors.green.shade700),
                    const SizedBox(width: 5),
                    Text(
                      _todayLabel,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Stat Cards
          Row(
            children: [
              Expanded(child: _statCard(
                title: 'Scans Today',
                value: scansToday.toString(),
                icon: Icons.today_rounded,
                gradient: [const Color(0xFF2E7D32), const Color(0xFF66BB6A)],
              )),
              const SizedBox(width: 12),
              Expanded(child: _statCard(
                title: 'Total Scans',
                value: totalScans.toString(),
                icon: Icons.bar_chart_rounded,
                gradient: [const Color(0xFF1565C0), const Color(0xFF42A5F5)],
              )),
            ],
          ),

          const SizedBox(height: 24),

          // Scan Button
          GestureDetector(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScannerScreen(
                    onScanComplete: (imagePath, detections) =>
                        saveScan(imagePath, detections),
                  ),
                ),
              );
              loadStats();
            },
            child: Container(
              width: double.infinity,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_scanner_rounded,
                      color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'START SCANNING',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Recent Scans header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Scans',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (totalScans > 0)
                GestureDetector(
                  onTap: () => setState(() => currentIndex = 1),
                  child: Text(
                    'See all',
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600),
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

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required List<Color> gradient,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradient.last.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
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
    final color     = _healthColor(label);
    final cardBg    = isDark
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Colors.white;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: (!kIsWeb && imagePath.isNotEmpty)
                  ? Image.file(File(imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image_not_supported, size: 28))
                  : Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.image, size: 28, color: Colors.grey),
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
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 3),
                Text(time,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyScansPlaceholder(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.grass_rounded,
              size: 48, color: Colors.green.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          const Text('No scans yet',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 4),
          const Text('Tap Start Scanning to begin',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> saveScan(
      String imagePath, List<DetectionResult> detections) async {

    final detectionsSafe = detections.where((d) => d.isCalamansi).toList();
    if (detectionsSafe.isEmpty) return;

    // ── Copy image to permanent app storage so it survives cache clears ───
    String permanentPath = imagePath;
    if (!kIsWeb) {
      try {
        final appDir  = await getApplicationDocumentsDirectory();
        final scanDir = Directory(p.join(appDir.path, 'scan_images'));
        if (!await scanDir.exists()) await scanDir.create(recursive: true);

        final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final destFile = File(p.join(scanDir.path, fileName));
        await File(imagePath).copy(destFile.path);
        permanentPath = destFile.path;
      } catch (e) {
        debugPrint('Image copy failed, using original path: $e');
      }
    }

    // ── Build scan record ──────────────────────────────────────────────────
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
          .map((d) => {
                'label':          d.className,
                'health':         d.healthScore,
                'confidence':     d.confidence,
                'boxAreaPx':      d.boxAreaPx,
                'recommendation': d.recommendation,
              })
          .toList(),
      'time': DateTime.now().toString(),
    };

    // ── Persist to SQLite ──────────────────────────────────────────────────
    await DatabaseService.insertScan(newScan);

    await NotificationService.sendScanNotification(
      success: true,
      health: imageAvgHealth,
      detections: detectionsSafe,
    );

    await loadStats();
  }
}