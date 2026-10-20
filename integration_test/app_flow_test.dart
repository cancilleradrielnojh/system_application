// Integration tests: app flow on a real device / emulator
//
// Runs the REAL app widgets (MyApp) with REAL SQLite, SharedPreferences and
// the REAL ONNX model loading. Nothing is mocked. The camera and the gallery
// are NOT driven here: both open OS permission / picker UI that a Flutter
// test cannot tap. Those are in docs/DEVICE_TEST_CHECKLIST.md (manual).
//
//   IT-FL-01  first launch shows the verification screen
//   IT-FL-02  name validation, saved name, opens Home
//   IT-FL-03  returning user goes straight to Home
//   IT-FL-04  bottom navigation reaches every tab
//   IT-FL-05  one saved scan is consistent on Home, History and Statistics
//   IT-FL-06  "Clear all" in History empties every screen
//   (theme toggle is in theme_toggle_test.dart, see the note there)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/data/database_service.dart';
import 'package:system_application/detection/inference_service.dart';
import 'package:system_application/home.dart';
import 'package:system_application/main.dart' show MyApp;
import 'package:system_application/profile_settings/name_notifier.dart';
import 'package:system_application/theme/app_widgets.dart';
import 'package:system_application/user_verification.dart';

/// Pumps in 100 ms steps until [finder] matches (spinners never "settle", so
/// pumpAndSettle would time out).
Future<void> pumpUntil(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets, reason: 'not found within $timeout');
}

Future<void> settle(WidgetTester tester, [int frames = 10]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> launchApp(WidgetTester tester) async {
  // Unmount first so MyApp.initState (loadUser) runs again for every test.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(const MyApp());
}

Finder navTab(String label) => find.descendant(
    of: find.byType(FuturisticNavBar), matching: find.text(label));

Map<String, Object?> _scan({
  required String label,
  required double health,
}) =>
    {
      'image': '',
      'label': label,
      'health': health,
      'confidence': 0.9,
      'boxAreaPx': 1000.0,
      'recommendation': 'Keep watering.',
      'detections': [
        {
          'number': 1,
          'label': label,
          'health': health,
          'confidence': 0.9,
          'boxAreaPx': 1000.0,
          'recommendation': 'Keep watering.',
          'outline': null,
        }
      ],
      'time': DateTime.now().toString(),
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Same call main() makes. A failure here means the .onnx assets are
    // missing from the build or the runtime cannot create a session.
    await inferenceService.loadModel();
  });

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    nameNotifier.value = '';
    await DatabaseService.deleteAllScans();
  });

  tearDown(() async {
    // Leave the device clean for the next run.
    await DatabaseService.deleteAllScans();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  testWidgets('IT-FL-00 both models loaded before the UI starts',
      (tester) async {
    expect(inferenceService.isLoaded, isTrue);
  });

  testWidgets('IT-FL-01 first launch shows the verification screen',
      (tester) async {
    await launchApp(tester);
    await pumpUntil(tester, find.byType(UserVerification));

    expect(find.text('Q-LAMANSI'), findsOneWidget);
    expect(find.text('IDENTIFY YOURSELF'), findsOneWidget);
    expect(find.byType(Home), findsNothing);
  });

  testWidgets('IT-FL-02 empty name rejected; valid name saved and opens Home',
      (tester) async {
    await launchApp(tester);
    await pumpUntil(tester, find.byType(UserVerification));
    await settle(tester);

    await tester.tap(find.text('Enter workspace'));
    await settle(tester);
    expect(find.byType(Home), findsNothing);
    expect((await SharedPreferences.getInstance()).getString('username'),
        isNull);

    await tester.enterText(find.byType(TextField), '  Juan  ');
    await tester.tap(find.text('Enter workspace'));
    await pumpUntil(tester, find.byType(Home));

    expect((await SharedPreferences.getInstance()).getString('username'),
        'Juan');
    expect(find.text('START SCAN'), findsOneWidget);
  });

  testWidgets('IT-FL-03 returning user goes straight to Home', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', 'Maria');

    await launchApp(tester);
    await pumpUntil(tester, find.byType(Home));

    expect(find.byType(UserVerification), findsNothing);
    expect(
        find.textContaining(
            RegExp(r'Good (morning|afternoon|evening), maria',
                caseSensitive: false)),
        findsOneWidget);
  });

  testWidgets('IT-FL-04 bottom navigation reaches every tab', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', 'Juan');
    await launchApp(tester);
    await pumpUntil(tester, find.byType(Home));
    await settle(tester);

    await tester.tap(navTab('History'));
    await settle(tester);
    expect(find.text('Scan History'), findsOneWidget);

    await tester.tap(navTab('Statistics'));
    await settle(tester);
    expect(find.text('Calamansi Sapling Insights'), findsOneWidget);

    await tester.tap(navTab('Settings'));
    await settle(tester);
    expect(find.text('PREFERENCES'), findsOneWidget);

    await tester.tap(navTab('Home'));
    await settle(tester);
    expect(find.text('START SCAN'), findsOneWidget);
  });

  testWidgets('IT-FL-05 one saved scan is consistent on Home, History, Stats',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', 'Juan');
    // Real SQLite write, exactly what Home.saveScan does at the end.
    await DatabaseService.insertScan(_scan(label: 'Healthy', health: 95));

    await launchApp(tester);
    await pumpUntil(tester, find.byType(Home));
    await settle(tester);

    // Home: recent scans list
    expect(find.text('Calamansi · 1 sapling'), findsOneWidget);
    expect(find.text('No scans yet'), findsNothing);

    // History
    await tester.tap(navTab('History'));
    await settle(tester);
    expect(find.text('1 scan recorded'), findsOneWidget);

    // Statistics
    await tester.tap(navTab('Statistics'));
    await settle(tester);
    expect(find.text('1 scan image · 1 sapling detected'), findsOneWidget);
    expect(find.text('100% Healthy'), findsOneWidget);
  });

  testWidgets('IT-FL-06 History "Clear all" empties Home, History and Stats',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', 'Juan');
    await DatabaseService.insertScan(_scan(label: 'Healthy', health: 95));
    await DatabaseService.insertScan(_scan(label: 'Wilting', health: 50));

    await launchApp(tester);
    await pumpUntil(tester, find.byType(Home));
    await settle(tester);

    await tester.tap(navTab('History'));
    await settle(tester);
    expect(find.text('2 scans recorded'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await settle(tester);
    expect(find.text('Clear all history?'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Clear all')));
    await settle(tester);

    expect(find.text('No history yet'), findsOneWidget);
    expect(await DatabaseService.countAll(), 0);

    await tester.tap(navTab('Statistics'));
    await settle(tester);
    expect(find.text('No scans recorded yet'), findsOneWidget);

    await tester.tap(navTab('Home'));
    await settle(tester);
    expect(find.text('No scans yet'), findsOneWidget);
  });
}