// TC-AL-05  MyApp follows themeNotifier (light -> dark -> light)
//
// Kept in its own file ON PURPOSE. MyApp (lib/main.dart) adds a listener to the
// global themeNotifier and never removes it, and that listener calls setState
// without a `mounted` check. If an earlier test in the same file had already
// mounted and disposed a MyApp, changing the notifier here would call
// setState() on that disposed State and fail the test. A file = a fresh
// isolate, so this test sees exactly one MyApp. (See finding F-03 in
// docs/WIDGET_TEST_CASES.md.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/main.dart';
import 'package:system_application/profile_settings/theme_notifier.dart';

import 'helpers/test_harness.dart';

void main() {
  configureWidgetTestEnvironment();
  final db = FakeSqflite();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db.install();
  });
  tearDown(db.uninstall);

  testWidgets('TC-AL-05 MaterialApp themeMode follows themeNotifier',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MyApp());
    await settle(tester);
    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.light);

    themeNotifier.value = ThemeMode.dark;
    await tester.pump();
    expect(app().themeMode, ThemeMode.dark);

    // Restore while MyApp is still mounted (its listener is never removed).
    themeNotifier.value = ThemeMode.light;
    await tester.pump();
    expect(app().themeMode, ThemeMode.light);

    await disposeTree(tester);
  });
}