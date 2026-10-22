// ========================= lib/profile_settings/theme_notifier.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeNotifier extends ValueNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.light) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs  = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('darkMode') ?? false;
    value = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  bool get isDark => value == ThemeMode.dark;

  Future<void> toggleTheme() async {
    final prefs   = await SharedPreferences.getInstance();
    final nowDark = !isDark;
    value = nowDark ? ThemeMode.dark : ThemeMode.light;
    await prefs.setBool('darkMode', nowDark);
  }
}

final themeNotifier = ThemeNotifier();