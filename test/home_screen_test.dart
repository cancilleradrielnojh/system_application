// Widget tests: Home dashboard + bottom navigation  -> TC-HM-01 .. 09
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/home.dart';
import 'package:system_application/profile_settings/name_notifier.dart';
import 'package:system_application/scanner.dart';
import 'package:system_application/theme/app_widgets.dart';

import 'helpers/test_harness.dart';

void main() {
  configureWidgetTestEnvironment();
  final db = FakeSqflite();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    nameNotifier.value = '';
    db.rows.clear();
    db.install();
  });
  tearDown(db.uninstall);

  Future<void> openHome(WidgetTester tester, {String name = 'JUAN'}) async {
    await pumpScreen(tester, Home(name: name));
    await settle(tester);
  }

  Finder navTab(String label) => find.descendant(
      of: find.byType(FuturisticNavBar), matching: find.text(label));

  testWidgets('TC-HM-01 shows greeting with the user name, brand and CTA',
      (tester) async {
    await openHome(tester);

    expect(find.textContaining(RegExp(r'Good (morning|afternoon|evening), JUAN')),
        findsOneWidget);
    expect(find.text('Q-LAMANSI'), findsOneWidget);
    expect(find.text('START SCAN'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('ALL TIME'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-HM-02 empty database shows zero counters and empty state',
      (tester) async {
    await openHome(tester);

    expect(find.text('No scans yet'), findsOneWidget);
    expect(find.text('Frame a leaf and start your first scan'), findsOneWidget);
    expect(find.text('See all'), findsNothing);
    expect(find.text('0'), findsNWidgets(2)); // Today + All time
    await disposeTree(tester);
  });

  testWidgets('TC-HM-03 counters reflect today vs all-time scans',
      (tester) async {
    final now = DateTime.now();
    db.rows.addAll([
      fakeScanRow(id: 1, time: now),
      fakeScanRow(id: 2, time: now.subtract(const Duration(minutes: 5))),
      for (var i = 3; i <= 5; i++)
        fakeScanRow(id: i, time: now.subtract(Duration(days: i + 3))),
    ]);
    await openHome(tester);

    expect(find.text('2'), findsOneWidget); // today
    expect(find.text('5'), findsOneWidget); // all time
    await disposeTree(tester);
  });

  testWidgets('TC-HM-04 recent scans list is capped at 3 and shows details',
      (tester) async {
    final now = DateTime.now();
    for (var i = 1; i <= 5; i++) {
      db.rows.add(fakeScanRow(
        id: i,
        label: i == 1 ? 'Pest-Damaged' : 'Healthy',
        time: now.subtract(Duration(minutes: i)),
        detections: i == 2
            ? [
                {'number': 1, 'label': 'Healthy', 'health': 95.0},
                {'number': 2, 'label': 'Healthy', 'health': 93.0},
              ]
            : null,
      ));
    }
    await openHome(tester);

    expect(find.textContaining('Calamansi ·'), findsNWidgets(3));
    expect(find.text('Calamansi · 2 saplings'), findsOneWidget); // plural
    expect(find.text('Calamansi · 1 sapling'), findsNWidgets(2)); // singular
    expect(find.text('Pest-Damaged'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-HM-05 "See all" switches to the History tab', (tester) async {
    db.rows.add(fakeScanRow(id: 1));
    await openHome(tester);

    await tester.tap(find.text('See all'));
    await settle(tester);

    expect(find.text('Scan History'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-HM-06 bottom navigation opens History, Statistics, Settings',
      (tester) async {
    await openHome(tester);

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
    await disposeTree(tester);
  });

  testWidgets('TC-HM-07 START SCAN opens the scanner; back returns to Home',
      (tester) async {
    await openHome(tester);

    await tester.tap(find.text('START SCAN'));
    await settle(tester);
    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(find.text('SCAN FRAME'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle(tester);
    expect(find.byType(ScannerScreen), findsNothing);
    expect(find.text('START SCAN'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-HM-08 greeting updates when nameNotifier changes',
      (tester) async {
    await openHome(tester);

    nameNotifier.value = 'MARIA';
    await tester.pump();

    expect(find.textContaining(', MARIA'), findsOneWidget);
    expect(find.textContaining(', JUAN'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-HM-09 saved username overrides the constructor name',
      (tester) async {
    SharedPreferences.setMockInitialValues({'username': 'PEDRO'});
    await openHome(tester, name: 'JUAN');

    expect(find.textContaining(', PEDRO'), findsOneWidget);
    await disposeTree(tester);
  });
}