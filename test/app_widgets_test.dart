// Widget tests: shared UI components in lib/theme/app_widgets.dart
// -> TC-AW-01 .. 08
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_application/theme/app_theme.dart';
import 'package:system_application/theme/app_widgets.dart';

import 'helpers/test_harness.dart';

void main() {
  configureWidgetTestEnvironment();

  testWidgets('TC-AW-01 LimeCta shows label + icon and fires onTap once',
      (tester) async {
    var taps = 0;
    await pumpScreen(
      tester,
      Scaffold(
        body: Center(
          child: LimeCta(
              label: 'START SCAN',
              icon: Icons.center_focus_strong_rounded,
              onTap: () => taps++),
        ),
      ),
    );

    expect(find.text('START SCAN'), findsOneWidget);
    expect(find.byIcon(Icons.center_focus_strong_rounded), findsOneWidget);
    await tester.tap(find.byType(LimeCta));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('TC-AW-02 LimeCta compact variant is shorter (52 vs 64)',
      (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: Column(
          children: [
            LimeCta(
                key: const Key('full'),
                label: 'A',
                icon: Icons.add,
                onTap: () {}),
            LimeCta(
                key: const Key('compact'),
                label: 'B',
                icon: Icons.add,
                compact: true,
                onTap: () {}),
          ],
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('full'))).height, 64);
    expect(tester.getSize(find.byKey(const Key('compact'))).height, 52);
  });

  testWidgets('TC-AW-03 StatusChip renders its label in the given color',
      (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(
            child: StatusChip(label: 'Wilting', color: AppColors.wilt)),
      ),
    );

    final text = tester.widget<Text>(find.text('Wilting'));
    expect(text.style?.color, AppColors.wilt);
  });

  testWidgets('TC-AW-04 SectionLabel upper-cases its text', (tester) async {
    await pumpScreen(
        tester, const Scaffold(body: Center(child: SectionLabel('Preferences'))));

    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('Preferences'), findsNothing);
  });

  testWidgets('TC-AW-05 BrandMark swaps colors between light and dark theme',
      (tester) async {
    BoxDecoration decoration() => tester
        .widget<Container>(find
            .descendant(
                of: find.byType(BrandMark), matching: find.byType(Container))
            .first)
        .decoration as BoxDecoration;

    await pumpScreen(
        tester, const Scaffold(body: Center(child: BrandMark(size: 48))));
    expect(decoration().color, AppColors.ink);

    await pumpScreen(tester,
        const Scaffold(body: Center(child: BrandMark(size: 48))),
        themeMode: ThemeMode.dark);
    await tester.pump(const Duration(milliseconds: 500));
    expect(decoration().color, AppColors.lime);
  });

  testWidgets('TC-AW-06 FuturisticNavBar lists 4 tabs and reports taps by index',
      (tester) async {
    final taps = <int>[];
    await pumpScreen(
      tester,
      Scaffold(
        bottomNavigationBar:
            FuturisticNavBar(index: 0, onTap: (i) => taps.add(i)),
      ),
    );

    for (final label in ['Home', 'History', 'Statistics', 'Settings']) {
      expect(find.text(label), findsOneWidget, reason: 'tab "$label"');
    }
    await tester.tap(find.text('History'));
    await tester.tap(find.text('Settings'));
    await tester.tap(find.text('Statistics'));
    expect(taps, [1, 3, 2]);
  });

  testWidgets('TC-AW-07 FuturisticNavBar selected tab uses the filled icon',
      (tester) async {
    await pumpScreen(
      tester,
      Scaffold(bottomNavigationBar: FuturisticNavBar(index: 1, onTap: (_) {})),
    );

    expect(find.byIcon(Icons.history_rounded), findsOneWidget);
    expect(find.byIcon(Icons.history_outlined), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsOneWidget);
  });

  test('TC-AW-08 ScanFramePainter repaints only when its color changes', () {
    final a = ScanFramePainter(color: AppColors.lime);
    expect(a.shouldRepaint(ScanFramePainter(color: AppColors.lime)), isFalse);
    expect(a.shouldRepaint(ScanFramePainter(color: AppColors.teal)), isTrue);
  });
}