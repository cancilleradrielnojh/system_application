// Shared helpers for the widget tests.
//
// - Replaces the sqflite plugin channel with an in-memory fake so screens that
//   call DatabaseService (Home, History, Statistics, Settings) run under
//   `flutter test` without a device.
// - Disables google_fonts runtime fetching (no network in tests).
// - Provides pumpScreen() which hosts a widget in a phone-sized MaterialApp
//   using the app's real AppTheme.
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:system_application/theme/app_theme.dart';

/// Call once at the top of every widget test file's `main()`.
void configureWidgetTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
}

/// Builds a row exactly as the `scans` table would return it.
Map<String, Object?> fakeScanRow({
  required int id,
  String label = 'Healthy',
  DateTime? time,
  List<Map<String, Object?>>? detections,
  String image = '',
  double health = 95,
  double confidence = 0.9,
}) {
  final dets = detections ??
      [
        {
          'number': 1,
          'label': label,
          'health': health,
          'confidence': confidence,
          'boxAreaPx': 1000.0,
          'recommendation': 'Keep watering.',
          'outline': null,
        }
      ];
  return {
    'id': id,
    'image': image,
    'label': label,
    'health': health,
    'confidence': confidence,
    'box_area_px': 1000.0,
    'recommendation': 'Keep watering.',
    'detections': jsonEncode(dets),
    'time': (time ?? DateTime.now()).toString(),
  };
}

/// In-memory stand-in for the sqflite native side (channel
/// `com.tekartik.sqflite`). Only the calls DatabaseService makes are handled.
class FakeSqflite {
  static const MethodChannel _channel = MethodChannel('com.tekartik.sqflite');

  final List<Map<String, Object?>> rows = [];
  final List<String> sqlLog = [];

  /// Every call the plugin channel received (method + arguments), for
  /// white-box assertions on the SQL DatabaseService actually sends.
  final List<MethodCall> calls = [];

  static bool _factoryInstalled = false;

  void install() {
    if (!_factoryInstalled) {
      databaseFactory = databaseFactorySqflitePlugin;
      _factoryInstalled = true;
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call);
    final args = (call.arguments is Map)
        ? Map<String, Object?>.from(call.arguments as Map)
        : <String, Object?>{};
    final sql = (args['sql'] as String?) ?? '';
    final sqlArgs = (args['arguments'] as List?) ?? const [];
    if (sql.isNotEmpty) sqlLog.add(sql);

    switch (call.method) {
      case 'getDatabasesPath':
        return '/fake/databases';
      case 'openDatabase':
        return 1;
      case 'closeDatabase':
      case 'execute':
        return null;
      case 'insert':
        return rows.length + 1;
      case 'update': // sqflite sends DELETE statements through this method
        if (sql.startsWith('DELETE FROM scans WHERE id')) {
          final before = rows.length;
          rows.removeWhere((r) => r['id'] == sqlArgs.first);
          return before - rows.length;
        }
        if (sql.startsWith('DELETE FROM scans')) {
          final n = rows.length;
          rows.clear();
          return n;
        }
        return 0;
      case 'query':
        if (sql.contains('user_version')) {
          // Same as DatabaseService's schema version -> onCreate is skipped.
          return [
            {'user_version': 1}
          ];
        }
        if (sql.contains('COUNT(*)')) {
          if (sql.contains('substr(time')) {
            final day = sqlArgs.first as String;
            final n = rows
                .where((r) => (r['time'] as String).substring(0, 10) == day)
                .length;
            return [
              {'cnt': n}
            ];
          }
          return [
            {'cnt': rows.length}
          ];
        }
        if (sql.contains('FROM scans')) {
          final sorted = List<Map<String, Object?>>.from(rows)
            ..sort((a, b) =>
                (b['time'] as String).compareTo(a['time'] as String));
          final m = RegExp(r'LIMIT (\d+)').firstMatch(sql);
          final limited =
              m == null ? sorted : sorted.take(int.parse(m.group(1)!)).toList();
          return limited.map((r) => Map<String, Object?>.from(r)).toList();
        }
        return <Map<String, Object?>>[];
    }
    return null;
  }
}

/// Hosts [child] in a MaterialApp on a 360x800 logical-pixel phone surface.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  GlobalKey<ScaffoldMessengerState>? messengerKey,
  double logicalWidth = 360,
}) async {
  tester.view.physicalSize = Size(logicalWidth * 3, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  // In `flutter test` google_fonts cannot load Space Grotesk / DM Sans (no
  // network, fonts not bundled), so text falls back to the test font, which
  // is much wider. That produces "RenderFlex overflowed" errors that do not
  // exist on a device. Ignore ONLY overflow reports; every other error still
  // reaches the original handler and fails the test. Real layout checks need
  // a device / golden run with the real fonts.
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed by')) return;
    originalOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalOnError);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      scaffoldMessengerKey: messengerKey,
      home: child,
    ),
  );
}

/// Advances time in small steps so futures and short animations complete
/// without pumpAndSettle (which never returns while a spinner is on screen).
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts the current tree so dispose() runs (cancels timers, observers).
Future<void> disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}