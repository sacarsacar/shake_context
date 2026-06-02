import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shake_context/shake_context.dart';
import 'package:shake_context/src/core/context_capturer.dart';
import 'package:shake_context/src/core/log_capture.dart';

void main() {
  group('log buffer', () {
    setUp(() => LogCapture.instance.reset());
    tearDown(() => LogCapture.instance.reset());

    test('drainConsoleLogs returns captured entries and clears the buffer', () {
      final capturer = ContextCapturer(boundaryKey: GlobalKey());
      capturer.installLogInterceptor();
      try {
        debugPrint('alpha');
        debugPrint('beta');
        debugPrint('gamma');

        final first = capturer.drainConsoleLogs();
        expect(first.map((e) => e.message).toList(),
            ['alpha', 'beta', 'gamma']);
        expect(first.every((e) => e.level == LogLevel.info), isTrue);
        expect(first.every((e) => e.source == 'debugPrint'), isTrue);

        // Buffer is empty after drain.
        expect(capturer.drainConsoleLogs(), isEmpty);
      } finally {
        capturer.restoreLogInterceptor();
      }
    });

    test('evicts oldest entries once logBufferSize is reached', () {
      final capturer =
          ContextCapturer(boundaryKey: GlobalKey(), logBufferSize: 3);
      capturer.installLogInterceptor();
      try {
        for (var i = 0; i < 7; i++) {
          debugPrint('line $i');
        }
        expect(
          capturer.drainConsoleLogs().map((e) => e.message).toList(),
          ['line 4', 'line 5', 'line 6'],
        );
      } finally {
        capturer.restoreLogInterceptor();
      }
    });

    test('restoreLogInterceptor stops capturing further lines', () {
      final capturer = ContextCapturer(boundaryKey: GlobalKey());
      capturer.installLogInterceptor();
      debugPrint('inside');
      // Drain the 'inside' entry so the next assertion is meaningful.
      capturer.drainConsoleLogs();
      capturer.restoreLogInterceptor();
      debugPrint('outside');

      // Reinstall to inspect — 'outside' was emitted while unhooked, so the
      // buffer is empty.
      capturer.installLogInterceptor();
      try {
        expect(capturer.drainConsoleLogs(), isEmpty);
      } finally {
        capturer.restoreLogInterceptor();
      }
    });

    test('install is idempotent — calling twice does not double-wrap', () {
      final capturer = ContextCapturer(boundaryKey: GlobalKey());
      capturer.installLogInterceptor();
      capturer.installLogInterceptor();
      try {
        debugPrint('once');
        final entries = capturer.drainConsoleLogs();
        expect(entries.length, 1);
        expect(entries.single.message, 'once');
      } finally {
        capturer.restoreLogInterceptor();
      }
    });

    test('ShakeContext.log records structured entries', () {
      final capturer = ContextCapturer(boundaryKey: GlobalKey());
      ShakeContext.log('boom',
          level: LogLevel.error, source: 'unit', stackTrace: StackTrace.current);
      final entries = capturer.drainConsoleLogs();
      expect(entries.length, 1);
      expect(entries.single.level, LogLevel.error);
      expect(entries.single.source, 'unit');
      expect(entries.single.stackTrace, isNotNull);
    });

    test('recordNetwork pushes into the network buffer', () {
      final capturer = ContextCapturer(boundaryKey: GlobalKey());
      ShakeContext.recordNetwork(NetworkLog(
        method: 'GET',
        url: 'https://example.test/items',
        statusCode: 200,
        durationMs: 42,
      ));
      final net = capturer.drainNetworkLogs();
      expect(net.length, 1);
      expect(net.single.url, 'https://example.test/items');
      expect(net.single.statusCode, 200);
    });
  });

  group('captureDeviceInfo', () {
    test('returns curated Android map when running on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final fakeAndroid = AndroidDeviceInfo.fromMap(_fakeAndroidMap());
      final plugin = DeviceInfoPlugin.setMockInitialValues(
        androidDeviceInfo: fakeAndroid,
      );
      final capturer =
          ContextCapturer(boundaryKey: GlobalKey(), deviceInfo: plugin);

      final info = await capturer.captureDeviceInfo();
      expect(info['platform'], 'android');
      expect(info['manufacturer'], 'TestVendor');
      expect(info['model'], 'TestModel');
      expect(info['release'], '14');
      expect(info['sdkInt'], 34);
    });

    test('returns curated iOS map when running on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final fakeIos = IosDeviceInfo.fromMap(_fakeIosMap());
      final plugin = DeviceInfoPlugin.setMockInitialValues(
        iosDeviceInfo: fakeIos,
      );
      final capturer =
          ContextCapturer(boundaryKey: GlobalKey(), deviceInfo: plugin);

      final info = await capturer.captureDeviceInfo();
      expect(info['platform'], 'ios');
      expect(info['systemName'], 'iOS');
      expect(info['systemVersion'], '17.4');
      expect(info['model'], 'iPhone');
      // `info.name` is the user-set device name — must stay out of the
      // payload so the prod sheet can promise a PII-free report.
      expect(info.containsKey('name'), isFalse);
    });
  });

  group('pickImageFromGallery', () {
    test('returns bytes from XFile when picker yields a file', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final picker = _StubPicker(XFile.fromData(bytes, name: 'pic.png'));
      final capturer =
          ContextCapturer(boundaryKey: GlobalKey(), imagePicker: picker);

      final result = await capturer.pickImageFromGallery();
      expect(result, bytes);
    });

    test('returns null when the user cancels (picker yields null)', () async {
      final picker = _StubPicker(null);
      final capturer =
          ContextCapturer(boundaryKey: GlobalKey(), imagePicker: picker);

      expect(await capturer.pickImageFromGallery(), isNull);
    });

    test('swallows picker errors and returns null', () async {
      final picker = _ThrowingPicker();
      final capturer =
          ContextCapturer(boundaryKey: GlobalKey(), imagePicker: picker);

      expect(await capturer.pickImageFromGallery(), isNull);
    });
  });

  group('currentRoute', () {
    testWidgets('reads the current route name without popping', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        initialRoute: '/',
        routes: {
          '/': (_) => const Scaffold(body: SizedBox.shrink()),
          '/profile': (_) => const Scaffold(body: SizedBox.shrink()),
        },
      ));
      navKey.currentState!.pushNamed('/profile');
      await tester.pumpAndSettle();

      final capturer = ContextCapturer(boundaryKey: GlobalKey());
      expect(capturer.currentRoute(navKey.currentState), '/profile');

      // The Navigator stack was not disturbed.
      expect(navKey.currentState!.canPop(), isTrue);
    });

    test('returns null when navigator is null', () {
      final capturer = ContextCapturer(boundaryKey: GlobalKey());
      expect(capturer.currentRoute(null), isNull);
    });
  });

  group('captureScreenshot', () {
    testWidgets('returns null when no boundary is mounted yet', (tester) async {
      final capturer = ContextCapturer(boundaryKey: GlobalKey());
      expect(await capturer.captureScreenshot(), isNull);
    });

    testWidgets('produces non-empty PNG bytes from a mounted boundary',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: Container(
              width: 40,
              height: 40,
              color: const Color(0xFF00FF00),
            ),
          ),
        ),
      );

      final capturer = ContextCapturer(boundaryKey: key);
      final bytes = await tester.runAsync(() => capturer.captureScreenshot(
            pixelRatio: 1.0,
          ));

      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(8));
      // PNG magic bytes — 89 50 4E 47.
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });
}

Map<String, dynamic> _fakeAndroidMap() => {
      'version': <String, dynamic>{
        'baseOS': '',
        'codename': 'REL',
        'incremental': '0',
        'previewSdkInt': 0,
        'release': '14',
        'sdkInt': 34,
        'securityPatch': '2026-01-01',
      },
      'board': 'test_board',
      'bootloader': 'test_bootloader',
      'brand': 'test_brand',
      'device': 'test_device',
      'display': 'test_display',
      'fingerprint': 'test_fingerprint',
      'hardware': 'test_hardware',
      'host': 'test_host',
      'id': 'test_id',
      'manufacturer': 'TestVendor',
      'model': 'TestModel',
      'product': 'test_product',
      'name': 'test_name',
      'supported32BitAbis': <String>[],
      'supported64BitAbis': <String>[],
      'supportedAbis': <String>[],
      'tags': 'test_tags',
      'type': 'test_type',
      'isPhysicalDevice': true,
      'freeDiskSize': 1000,
      'totalDiskSize': 2000,
      'systemFeatures': <String>[],
      'serialNumber': 'SERIAL',
      'isLowRamDevice': false,
      'physicalRamSize': 8000,
      'availableRamSize': 4000,
    };

Map<String, dynamic> _fakeIosMap() => {
      'name': 'Sim iPhone',
      'systemName': 'iOS',
      'systemVersion': '17.4',
      'model': 'iPhone',
      'modelName': 'iPhone 15',
      'localizedModel': 'iPhone',
      'identifierForVendor': '00000000-0000-0000-0000-000000000000',
      'freeDiskSize': 1000,
      'totalDiskSize': 2000,
      'physicalRamSize': 6000,
      'availableRamSize': 3000,
      'isPhysicalDevice': false,
      'isiOSAppOnMac': false,
      'utsname': <String, dynamic>{
        'sysname': 'Darwin',
        'nodename': 'iPhone',
        'release': '23.0.0',
        'version': 'Darwin Kernel Version 23.0.0',
        'machine': 'iPhone15,2',
      },
    };

class _StubPicker extends ImagePicker {
  _StubPicker(this._file);

  final XFile? _file;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async =>
      _file;
}

class _ThrowingPicker extends ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) =>
      Future<XFile?>.error(StateError('picker exploded'));
}
