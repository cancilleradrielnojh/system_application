// Widget tests: HistoryPage  -> TC-HI-01 .. 08
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/history.dart';
import 'package:system_application/theme/app_theme.dart';

import 'helpers/test_harness.dart';

void main() {
  configureWidgetTestEnvironment();
  final db = FakeSqflite();
  var changedCalls = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db.rows.clear();
    changedCalls = 0;
    db.install();
  });
  tearDown(db.uninstall);

  Future<void> openHistory(WidgetTester tester,
      {double logicalWidth = 360}) async {
    await pumpScreen(
      tester,
      Scaffold(body: HistoryPage(onHistoryChanged: () => changedCalls++)),
      logicalWidth: logicalWidth,
    );
    await settle(tester);
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  testWidgets('TC-HI-01 empty history shows the empty state only',
      (tester) async {
    await openHistory(tester);

    expect(find.text('Scan History'), findsOneWidget);
    expect(find.text('0 scans recorded'), findsOneWidget);
    expect(find.text('No history yet'), findsOneWidget);
    expect(find.text('Your scan records will appear here'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-HI-02 scans are grouped under Today / Yesterday headers',
      (tester) async {
    final now = DateTime.now();
    db.rows.addAll([
      fakeScanRow(id: 1, time: now),
      fakeScanRow(id: 2, time: now.subtract(const Duration(seconds: 30))),
      fakeScanRow(id: 3, time: now.subtract(const Duration(days: 1))),
    ]);
    await openHistory(tester);

    expect(find.text('3 scans recorded'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.textContaining('Calamansi · 1 detected'), findsNWidgets(3));
    expect(find.text('Clear all'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-HI-03 singular wording for exactly one scan',
      (tester) async {
    db.rows.add(fakeScanRow(id: 1));
    await openHistory(tester);

    expect(find.text('1 scan recorded'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-HI-04 health label badge color follows the class mapping',
      (tester) async {
    final now = DateTime.now();
    final expected = <String, Color>{
      'Healthy': AppColors.healthy,
      'Yellowing': AppColors.warn,
      'Wilting': AppColors.wilt,
      'Pest-Damaged': AppColors.danger,
    };
    var id = 1;
    for (final label in expected.keys) {
      db.rows.add(fakeScanRow(
          id: id, label: label, time: now.subtract(Duration(seconds: id))));
      id++;
    }
    await openHistory(tester);

    expected.forEach((label, color) {
      final badge = tester.widget<Text>(find.text(label).first);
      expect(badge.style?.color, color, reason: 'badge for $label');
    });
    await disposeTree(tester);
  });

  testWidgets('TC-HI-05 expanding a card lists per-sapling recommendations',
      (tester) async {
    db.rows.add(fakeScanRow(
      id: 1,
      label: 'Yellowing',
      detections: [
        {
          'number': 1,
          'label': 'Yellowing',
          'health': 70.0,
          'confidence': 0.82,
          'recommendation': 'Apply mild nitrogen feed.'
        },
        {
          'number': 2,
          'label': 'Healthy',
          'health': 95.0,
          'confidence': 0.91,
          'recommendation': 'Keep watering.'
        },
      ],
    ));
    await openHistory(tester);
    expect(find.text('Recommendations per sapling'), findsNothing);

    await tester.tap(find.byType(ExpansionTile));
    await settle(tester);

    expect(find.text('Recommendations per sapling'), findsOneWidget);
    expect(find.text('Apply mild nitrogen feed.'), findsOneWidget);
    expect(find.text('Keep watering.'), findsOneWidget);
    expect(find.textContaining('82% confidence'), findsOneWidget);
    expect(find.textContaining('#1'), findsOneWidget);
    expect(find.textContaining('#2'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-HI-06 swipe-to-delete asks first; Cancel keeps the scan',
      (tester) async {
    db.rows.add(fakeScanRow(id: 1));
    await openHistory(tester);

    await tester.drag(find.byKey(const ValueKey('scan_1')), const Offset(-500, 0));
    await settle(tester);
    expect(find.text('Delete scan?'), findsOneWidget);

    await tester.tap(inDialog('Cancel'));
    await settle(tester);

    expect(find.byKey(const ValueKey('scan_1')), findsOneWidget);
    expect(find.text('1 scan recorded'), findsOneWidget);
    expect(db.rows.length, 1);
    expect(changedCalls, 0);
    await disposeTree(tester);
  });

  testWidgets('TC-HI-07 confirming delete removes the scan and notifies parent',
      (tester) async {
    db.rows.addAll([fakeScanRow(id: 1), fakeScanRow(id: 2)]);
    await openHistory(tester);
    expect(find.text('2 scans recorded'), findsOneWidget);

    await tester.drag(find.byKey(const ValueKey('scan_1')), const Offset(-500, 0));
    await settle(tester);
    await tester.tap(inDialog('Delete'));
    await settle(tester, frames: 12);

    expect(find.byKey(const ValueKey('scan_1')), findsNothing);
    expect(find.text('1 scan recorded'), findsOneWidget);
    expect(db.rows.map((r) => r['id']), [2]);
    expect(changedCalls, 1);
    await disposeTree(tester);
  });

  testWidgets('TC-HI-08 "Clear all": Cancel keeps data, confirm wipes it',
      (tester) async {
    db.rows.addAll([fakeScanRow(id: 1), fakeScanRow(id: 2)]);
    // Wider surface: the fallback test font makes the header row wider than
    // 360 px, which pushes "Clear all" off-screen where taps cannot reach it.
    await openHistory(tester, logicalWidth: 700);

    await tester.tap(find.text('Clear all'));
    await settle(tester);
    expect(find.text('Clear all history?'), findsOneWidget);
    await tester.tap(inDialog('Cancel'));
    await settle(tester);
    expect(find.text('2 scans recorded'), findsOneWidget);
    expect(db.rows.length, 2);

    await tester.tap(find.text('Clear all'));
    await settle(tester);
    await tester.tap(inDialog('Clear all'));
    await settle(tester);

    expect(find.text('No history yet'), findsOneWidget);
    expect(find.text('0 scans recorded'), findsOneWidget);
    expect(db.rows, isEmpty);
    expect(changedCalls, 1);
    await disposeTree(tester);
  });
}