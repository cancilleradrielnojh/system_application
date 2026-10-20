// Widget tests: AccountSettingsScreen + sub-screens  -> TC-AS-01 .. 09
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/account_settings.dart';
import 'package:system_application/profile_settings/name_notifier.dart';
import 'package:system_application/profile_settings/profile_settings_screen.dart';
import 'package:system_application/profile_settings/support_help_screen.dart';
import 'package:system_application/profile_settings/theme_notifier.dart';

import 'helpers/test_harness.dart';

void main() {
  configureWidgetTestEnvironment();
  final db = FakeSqflite();
  var cleared = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db.rows.clear();
    cleared = 0;
    nameNotifier.value = '';
    themeNotifier.value = ThemeMode.light;
    db.install();
  });
  tearDown(db.uninstall);

  Future<void> openSettings(WidgetTester tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: AccountSettingsScreen(name: 'JUAN', onDataCleared: () => cleared++),
      ),
    );
    await settle(tester);
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  Finder inDialog(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  testWidgets('TC-AS-01 renders profile card and all settings rows',
      (tester) async {
    await openSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('JUAN'), findsOneWidget);
    expect(find.text('Field operator'), findsOneWidget);
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('Profile Settings'), findsOneWidget);
    expect(find.text('Dark Mode'), findsOneWidget);
    expect(find.text('Push Notifications'), findsOneWidget);
    expect(find.text('Support & Help'), findsOneWidget);
    expect(find.text('DANGER ZONE'), findsOneWidget);
    expect(find.text('Clear All App Data'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-AS-02 stored username replaces the constructor name',
      (tester) async {
    SharedPreferences.setMockInitialValues({'username': 'PEDRO'});
    await openSettings(tester);

    expect(find.text('PEDRO'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-AS-03 Push Notifications toggle persists the preference',
      (tester) async {
    await openSettings(tester);
    expect(find.text('Alerts on'), findsOneWidget);

    await tapVisible(tester, find.byType(Switch).at(1));

    expect(find.text('Alerts off'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pushNotifications'), isFalse);

    await tapVisible(tester, find.byType(Switch).at(1));
    expect(find.text('Alerts on'), findsOneWidget);
    expect(prefs.getBool('pushNotifications'), isTrue);
    await disposeTree(tester);
  });

  testWidgets('TC-AS-04 Dark Mode toggle flips themeNotifier and subtitle',
      (tester) async {
    await openSettings(tester);
    expect(find.text('Light active'), findsOneWidget);

    await tapVisible(tester, find.byType(Switch).at(0));

    expect(themeNotifier.value, ThemeMode.dark);
    expect(find.text('Dark active'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('darkMode'), isTrue);
    await disposeTree(tester);
  });

  testWidgets('TC-AS-05 Clear All App Data: Cancel changes nothing',
      (tester) async {
    db.rows.add(fakeScanRow(id: 1));
    await openSettings(tester);

    await tapVisible(tester, find.text('Clear All App Data'));
    expect(find.text('Clear all app data?'), findsOneWidget);
    await tester.tap(inDialog('Cancel'));
    await settle(tester);

    expect(find.text('Clear all app data?'), findsNothing);
    expect(db.rows.length, 1);
    expect(cleared, 0);
    expect(find.text('All app data cleared'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-AS-06 Clear All App Data: confirm wipes scans and prefs',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'farmName': 'Dela Cruz Farm', 'location': 'Iloilo', 'scansToday': 4});
    db.rows.addAll([fakeScanRow(id: 1), fakeScanRow(id: 2)]);
    await openSettings(tester);

    await tapVisible(tester, find.text('Clear All App Data'));
    await tester.tap(inDialog('Clear all'));
    await settle(tester);

    expect(db.rows, isEmpty);
    expect(cleared, 1);
    expect(find.text('All app data cleared'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('farmName'), isNull);
    expect(prefs.getString('location'), isNull);
    expect(prefs.getInt('scansToday'), isNull);
    await disposeTree(tester);
  });

  testWidgets('TC-AS-07 Support & Help opens the help screen', (tester) async {
    await openSettings(tester);

    await tapVisible(tester, find.text('Support & Help'));

    expect(find.byType(SupportHelpScreen), findsOneWidget);
    expect(find.text('App Features'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-AS-08 Profile Settings opens pre-filled with the name',
      (tester) async {
    await openSettings(tester);

    await tapVisible(tester, find.text('Profile Settings'));

    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    expect(find.text('Personal Info'), findsOneWidget);
    final nameField = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Display Name'));
    expect(nameField.controller?.text, 'JUAN');
    await disposeTree(tester);
  });

  testWidgets('TC-AS-09 Profile save: empty name rejected, valid name saved',
      (tester) async {
    await openSettings(tester);
    await tapVisible(tester, find.text('Profile Settings'));

    // empty -> validation message, stays on the screen
    await tester.enterText(find.widgetWithText(TextField, 'Display Name'), '   ');
    await tapVisible(tester, find.text('Save Changes'));
    expect(find.text('Name cannot be empty'), findsOneWidget);
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);

    // valid -> saved, notifier updated, screen closes
    await tester.enterText(
        find.widgetWithText(TextField, 'Display Name'), 'MARIA');
    await tester.enterText(
        find.widgetWithText(TextField, 'Farm Name (optional)'), 'Sunrise Farm');
    await tapVisible(tester, find.text('Save Changes'));
    await settle(tester, frames: 12);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), 'MARIA');
    expect(prefs.getString('farmName'), 'Sunrise Farm');
    expect(nameNotifier.value, 'MARIA');
    expect(find.byType(ProfileSettingsScreen), findsNothing);
    expect(find.text('MARIA'), findsOneWidget); // settings header updated
    await disposeTree(tester);
  });
}