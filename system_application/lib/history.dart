// ========================= lib/history.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> history = [];

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList('history') ?? [];
    setState(() {
      history = raw
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    });
  }

  Color healthColor(double health) {
    if (health >= 90) return Colors.green;
    if (health >= 60) return const Color(0xFFD4A017);
    if (health >= 40) return Colors.orange;
    return Colors.red;
  }

  String healthLabel(double health) {
    if (health >= 90) return 'Healthy';
    if (health >= 60) return 'Yellowing';
    if (health >= 40) return 'Wilting';
    return 'Pest-Damaged';
  }

  String formatTime(String raw) {
    try {
      final dt = DateTime.parse(raw);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: loadHistory,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Scan History',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('${history.length} scan(s) recorded',
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            history.isEmpty
                ? const Expanded(
                    child: Center(
                        child: Text('No history yet. Start scanning!')),
                  )
                : Expanded(
                    child: ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final scan      = history[index];
                        final String imagePath = scan['image'] ?? '';
                        final List<dynamic> detectionsList =
                            (scan['detections'] as List?) ?? const [];
                        final String recommendation =
                            (scan['recommendation'] as String?) ?? '';
                        final String time =
                            formatTime(scan['time'] ?? '');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: (!kIsWeb && imagePath.isNotEmpty)
                                    ? Image.file(
                                        File(imagePath),
                                        fit: BoxFit.cover,
                                        // ✅ fixed: unique param names
                                        errorBuilder:
                                            (ctx, error, stackTrace) =>
                                                const Icon(Icons
                                                    .image_not_supported),
                                      )
                                    : const Icon(Icons.image, size: 40),
                              ),
                            ),
                            title: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detectionsList.isNotEmpty
                                      ? 'Calamansi (${detectionsList.length} detected)'
                                      : 'Calamansi',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,

                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  time,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color.fromARGB(255, 54, 129, 57),
                                      letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (detectionsList.isNotEmpty)
                                      const SizedBox(height: 12),
                                    if (detectionsList.isNotEmpty)
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Recommendations per sapling',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ...detectionsList.map((det) {
                                            final m = det as Map<String, dynamic>;
                                            final detLabel =
                                                (m['label'] as String?) ?? 'Calamansi';
                                            final detHealth =
                                                (m['health'] as num?)?.toDouble() ?? 0.0;
                                            final detRec =
                                                (m['recommendation'] as String?) ?? '';

                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: Container(
                                                width: double.infinity,
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: healthColor(detHealth)
                                                      .withValues(alpha: 0.06),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                      color: healthColor(detHealth)
                                                          .withValues(alpha: 0.18)),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      detLabel,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        color: healthColor(detHealth),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      detRec.isNotEmpty
                                                          ? detRec
                                                          : 'No recommendation available.',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }),
                                        ],
                                      )
                                    else if (recommendation.isEmpty)
                                      const Text(
                                        'No recommendation available.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey),
                                      )
                                    else
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Recommendation',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight:
                                                    FontWeight.bold),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            recommendation,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}