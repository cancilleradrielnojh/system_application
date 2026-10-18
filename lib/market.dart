// ========================= lib/market.dart =========================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/database_service.dart';
import 'theme/app_theme.dart';

enum _DateFilter { allTime, today, last7, last30, custom }

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  int ready       = 0;
  int yellowing   = 0;
  int pestDamaged = 0;
  int wilting     = 0;
  int total       = 0;
  int totalScans  = 0;

  // Last scan summary
  String _lastLabel      = '';
  String _lastTime       = '';
  int    _lastDetections = 0;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  // ── Date filter ───────────────────────────────────────────────────────
  _DateFilter _filter = _DateFilter.allTime;
  DateTimeRange? _customRange;
  List<Map<String, dynamic>> _allScans = [];

  /// Active range (inclusive, whole days) or null for "All time".
  DateTimeRange? get _activeRange {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_filter) {
      case _DateFilter.allTime:
        return null;
      case _DateFilter.today:
        return DateTimeRange(start: today, end: today);
      case _DateFilter.last7:
        return DateTimeRange(
            start: today.subtract(const Duration(days: 6)), end: today);
      case _DateFilter.last30:
        return DateTimeRange(
            start: today.subtract(const Duration(days: 29)), end: today);
      case _DateFilter.custom:
        return _customRange;
    }
  }

  bool _inRange(Map<String, dynamic> scan, DateTimeRange? range) {
    if (range == null) return true;
    final dt = DateTime.tryParse(scan['time'] as String? ?? '');
    if (dt == null) return false;
    final day = DateTime(dt.year, dt.month, dt.day);
    return !day.isBefore(range.start) && !day.isAfter(range.end);
  }

  String _fmtDay(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  String get _rangeLabel {
    final r = _activeRange;
    if (r == null) return 'All time';
    if (r.start == r.end) return _fmtDay(r.start);
    return '${_fmtDay(r.start)} – ${_fmtDay(r.end)}';
  }

  Future<void> _pickCustomRange() async {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Earliest scan date bounds the calendar so users can't pick empty years.
    DateTime first = DateTime(today.year - 2);
    for (final s in _allScans) {
      final dt = DateTime.tryParse(s['time'] as String? ?? '');
      if (dt != null && dt.isBefore(first)) {
        first = DateTime(dt.year, dt.month, dt.day);
      }
    }

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: today,
      initialDateRange: _customRange,
      helpText: 'Filter statistics by date',
      saveText: 'Apply',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _filter      = _DateFilter.custom;
      _customRange = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end:   DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
    });
    _applyFilter();
  }

  void _selectFilter(_DateFilter f) {
    if (f == _DateFilter.custom) {
      _pickCustomRange();
      return;
    }
    setState(() => _filter = f);
    _applyFilter();
  }

  Future<void> loadData() async {
    // ── SQLite: read all scans ─────────────────────────────────────────────
    _allScans = await DatabaseService.getAllScans();
    _applyFilter();
  }

  void _applyFilter() {
    final range = _activeRange;
    final data  = _allScans.where((s) => _inRange(s, range)).toList();

    int r = 0, y = 0, po = 0, w = 0, totalDetections = 0;

    for (final decoded in data) {
      final detections = decoded['detections'];

      if (detections is List && detections.isNotEmpty) {
        for (final det in detections) {
          if (det is! Map) continue;
          totalDetections++;
          final label = (det['label'] as String? ?? '').toLowerCase();
          if (label.contains('healthy')) {
            r++;
          } else if (label.contains('yellow')) {
            y++;
          } else if (label.contains('pest')) {
            po++;
          } else if (label.contains('wilt')) {
            w++;
          } else {
            final healthVal = det['health'];
            if (healthVal is num) {
              final health = healthVal.toDouble();
              if (health >= 90)      { r++;  }
              else if (health >= 70) { y++;  }
              else if (health >= 55) { w++;  }
              else                   { po++; }
            }
          }
        }
      } else {
        final label = (decoded['label'] as String? ?? '').toLowerCase();
        totalDetections++;
        if (label.contains('healthy')) {
          r++;
        } else if (label.contains('yellow')) {
          y++;
        } else if (label.contains('pest')) {
          po++;
        } else if (label.contains('wilt')) {
          w++;
        } else {
          final healthVal = decoded['health'];
          if (healthVal is num) {
            final health = healthVal.toDouble();
            if (health >= 90)      { r++;  }
            else if (health >= 70) { y++;  }
            else if (health >= 55) { w++;  }
            else                   { po++; }
          }
        }
      }
    }

    // Last scan info — getAllScans returns newest-first so first element is last
    String lastLabel = '';
    String lastTime  = '';
    int    lastCount = 0;
    if (data.isNotEmpty) {
      final last = data.first;
      lastLabel = last['label'] as String? ?? '';
      lastTime  = last['time']  as String? ?? '';
      lastCount = (last['detections'] as List?)?.length ?? 0;
    }

    if (!mounted) return;
    setState(() {
      ready           = r;
      yellowing       = y;
      pestDamaged     = po;
      wilting         = w;
      total           = totalDetections;
      totalScans      = data.length;
      _lastLabel      = lastLabel;
      _lastTime       = lastTime;
      _lastDetections = lastCount;
    });
  }

  // ── Helpers ─────────────────────────────────────────────────────
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
      return '${months[dt.month]} ${dt.day}, ${dt.year} · $h:$m $ampm';
    } catch (_) {
      return raw;
    }
  }

  Color _labelColor(String label) => AppTheme.healthColor(label);

  Widget _buildDateFilter(bool isDark) {
    const options = <_DateFilter, String>{
      _DateFilter.allTime: 'All time',
      _DateFilter.today:   'Today',
      _DateFilter.last7:   '7 days',
      _DateFilter.last30:  '30 days',
      _DateFilter.custom:  'Pick dates',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: options.entries.map((e) {
              final selected = _filter == e.key;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: e.key == _DateFilter.custom
                      ? Icon(Icons.calendar_month_rounded,
                          size: 16,
                          color: selected ? AppColors.ink : null)
                      : null,
                  label: Text(e.value),
                  selected: selected,
                  showCheckmark: false,
                  selectedColor: AppColors.lime,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.ink : null,
                  ),
                  onSelected: (_) => _selectFilter(e.key),
                ),
              );
            }).toList(),
          ),
        ),
        if (_filter != _DateFilter.allTime) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.event_rounded, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Showing: $_rangeLabel',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ),
              GestureDetector(
                onTap: () => _selectFilter(_DateFilter.allTime),
                child: Text('Clear',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.lime : AppColors.tealDeep)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Page title ───────────────────────────────────────
            Text('Calamansi Sapling Insights',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
            const SizedBox(height: 4),
            Text(
              totalScans == 0
                  ? (_filter == _DateFilter.allTime
                      ? 'No scans recorded yet'
                      : 'No scans in this date range')
                  : '$totalScans scan image${totalScans == 1 ? '' : 's'} · $total sapling${total == 1 ? '' : 's'} detected',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),

            const SizedBox(height: 16),

            // ── Date filter ──────────────────────────────────────
            _buildDateFilter(isDark),

            const SizedBox(height: 20),

            // ── Overall health banner ────────────────────────────
            if (total > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? const [Color(0xFF16352C), Color(0xFF0E1A16)]
                        : const [AppColors.ink, Color(0xFF16352C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.lime.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.eco_rounded,
                        color: AppColors.lime, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Overall Healthy Saplings',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          Text(
                            '${(ready / total * 100).round()}% Healthy',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$ready of $total saplings in good condition',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // ── Sapling Status ───────────────────────────────────
            const Text('Sapling Status',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(child: _StatCard(
                  count: ready,
                  label: 'Healthy',
                  icon: Icons.spa_rounded,
                  color: AppColors.healthy,
                  bgColor: isDark ? const Color(0xFF1B3A1E) : const Color(0xFFE8F5EE),
                )),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  count: yellowing,
                  label: 'Yellowing',
                  icon: Icons.wb_sunny_rounded,
                  color: AppColors.warn,
                  bgColor: isDark ? const Color(0xFF3A2A0A) : const Color(0xFFFBF3E0),
                )),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _StatCard(
                  count: pestDamaged,
                  label: 'Pest-Damaged',
                  icon: Icons.bug_report_rounded,
                  color: AppColors.danger,
                  bgColor: isDark ? const Color(0xFF3A1212) : const Color(0xFFFBECEA),
                )),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  count: wilting,
                  label: 'Wilting',
                  icon: Icons.water_drop_rounded,
                  color: AppColors.wilt,
                  bgColor: isDark ? const Color(0xFF3A2412) : const Color(0xFFF8EEE4),
                )),
              ],
            ),
            const SizedBox(height: 12),
            _StatCard(
              count: totalScans,
              label: 'Total Scan Images',
              icon: Icons.bar_chart_rounded,
              color: Colors.blueGrey,
              bgColor: isDark ? const Color(0xFF1A2530) : Colors.blueGrey.shade50,
              fullWidth: true,
            ),

            const SizedBox(height: 28),

            // ── Health Breakdown ─────────────────────────────────
            if (total > 0) ...[
              const Text('Health Breakdown',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              _BreakdownBar(
                  ready: ready,
                  yellowing: yellowing,
                  pestDamaged: pestDamaged,
                  wilting: wilting,
                  total: total),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  _Legend(color: AppColors.healthy, label: 'Healthy',      count: ready),
                  _Legend(color: AppColors.warn,    label: 'Yellowing',    count: yellowing),
                  _Legend(color: AppColors.danger,  label: 'Pest-Damaged', count: pestDamaged),
                  _Legend(color: AppColors.wilt,    label: 'Wilting',      count: wilting),
                ],
              ),
              const SizedBox(height: 28),
            ],

            // ── Last Scan ────────────────────────────────────────
            const Text('Last Scan',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            total == 0
                ? Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                          _filter == _DateFilter.allTime
                              ? 'No data yet — start scanning!'
                              : 'No scans found for this period.',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.surfaceContainerHighest
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2)),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              _labelColor(_lastLabel).withValues(alpha: 0.15),
                          child: Icon(Icons.eco_rounded,
                              color: _labelColor(_lastLabel)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_lastDetections sapling${_lastDetections == 1 ? '' : 's'} detected',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14),
                              ),
                              if (_lastTime.isNotEmpty)
                                Text(
                                  _formatTime(_lastTime),
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                            ],
                          ),
                        ),
                        if (_lastLabel.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _labelColor(_lastLabel)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: _labelColor(_lastLabel)
                                      .withValues(alpha: 0.35)),
                            ),
                            child: Text(
                              _lastLabel,
                              style: TextStyle(
                                  color: _labelColor(_lastLabel),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
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

// ── _StatCard ─────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final int count;
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final bool fullWidth;

  const _StatCard({
    required this.count,
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: color.withValues(alpha: 0.85))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── _BreakdownBar ─────────────────────────────────────────────────
class _BreakdownBar extends StatelessWidget {
  final int ready, yellowing, pestDamaged, wilting, total;
  const _BreakdownBar({
      required this.ready,
      required this.yellowing,
      required this.pestDamaged,
      required this.wilting,
      required this.total});

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const SizedBox();

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            if (ready > 0)
              Expanded(
                flex: ready,
                child: Container(
                  color: AppColors.healthy,
                  alignment: Alignment.center,
                  child: ready * 100 ~/ total >= 10
                      ? Text(
                          '${(ready / total * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              ),
            if (yellowing > 0)
              Expanded(
                flex: yellowing,
                child: Container(
                  color: AppColors.warn,
                  alignment: Alignment.center,
                  child: yellowing * 100 ~/ total >= 10
                      ? Text(
                          '${(yellowing / total * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              ),
            if (pestDamaged > 0)
              Expanded(
                flex: pestDamaged,
                child: Container(
                  color: AppColors.danger,
                  alignment: Alignment.center,
                  child: pestDamaged * 100 ~/ total >= 10
                      ? Text(
                          '${(pestDamaged / total * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              ),
            if (wilting > 0)
              Expanded(
                flex: wilting,
                child: Container(
                  color: AppColors.wilt,
                  alignment: Alignment.center,
                  child: wilting * 100 ~/ total >= 10
                      ? Text(
                          '${(wilting / total * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── _Legend ───────────────────────────────────────────────────────
class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final int count;
  const _Legend({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text('$label ($count)',
            style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}