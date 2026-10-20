// Widget tests: MarketScreen ("Statistics" tab)  -> TC-ST-01 .. 05
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/market.dart';

import 'helpers/test_harness.dart';

Map<String, Object?> _det(String label, double health) => {
      'number': 1,
      'label': label,
      'health': health,
      'confidence': 0.9,
      'recommendation': 'x',
    };

void main() {
  configureWidgetTestEnvironment();
  final db = FakeSqflite();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db.rows.clear();
    db.install();
  });
  tearDown(db.uninstall);

  Future<void> openStats(WidgetTester tester) async {
    await pumpScreen(tester, const Scaffold(body: MarketScreen()));
    await settle(tester);
  }

  testWidgets('TC-ST-01 empty database shows the "no scans" state',
      (tester) async {
    await openStats(tester);

    expect(find.text('Calamansi Sapling Insights'), findsOneWidget);
    expect(find.text('No scans recorded yet'), findsOneWidget);
    expect(find.text('Overall Healthy Saplings'), findsNothing);
    expect(find.text('Health Breakdown'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-ST-02 date filter chips are all present', (tester) async {
    await openStats(tester);

    for (final chip in ['All time', 'Today', '7 days', '30 days', 'Pick dates']) {
      expect(find.widgetWithText(ChoiceChip, chip), findsOneWidget,
          reason: chip);
    }
    await disposeTree(tester);
  });

  testWidgets('TC-ST-03 scan + sapling totals count every detection',
      (tester) async {
    final now = DateTime.now();
    db.rows.addAll([
      fakeScanRow(
        id: 1,
        time: now,
        detections: [_det('Healthy', 95), _det('Healthy', 93), _det('Wilting', 50)],
      ),
      fakeScanRow(
        id: 2,
        time: now.subtract(const Duration(days: 2)),
        detections: [_det('Yellowing', 70)],
      ),
      fakeScanRow(
        id: 3,
        time: now.subtract(const Duration(days: 3)),
        detections: [_det('Pest-Damaged', 25)],
      ),
    ]);
    await openStats(tester);

    expect(find.text('3 scan images · 5 saplings detected'), findsOneWidget);
    expect(find.text('Overall Healthy Saplings'), findsOneWidget);
    expect(find.text('40% Healthy'), findsOneWidget); // 2 of 5
    expect(find.text('2 of 5 saplings in good condition'), findsOneWidget);
    expect(find.text('Health Breakdown'), findsOneWidget);
    expect(find.text('Total Scan Images'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-ST-04 singular wording for one scan with one sapling',
      (tester) async {
    db.rows.add(fakeScanRow(id: 1, detections: [_det('Healthy', 95)]));
    await openStats(tester);

    expect(find.text('1 scan image · 1 sapling detected'), findsOneWidget);
    expect(find.text('100% Healthy'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-ST-05 "Today" filter excludes older scans', (tester) async {
    db.rows.add(fakeScanRow(
      id: 1,
      time: DateTime.now().subtract(const Duration(days: 5)),
      detections: [_det('Healthy', 95)],
    ));
    await openStats(tester);
    expect(find.text('1 scan image · 1 sapling detected'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Today'));
    await settle(tester);

    expect(find.text('No scans in this date range'), findsOneWidget);
    expect(find.text('Overall Healthy Saplings'), findsNothing);
    await disposeTree(tester);
  });
}