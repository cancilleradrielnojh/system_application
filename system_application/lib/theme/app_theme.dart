// ========================= lib/theme/app_theme.dart =========================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Q-Lamansi visual language: citrus-lab tech — ink + lime, simple, human.
class AppColors {
  static const ink = Color(0xFF0B1F1A);
  static const inkSoft = Color(0xFF1A332C);
  static const mist = Color(0xFFEEF5F1);
  static const mistDeep = Color(0xFFE0EBE5);
  static const surface = Color(0xFFF7FBF8);
  static const lime = Color(0xFFC8F542);
  static const limeDeep = Color(0xFF9BCF2E);
  static const teal = Color(0xFF1FA89A);
  static const tealDeep = Color(0xFF147A70);
  static const steel = Color(0xFF5A7268);
  static const line = Color(0xFFD5E3DC);
  static const danger = Color(0xFFE85D4C);
  static const warn = Color(0xFFE8A838);
  static const wilt = Color(0xFFD4783A);
  static const healthy = Color(0xFF2E9B6A);

  // Dark
  static const darkBg = Color(0xFF050D0B);
  static const darkSurface = Color(0xFF0E1A16);
  static const darkCard = Color(0xFF142420);
  static const darkLine = Color(0xFF243832);
  static const darkText = Color(0xFFE8F2EE);
  static const darkMuted = Color(0xFF8AA399);
}

class AppTheme {
  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? AppColors.darkText
        : AppColors.ink;
    final muted = brightness == Brightness.dark
        ? AppColors.darkMuted
        : AppColors.steel;

    final display = GoogleFonts.spaceGroteskTextTheme();
    final body = GoogleFonts.dmSansTextTheme();

    return body.copyWith(
      displayLarge: display.displayLarge?.copyWith(
        color: base,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
      ),
      displayMedium: display.displayMedium?.copyWith(
        color: base,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        color: base,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        color: base,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      headlineSmall: display.headlineSmall?.copyWith(
        color: base,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: display.titleLarge?.copyWith(
        color: base,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: body.titleMedium?.copyWith(
        color: base,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: body.titleSmall?.copyWith(
        color: muted,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
      bodyLarge: body.bodyLarge?.copyWith(color: base, height: 1.45),
      bodyMedium: body.bodyMedium?.copyWith(color: base, height: 1.45),
      bodySmall: body.bodySmall?.copyWith(color: muted, height: 1.4),
      labelLarge: body.labelLarge?.copyWith(
        color: base,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      labelMedium: body.labelMedium?.copyWith(
        color: muted,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.6,
      ),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.light(
      primary: AppColors.tealDeep,
      onPrimary: Colors.white,
      secondary: AppColors.limeDeep,
      onSecondary: AppColors.ink,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
      outline: AppColors.line,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.mist,
      textTheme: _textTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      dividerColor: AppColors.line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.teal, width: 1.6),
        ),
        labelStyle: GoogleFonts.dmSans(color: AppColors.steel),
        hintStyle: GoogleFonts.dmSans(color: AppColors.steel.withValues(alpha: 0.7)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.lime,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          minimumSize: const Size(double.infinity, 54),
          side: const BorderSide(color: AppColors.ink, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.ink,
        unselectedItemColor: AppColors.steel,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 11),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: AppColors.lime,
      onPrimary: AppColors.ink,
      secondary: AppColors.teal,
      onSecondary: Colors.white,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      error: AppColors.danger,
      outline: AppColors.darkLine,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkBg,
      textTheme: _textTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.darkText,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.darkText,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.darkLine),
        ),
      ),
      dividerColor: AppColors.darkLine,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.lime, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lime,
          foregroundColor: AppColors.ink,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkText,
          minimumSize: const Size(double.infinity, 54),
          side: BorderSide(
            color: AppColors.darkText.withValues(alpha: 0.45),
            width: 1.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: AppColors.lime,
        unselectedItemColor: AppColors.darkMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  static Color healthColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('healthy')) return AppColors.healthy;
    if (l.contains('yellow')) return AppColors.warn;
    if (l.contains('wilt')) return AppColors.wilt;
    if (l.contains('pest')) return AppColors.danger;
    return AppColors.steel;
  }
}
