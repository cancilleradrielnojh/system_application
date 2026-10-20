// Widget tests: ScannerScreen (live camera screen)  -> TC-SC-01 .. 08
//
// The real camera cannot run under `flutter test`. These tests replace the
// camera platform with a fake that fails in controlled ways, which verifies
// the permission / error / empty-camera UI and the lifecycle handling. They do
// NOT prove live preview, live detection overlay alignment or capture on a
// device - those need integration_test on a physical Android phone.
//
// Requires dev dependencies (transitive today, add explicitly):
//   flutter pub add --dev camera_platform_interface plugin_platform_interface

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:system_application/scanner.dart';

import 'helpers/test_harness.dart';

class _FakeCameraPlatform extends CameraPlatform
    with MockPlatformInterfaceMixin {
  _FakeCameraPlatform({
    List<CameraDescription>? cameras,
    this.errorCode = 'CameraAccessDenied',
    this.errorDescription = 'denied',
  }) : cameras = cameras ??
            [
              CameraDescription(
                  name: '0',
                  lensDirection: CameraLensDirection.back,
                  sensorOrientation: 90),
            ];

  final List<CameraDescription> cameras;
  final String errorCode;
  final String errorDescription;
  int availableCamerasCalls = 0;

  @override
  Future<List<CameraDescription>> availableCameras() async {
    availableCamerasCalls++;
    return cameras;
  }

  @override
  Future<int> createCamera(CameraDescription cameraDescription,
          ResolutionPreset? resolutionPreset,
          {bool enableAudio = false}) async =>
      throw CameraException(errorCode, errorDescription);

  // Parameter widened to Object? so this compiles whether or not the installed
  // camera_platform_interface version has MediaSettings.
  @override
  Future<int> createCameraWithSettings(
          CameraDescription cameraDescription, Object? mediaSettings) async =>
      throw CameraException(errorCode, errorDescription);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream<DeviceOrientationChangedEvent>.empty();
}

void main() {
  configureWidgetTestEnvironment();
  final db = FakeSqflite();
  CameraPlatform? originalPlatform;
  final pickerCalls = <String>[];

  setUp(() {
    originalPlatform = CameraPlatform.instance;
    db.install();
    pickerCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'),
            (call) async {
      pickerCalls.add(call.method);
      return null; // user cancelled the gallery
    });
  });

  tearDown(() {
    CameraPlatform.instance = originalPlatform!;
    db.uninstall();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/image_picker'), null);
  });

  Future<void> openScanner(WidgetTester tester) async {
    await pumpScreen(tester, ScannerScreen(onScanComplete: (_, _, _) {}));
    await settle(tester);
  }

  testWidgets('TC-SC-01 shows title, Capture and gallery controls',
      (tester) async {
    CameraPlatform.instance = _FakeCameraPlatform();
    await openScanner(tester);

    expect(find.text('SCAN FRAME'), findsOneWidget);
    // ElevatedButton.icon / OutlinedButton.icon build private subclasses, so
    // find.byType (exact match) would miss them; match by subtype instead.
    expect(
        find.ancestor(
            of: find.text('Capture'),
            matching: find.bySubtype<ElevatedButton>()),
        findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Upload from gallery'),
            matching: find.bySubtype<OutlinedButton>()),
        findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-SC-02 camera permission denied shows the permission message',
      (tester) async {
    CameraPlatform.instance = _FakeCameraPlatform(errorCode: 'CameraAccessDenied');
    await openScanner(tester);

    expect(find.text('Camera unavailable'), findsOneWidget);
    expect(find.text('Camera permission is required to scan live.'),
        findsOneWidget);
    expect(find.text('Align leaf inside brackets'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-SC-03 permission denied without prompt / restricted too',
      (tester) async {
    for (final code in ['CameraAccessDeniedWithoutPrompt', 'CameraAccessRestricted']) {
      CameraPlatform.instance = _FakeCameraPlatform(errorCode: code);
      await openScanner(tester);
      expect(find.text('Camera permission is required to scan live.'),
          findsOneWidget,
          reason: code);
      await disposeTree(tester);
    }
  });

  testWidgets('TC-SC-04 other camera errors show the error description',
      (tester) async {
    CameraPlatform.instance = _FakeCameraPlatform(
        errorCode: 'CameraNotAvailable', errorDescription: 'sensor busy');
    await openScanner(tester);

    expect(find.text('Camera error: sensor busy'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-SC-05 device with no cameras shows a generic message',
      (tester) async {
    CameraPlatform.instance = _FakeCameraPlatform(cameras: <CameraDescription>[]);
    await openScanner(tester);

    expect(find.text('Camera unavailable'), findsOneWidget);
    expect(find.text('Camera unavailable.'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('TC-SC-06 no live overlay or capture frame without a camera',
      (tester) async {
    CameraPlatform.instance = _FakeCameraPlatform();
    await openScanner(tester);

    expect(find.text('No sapling detected'), findsNothing);
    expect(find.textContaining('sapling detected'), findsNothing);
    expect(find.text('Align leaf inside brackets'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-SC-07 Capture is a no-op while the camera is not ready',
      (tester) async {
    CameraPlatform.instance = _FakeCameraPlatform();
    await openScanner(tester);

    await tester.tap(find.text('Capture'));
    await settle(tester);

    expect(find.text('Capture'), findsOneWidget);
    expect(find.text('Processing…'), findsNothing);
    expect(find.text('SCAN RESULT'), findsNothing); // no ResultScreen pushed
    await disposeTree(tester);
  });

  testWidgets('TC-SC-08 cancelled gallery pick returns to the camera screen',
      (tester) async {
    CameraPlatform.instance = _FakeCameraPlatform();
    await openScanner(tester);

    await tester.tap(find.text('Upload from gallery'));
    await settle(tester);

    expect(pickerCalls, contains('pickImage'));
    expect(find.text('SCAN FRAME'), findsOneWidget);
    expect(find.text('Capture'), findsOneWidget); // not stuck on Processing…
    expect(find.text('SCAN RESULT'), findsNothing);
    await disposeTree(tester);
  });

  testWidgets('TC-SC-09 resuming the app retries camera initialisation',
      (tester) async {
    final fake = _FakeCameraPlatform();
    CameraPlatform.instance = fake;
    await openScanner(tester);
    final before = fake.availableCamerasCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    expect(fake.availableCamerasCalls, greaterThan(before));
    await disposeTree(tester);
  });
}