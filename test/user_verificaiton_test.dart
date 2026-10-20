// Widget tests: UserVerification (first-run name screen)  -> TC-UV-01 .. 05
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/home.dart';
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

  Future<void> openScreen(WidgetTester tester) async {
    await pumpScreen(tester, const UserVerification());
    await tester.pump(const Duration(milliseconds: 800)); // fade/slide in
  }

  testWidgets('TC-UV-01 renders brand, tagline, name field and button',
      (tester) async {
    await openScreen(tester);

    expect(find.text('Q-LAMANSI'), findsOneWidget);
    expect(find.text('Sapling health, read at a glance.'), findsOneWidget);
    expect(find.text('IDENTIFY YOURSELF'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Your name'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Enter workspace'),
        findsOneWidget);
  });

  testWidgets('TC-UV-02 empty name is rejected (no navigation, nothing saved)',
      (tester) async {
    await openScreen(tester);

    await tester.tap(find.text('Enter workspace'));
    await settle(tester);

    expect(find.byType(UserVerification), findsOneWidget);
    expect(find.byType(Home), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), isNull);
  });

  testWidgets('TC-UV-03 whitespace-only name is rejected', (tester) async {
    await openScreen(tester);

    await tester.enterText(find.byType(TextField), '     ');
    await tester.tap(find.text('Enter workspace'));
    await settle(tester);

    expect(find.byType(Home), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), isNull);
  });

  testWidgets('TC-UV-04 valid name is trimmed, saved, and opens Home',
      (tester) async {
    await openScreen(tester);

    await tester.enterText(find.byType(TextField), '  Juan  ');
    await tester.tap(find.text('Enter workspace'));
    await settle(tester);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), 'Juan');
    expect(find.byType(Home), findsOneWidget);
    expect(find.textContaining(', Juan'), findsOneWidget);
    expect(find.byType(UserVerification), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('TC-UV-05 keyboard "done" submits the name', (tester) async {
    await openScreen(tester);

    await tester.enterText(find.byType(TextField), 'Maria');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(find.byType(Home), findsOneWidget);
    await disposeTree(tester);
  });
}