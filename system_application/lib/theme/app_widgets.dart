// ========================= lib/theme/app_widgets.dart =========================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

class AppBackdrop extends StatelessWidget {
  final Widget child;
  const AppBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [
                      Color(0xFF050D0B),
                      Color(0xFF0A1814),
                      Color(0xFF071210),
                    ]
                  : const [
                      Color(0xFFF4FAF6),
                      Color(0xFFE8F3EE),
                      Color(0xFFF0F7F3),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -80,
          right: -60,
          child: _Blob(
            size: 220,
            color: (isDark ? AppColors.lime : AppColors.teal)
                .withValues(alpha: isDark ? 0.08 : 0.10),
          ),
        ),
        Positioned(
          bottom: 80,
          left: -70,
          child: _Blob(
            size: 180,
            color: (isDark ? AppColors.teal : AppColors.limeDeep)
                .withValues(alpha: isDark ? 0.10 : 0.12),
          ),
        ),
        child,
      ],
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? AppColors.lime : AppColors.ink,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.spa_rounded,
        color: isDark ? AppColors.ink : AppColors.lime,
        size: size * 0.55,
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.dmSans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkMuted
            : AppColors.steel,
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ??
            (isDark ? AppColors.darkCard.withValues(alpha: 0.92) : Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkLine : AppColors.line,
        ),
      ),
      child: child,
    );
  }
}

class LimeCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  const LimeCta({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: compact ? 52 : 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: isDark
                  ? const [AppColors.limeDeep, AppColors.lime]
                  : const [AppColors.ink, Color(0xFF16352C)],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isDark ? AppColors.ink : AppColors.lime,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  color: isDark ? AppColors.ink : AppColors.lime,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const StatusChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Corner-bracket viewfinder used on the scanner.
class ScanFramePainter extends CustomPainter {
  final Color color;
  ScanFramePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    const len = 28.0;
    final w = size.width;
    final h = size.height;

    // TL
    canvas.drawLine(const Offset(0, len), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    // TR
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, len), paint);
    // BL
    canvas.drawLine(Offset(0, h - len), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(len, h), paint);
    // BR
    canvas.drawLine(Offset(w - len, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h - len), Offset(w, h), paint);

    // Center crosshair tick
    final cx = w / 2;
    final cy = h / 2;
    final tick = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 1.4;
    canvas.drawLine(Offset(cx - 10, cy), Offset(cx + 10, cy), tick);
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy + 10), tick);
  }

  @override
  bool shouldRepaint(covariant ScanFramePainter oldDelegate) =>
      oldDelegate.color != color;
}

class FuturisticNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;

  const FuturisticNavBar({
    super.key,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = const [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (Icons.history_outlined, Icons.history_rounded, 'History'),
      (Icons.insights_outlined, Icons.insights_rounded, 'Statistics'),
      (Icons.tune_outlined, Icons.tune_rounded, 'Settings'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkLine : AppColors.line,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = index == i;
              final icon = selected ? items[i].$2 : items[i].$1;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? (isDark
                              ? AppColors.lime.withValues(alpha: 0.12)
                              : AppColors.mistDeep)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: selected
                              ? (isDark ? AppColors.lime : AppColors.ink)
                              : (isDark
                                  ? AppColors.darkMuted
                                  : AppColors.steel),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items[i].$3,
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected
                                ? (isDark ? AppColors.lime : AppColors.ink)
                                : (isDark
                                    ? AppColors.darkMuted
                                    : AppColors.steel),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
