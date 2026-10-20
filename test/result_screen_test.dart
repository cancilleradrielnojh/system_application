// Widget tests: ResultScreen (capture -> analysis result)  -> TC-RS-01 .. 04
//
// SCOPE NOTE: ResultScreen calls the global `inferenceService.analyzeImage`
// and the service cannot be injected, so under `flutter test` the model is
// never loaded and analysis always fails with "Model not loaded". That makes
// the ERROR path fully testable without touching lib/. The detected /
// not-detected sheets need an injection seam (see docs/WIDGET_TEST_CASES.md,
// section "Blocked cases").
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_application/result_screen.dart';
import 'package:system_application/detection/inference_service.dart';

import 'helpers/test_harness.dart';

// 1x1 transparent PNG so Image.file has something valid to decode.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  configureWidgetTestEnvironment();
  late File image;

  setUpAll(() {
    final dir = Directory.systemTemp.createTempSync('result_screen_test');
    image = File('${dir.path}/leaf.png')..writeAsBytesSync(base64Decode(_png));
  });

  Future<void> openResult(WidgetTester tester) async {
    await pumpScreen(tester, ResultScreen(imagePath: image.path));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);
  }

  testWidgets('TC-RS-01 failed analysis shows the error sheet',
      (tester) async {
    await openResult(tester);

    expect(find.text('SCAN RESULT'), findsOneWidget);
    expect(find.text('Analysis Failed'), findsOneWidget);
    expect(find.textContaining('Model not loaded'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('Detected calamansi saplings'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-RS-02 error sheet offers Try Again and no Done/Scan New',
      (tester) async {
    await openResult(tester);

    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Done'), findsNothing);
    expect(find.text('Scan New'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-RS-03 Try Again closes the screen and returns null',
      (tester) async {
    ResultPayload? received = ResultPayload(
        action: ResultAction.done, detections: const <DetectionResult>[]);
    var closed = false;

    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                received = await Navigator.push<ResultPayload?>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ResultScreen(imagePath: image.path)),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await settle(tester);

    await tester.ensureVisible(find.text('Try Again'));
    await tester.tap(find.text('Try Again'));
    await settle(tester);

    expect(closed, isTrue);
    expect(received, isNull);
    await disposeTree(tester);
  });

  testWidgets('TC-RS-04 result screen has no implicit back button',
      (tester) async {
    await openResult(tester);

    expect(find.byType(BackButton), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    await disposeTree(tester);
  });

  test('TC-RS-05 ResultPayload keeps action + detections; analysis optional',
      () {
    final payload = ResultPayload(
        action: ResultAction.scanNew, detections: const <DetectionResult>[]);
    expect(payload.action, ResultAction.scanNew);
    expect(payload.detections, isEmpty);
    expect(payload.analysis, isNull);
  });
}