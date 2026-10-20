// White-box unit tests: ThemeNotifier and nameNotifier
// Sources: lib/profile_settings/theme_notifier.dart, name_notifier.dart
//
// Branches covered: _loadTheme (saved true / saved false / nothing saved),
// toggleTheme (light->dark and dark->light, persisted value, listener call),
// isDark getter, nameNotifier notification.
//
// New ThemeNotifier() instances are used so the app-wide singleton
// `themeNotifier` is never touched.
//
//   UT-NT-01..06
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_application/profile_settings/name_notifier.dart';
import 'package:system_application/profile_settings/theme_notifier.dart';

Future<void> _let() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UT-NT-01 starts light, and stays light when nothing is saved',
      () async {
    SharedPreferences.setMockInitialValues({});
    final n = ThemeNotifier();
    expect(n.value, ThemeMode.light);
    await _let();
    expect(n.value, ThemeMode.light);
    expect(n.isDark, isFalse);
  });

  test('UT-NT-02 saved darkMode=true is loaded asynchronously', () async {
    SharedPreferences.setMockInitialValues({'darkMode': true});
    final n = ThemeNotifier();
    await _let();
    expect(n.value, ThemeMode.dark);
    expect(n.isDark, isTrue);
  });

  test('UT-NT-03 saved darkMode=false keeps light', () async {
    SharedPreferences.setMockInitialValues({'darkMode': false});
    final n = ThemeNotifier();
    await _let();
    expect(n.value, ThemeMode.light);
  });

  test('UT-NT-04 toggleTheme flips the mode and persists the choice',
      () async {
    SharedPreferences.setMockInitialValues({});
    final n = ThemeNotifier();
    await _let();

    await n.toggleTheme();
    expect(n.value, ThemeMode.dark);
    expect((await SharedPreferences.getInstance()).getBool('darkMode'), true);

    await n.toggleTheme();
    expect(n.value, ThemeMode.light);
    expect((await SharedPreferences.getInstance()).getBool('darkMode'), false);
  });

  test('UT-NT-05 toggleTheme notifies listeners once per change', () async {
    SharedPreferences.setMockInitialValues({});
    final n = ThemeNotifier();
    await _let();
    var calls = 0;
    n.addListener(() => calls++);
    await n.toggleTheme();
    expect(calls, 1);
    await n.toggleTheme();
    expect(calls, 2);
  });

  test('UT-NT-06 nameNotifier starts empty and notifies on change', () {
    final original = nameNotifier.value;
    addTearDown(() => nameNotifier.value = original);

    nameNotifier.value = '';
    var calls = 0;
    void l() => calls++;
    nameNotifier.addListener(l);
    addTearDown(() => nameNotifier.removeListener(l));

    nameNotifier.value = 'Maria';
    expect(nameNotifier.value, 'Maria');
    expect(calls, 1);

    nameNotifier.value = 'Maria'; // same value: ValueNotifier does not notify
    expect(calls, 1);
  });
}