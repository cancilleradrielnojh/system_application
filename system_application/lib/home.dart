// ========================= lib/home.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'history.dart';
import 'market.dart';
import 'account_settings.dart';
import 'scanner.dart';
import 'profile_settings/notification_service.dart';
import 'detection/inference_service.dart';

class Home extends StatefulWidget {
  final String name;
  const Home({super.key, required this.name});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int    currentIndex = 0;
  int    scansToday   = 0;
  double avgHealth    = 0;
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _displayName = widget.name;
    loadStats();
    NotificationService.init();
  }

  Future<void> loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      scansToday   = prefs.getInt('scansToday')   ?? 0;
      avgHealth    = prefs.getDouble('avgHealth')  ?? 0;
      _displayName = prefs.getString('username')   ?? widget.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      homeUI(),
      const HistoryPage(),
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
        onTap: (i) => setState(() => currentIndex = i),
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(
              icon: Icon(Icons.show_chart), label: 'Market'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget homeUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hello, $_displayName!',
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: card('Scans Today', scansToday.toString())),
              const SizedBox(width: 10),
              Expanded(
                child: card(
                  'Avg. Health',
                  avgHealth == 0
                      ? '--'
                      : '${avgHealth.toStringAsFixed(0)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              minimumSize: const Size(double.infinity, 60),
            ),
            child: const Text(
              'START SCANNING',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Recent Scans',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          scansToday == 0
              ? const Text('No scans yet',
                  style: TextStyle(color: Colors.grey))
              : ListTile(
                  leading: const Icon(Icons.wb_sunny,
                      color: Colors.orange),
                  title: const Text('Latest Scan'),
                  subtitle: Text(
                    '$scansToday scan(s) today — tap History to view details',
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> saveScan(String imagePath, List<DetectionResult> detections) async {
    final prefs   = await SharedPreferences.getInstance();
    List<String> history =
        prefs.getStringList('history') ?? [];

    final detectionsSafe = detections.where((d) => d.isCalamansi).toList();
    if (detectionsSafe.isEmpty) return;

    // For legacy fields + summary banners: use the highest-confidence detection.
    final top = detectionsSafe.reduce((a, b) => a.confidence > b.confidence ? a : b);
    final double imageAvgHealth =
        detectionsSafe.map((d) => d.healthScore).reduce((a, b) => a + b) /
        detectionsSafe.length;

    final newScan = {
      'image':  imagePath,
      // Legacy fields (keep old UI working)
      'health': top.healthScore,
      'label':  top.className,
      'confidence': top.confidence,
      'boxAreaPx':  top.boxAreaPx,
      'recommendation': top.recommendation,
      // New: full per-image detections list
      'detections': detectionsSafe
          .map((d) => {
                'label': d.className,
                'health': d.healthScore,
                'confidence': d.confidence,
                'boxAreaPx': d.boxAreaPx,
                'recommendation': d.recommendation,
              })
          .toList(),
      'time':   DateTime.now().toString(),
    };
    history.add(jsonEncode(newScan));
    await prefs.setStringList('history', history);

    final newCount = scansToday + 1;
    final newAvg   = ((imageAvgHealth * scansToday) + imageAvgHealth) / newCount;
    await prefs.setInt('scansToday', newCount);
    await prefs.setDouble('avgHealth', newAvg);

    setState(() {
      scansToday = newCount;
      avgHealth  = newAvg;
    });

    await NotificationService.sendScanNotification(
      success: true,
      health: avgHealth,
      detections: detectionsSafe,
    );
  }

  Widget card(String title, String value) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color cardBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : Colors.grey.shade200;
    final Color titleColor = theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.9)
        ?? (isDark ? Colors.white70 : Colors.black87);
    final Color valueColor = theme.textTheme.titleLarge?.color
        ?? (isDark ? Colors.white : Colors.black);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: titleColor)),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }
}