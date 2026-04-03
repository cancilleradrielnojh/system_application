// ========================= lib/history.dart =========================
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'data/database_service.dart';

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
  Color _healthColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('healthy')) return Colors.green;
    if (l.contains('yellow'))  return Colors.orange;
    if (l.contains('wilt'))    return const Color(0xFF7B5EA7);
    if (l.contains('pest'))    return Colors.red;
    return Colors.grey;
  }

  Color _healthColorFromScore(double health) {
    if (health >= 90) return Colors.green;
    if (health >= 60) return Colors.orange;
    if (health >= 40) return const Color(0xFF7B5EA7);
    return Colors.red;
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
                const Text('Scan History',
                    style: TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
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
          leading: ClipRRect(
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
              style: const TextStyle(
                  fontSize: 11,
                  color: Color.fromARGB(255, 54, 129, 57),
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
                                    'Sapling ${i + 1} — $dLabel',
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