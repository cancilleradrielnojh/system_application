// Replaces the default Flutter counter test (it targeted a template app that
// no longer exists, so it always failed).  -> TC-AL-01 .. 04 (TC-AL-05 lives in app_theme_mode_test.dart)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/home.dart';
import 'package:system_application/main.dart';
import 'package:system_application/user_verification.dart';

import 'helpers/test_harness.dart';

void main() {
  configureWidgetTestEnvironment();
  final db = FakeSqflite();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db.rows.clear();
    db.install();
  });
  tearDown(db.uninstall);

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MyApp());
    await settle(tester);
  }

  testWidgets('TC-AL-01 first launch (no saved name) opens UserVerification',
      (tester) async {
    await launch(tester);

    expect(find.byType(UserVerification), findsOneWidget);
    expect(find.byType(Home), findsNothing);
    expect(find.text('Enter workspace'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-AL-02 returning user (saved name) goes straight to Home',
      (tester) async {
    SharedPreferences.setMockInitialValues({'username': 'JUAN'});
    await launch(tester);

    expect(find.byType(Home), findsOneWidget);
    expect(find.byType(UserVerification), findsNothing);
    expect(find.textContaining(', JUAN'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-AL-03 loading spinner is gone once the user is resolved',
      (tester) async {
    await launch(tester);

    expect(find.byIcon(Icons.spa_rounded), findsWidgets); // brand mark only
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-AL-04 debug banner is hidden', (tester) async {
    await launch(tester);

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp))
        .debugShowCheckedModeBanner, isFalse);
    await disposeTree(tester);
  });
}