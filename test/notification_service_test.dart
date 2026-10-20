// Widget tests: NotificationService snackbars (scan result banners)
// -> TC-NS-01 .. 08
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/detection/inference_service.dart';
import 'package:system_application/profile_settings/notification_service.dart';

import 'helpers/test_harness.dart';

DetectionResult _det(SaplingClass? cls, {bool calamansi = true}) =>
    DetectionResult(
      saplingClass: cls,
      confidence: 0.9,
      boxAreaPx: 1000,
      isCalamansi: calamansi,
    );

void main() {
  configureWidgetTestEnvironment();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> host(WidgetTester tester) => pumpScreen(
        tester,
        const Scaffold(body: SizedBox.expand()),
        messengerKey: NotificationService.messengerKey,
      );

  Future<void> send(
    WidgetTester tester, {
    bool success = true,
    double health = 0,
    List<DetectionResult> detections = const [],
  }) async {
    await NotificationService.sendScanNotification(
        success: success, health: health, detections: detections);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Color? bg(WidgetTester tester) =>
      tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor;

  testWidgets('TC-NS-01 failed scan shows a red failure banner',
      (tester) async {
    await host(tester);
    await send(tester, success: false);

    expect(find.text('❌ Scan failed. Please try again.'), findsOneWidget);
    expect(bg(tester), Colors.red);
    await disposeTree(tester);
  });

  testWidgets('TC-NS-02 single class: count + class name, green for Healthy',
      (tester) async {
    await host(tester);
    await send(tester, detections: [
      _det(SaplingClass.healthy),
      _det(SaplingClass.healthy),
    ]);

    expect(find.text('✅ 2 detected — Healthy'), findsOneWidget);
    expect(bg(tester), Colors.green);
    await disposeTree(tester);
  });

  testWidgets('TC-NS-03 mixed classes: count only, color from the top class',
      (tester) async {
    await host(tester);
    await send(tester, detections: [
      _det(SaplingClass.wilting),
      _det(SaplingClass.wilting),
      _det(SaplingClass.healthy),
    ]);

    expect(find.text('✅ 3 detected'), findsOneWidget);
    expect(bg(tester), Colors.orange); // Wilting is the most frequent
    await disposeTree(tester);
  });

  testWidgets('TC-NS-04 yellowing uses amber, pest-damaged uses red',
      (tester) async {
    await host(tester);
    await send(tester, detections: [_det(SaplingClass.yellowing)]);
    expect(bg(tester), const Color(0xFFD4A017));

    NotificationService.messengerKey.currentState!.clearSnackBars();
    await tester.pump();
    await send(tester, detections: [_det(SaplingClass.pestDamaged)]);
    expect(find.text('✅ 1 detected — Pest-Damaged'), findsOneWidget);
    expect(bg(tester), Colors.red);
    await disposeTree(tester);
  });

  testWidgets('TC-NS-05 non-calamansi detections are ignored with a warning',
      (tester) async {
    await host(tester);
    await send(tester, detections: [
      _det(SaplingClass.healthy, calamansi: false),
    ]);

    expect(find.text('⚠️ No valid calamansi detection found.'), findsOneWidget);
    expect(bg(tester), Colors.orange);
    await disposeTree(tester);
  });

  testWidgets('TC-NS-06 no detections: banner derives from the health score',
      (tester) async {
    final cases = <double, String>{
      95: '✅ 95.0% — Healthy',
      75: '🟡 75.0% — Yellowing detected',
      50: '🥀 50.0% — Wilting detected',
      10: '🐛 10.0% — Pest damage detected',
    };
    await host(tester);
    for (final e in cases.entries) {
      NotificationService.messengerKey.currentState!.clearSnackBars();
      await tester.pump();
      await send(tester, health: e.key);
      expect(find.text(e.value), findsOneWidget, reason: 'health ${e.key}');
    }
    await disposeTree(tester);
  });

  testWidgets('TC-NS-07 nothing is shown when push notifications are off',
      (tester) async {
    SharedPreferences.setMockInitialValues({'pushNotifications': false});
    await host(tester);
    await send(tester, detections: [_det(SaplingClass.healthy)]);

    expect(find.byType(SnackBar), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-NS-08 banner is floating and uses a bold message',
      (tester) async {
    await host(tester);
    await send(tester, detections: [_det(SaplingClass.healthy)]);

    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.behavior, SnackBarBehavior.floating);
    expect(bar.duration, const Duration(seconds: 4));
    final text = tester.widget<Text>(find.text('✅ 1 detected — Healthy'));
    expect(text.style?.fontWeight, FontWeight.bold);
    await disposeTree(tester);
  });

  test('TC-NS-09 DetectionResult class labels match the 4 target classes', () {
    expect(_det(SaplingClass.healthy).className, 'Healthy');
    expect(_det(SaplingClass.yellowing).className, 'Yellowing');
    expect(_det(SaplingClass.pestDamaged).className, 'Pest-Damaged');
    expect(_det(SaplingClass.wilting).className, 'Wilting');
    expect(_det(null).className, 'Unknown');
    expect(SaplingClass.values.length, 4);
  });
}