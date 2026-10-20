// Integration test: theme toggle on the live app   -> IT-TH-01
//
// Kept in its own file ON PURPOSE. MyApp (lib/main.dart) adds a listener to
// the global themeNotifier in initState and never removes it (finding F-03).
// If earlier tests in the same run had mounted and disposed MyApp, toggling
// the theme here would call setState on those disposed states and fail for a
// reason unrelated to this feature. Each integration_test file runs in its
// own app process, so this file starts with exactly one MyApp.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/detection/inference_service.dart';
import 'package:system_application/home.dart';
import 'package:system_application/main.dart' show MyApp;
import 'package:system_application/profile_settings/theme_notifier.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('IT-TH-01 toggle updates the live MaterialApp and is persisted',
      (tester) async {
    await inferenceService.loadModel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('username', 'Juan');

    await tester.pumpWidget(const MyApp());
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (find.byType(Home).evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Home), findsOneWidget);

    final startedDark = themeNotifier.isDark;
    await themeNotifier.toggleTheme();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(themeNotifier.isDark, !startedDark);
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        startedDark ? ThemeMode.light : ThemeMode.dark);
    expect((await SharedPreferences.getInstance()).getBool('darkMode'),
        !startedDark);

    // restore the original theme and persisted value
    await themeNotifier.toggleTheme();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(themeNotifier.isDark, startedDark);
    await prefs.clear();
  });
}