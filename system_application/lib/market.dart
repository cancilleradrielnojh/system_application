// ========================= lib/market.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  int ready     = 0;
  int growth    = 0;
  int treatment = 0;
  int total     = 0; // detected saplings (used for health breakdown)
  int totalScans = 0; // scan images (must match History count)

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final data  = prefs.getStringList('history') ?? [];
    int r = 0, g = 0, t = 0;
    int totalDetections = 0;
    for (var item in data) {
      final decoded = jsonDecode(item);
      final detections = decoded['detections'];

      // New format: count every detected sapling in an image.
      if (detections is List && detections.isNotEmpty) {
        for (final det in detections) {
          if (det is! Map) continue;
          final healthVal = det['health'];
          if (healthVal is! num) continue;
          final health = healthVal.toDouble();
          totalDetections++;
          if (health >= 90) {
            r++;
          } else if (health >= 70) {
            g++;
          } else {
            t++;
          }
        }
      } else {
        // Backward compatibility: old entries had only one top detection.
        final healthVal = decoded['health'];
        if (healthVal is! num) continue;
        final health = healthVal.toDouble();
        totalDetections++;
        if (health >= 90) {
          r++;
        } else if (health >= 70) {
          g++;
        } else {
          t++;
        }
      }
    }
    setState(() {
      ready     = r;
      growth    = g;
      treatment = t;
      total     = totalDetections;
      totalScans = data.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Market Insights',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              totalScans == 0
                  ? 'No scans recorded yet'
                  : '$totalScans scan image(s) recorded',
              style: const TextStyle(
                  color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 20),

            // Summary banner
            if (total > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.eco,
                        color: Colors.white, size: 36),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Overall Health Rate',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13)),
                        Text(
                          '${((ready / total) * 100).toStringAsFixed(0)}% Healthy',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),
            const Text('Sapling Status',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    count: ready,
                    label: 'Healthy',
                    icon: Icons.spa,
                    color: Colors.green,
                    bgColor: Colors.green.shade50,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    count: growth,
                    label: 'Yellowing /\nNot Ready',
                    icon: Icons.wb_sunny,
                    color: Colors.orange,
                    bgColor: Colors.orange.shade50,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    count: treatment,
                    label: 'Pest /\nWilting',
                    icon: Icons.healing,
                    color: Colors.red,
                    bgColor: Colors.red.shade50,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    count: totalScans,
                    label: 'Total Scan Images',
                    icon: Icons.bar_chart,
                    color: Colors.blueGrey,
                    bgColor: Colors.blueGrey.shade50,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (total > 0) ...[
              const Text('Health Breakdown',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _BreakdownBar(
                  ready: ready,
                  growth: growth,
                  treatment: treatment),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Legend(color: Colors.green, label: 'Healthy'),
                  const SizedBox(width: 16),
                  _Legend(
                      color: Colors.orange,
                      label: 'Yellowing'),
                  const SizedBox(width: 16),
                  _Legend(
                      color: Colors.red,
                      label: 'Pest/Wilting'),
                ],
              ),
              const SizedBox(height: 24),
            ],

            const Text('Recent Transplant Decision',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            total == 0
                ? Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                          'No data yet — start scanning!',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black
                                .withValues(alpha: 0.05), // ✅ fixed
                            blurRadius: 8,
                            offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              Colors.orange.shade100,
                          child: const Icon(Icons.wb_sunny,
                              color: Colors.orange),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text('Latest Batch',
                                  style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold)),
                              Text(
                                  'Check History for full details',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                          child: const Text('VIEW',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final int count;
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _StatCard({
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: color.withValues(alpha: 0.3)), // ✅ fixed
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor:
                color.withValues(alpha: 0.15), // ✅ fixed
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(label,
                    style: TextStyle(
                        fontSize: 11,
                        color: color.withValues(alpha: 0.8))), // ✅ fixed
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  final int ready, growth, treatment;
  const _BreakdownBar(
      {required this.ready,
      required this.growth,
      required this.treatment});

  @override
  Widget build(BuildContext context) {
    final total = ready + growth + treatment;
    if (total == 0) return const SizedBox();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          if (ready > 0)
            Expanded(
                flex: ready,
                child: Container(height: 16, color: Colors.green)),
          if (growth > 0)
            Expanded(
                flex: growth,
                child: Container(height: 16, color: Colors.orange)),
          if (treatment > 0)
            Expanded(
                flex: treatment,
                child: Container(height: 16, color: Colors.red)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}