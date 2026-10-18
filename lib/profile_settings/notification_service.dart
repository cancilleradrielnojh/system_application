// ========================= lib/profile_settings/notification_service.dart =========================
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../detection/inference_service.dart';

class NotificationService {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('pushNotifications') ?? true;
  }

  static Future<void> init() async {}

  static Future<void> sendScanNotification({
    required bool success,
    required double health,
    List<DetectionResult> detections = const [],
  }) async {
    if (!await isEnabled()) return;

    String message;
    Color  color;

    if (!success) {
      message = '❌ Scan failed. Please try again.';
      color   = Colors.red;
    } else if (detections.isNotEmpty) {
      final valid = detections.where((d) => d.isCalamansi).toList();
      if (valid.isEmpty) {
        message = '⚠️ No valid calamansi detection found.';
        color = Colors.orange;
      } else {
        final counts = <String, int>{};
        for (final d in valid) {
          counts[d.className] = (counts[d.className] ?? 0) + 1;
        }
        final sorted = counts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topLabel = sorted.first.key;
       

        if (sorted.length == 1) {
          message = '✅ ${valid.length} detected — $topLabel';
        } else {
          message = '✅ ${valid.length} detected';
        }

        final lower = topLabel.toLowerCase();
        if (lower.contains('healthy')) {
          color = Colors.green;
        } else if (lower.contains('yellow')) {
          color = const Color(0xFFD4A017);
        } else if (lower.contains('wilt')) {
          color = Colors.orange;
        } else {
          color = Colors.red;
        }
      }
    } else if (health >= 90) {
      message = '✅ ${health.toStringAsFixed(1)}% — Healthy';
      color = Colors.green;
    } else if (health >= 70) {
      message = '🟡 ${health.toStringAsFixed(1)}% — Yellowing detected';
      color = const Color(0xFFD4A017);
    } else if (health >= 40) {
      message = '🥀 ${health.toStringAsFixed(1)}% — Wilting detected';
      color = Colors.orange;
    } else {
      message = '🐛 ${health.toStringAsFixed(1)}% — Pest damage detected';
      color = Colors.red;
    }

    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}