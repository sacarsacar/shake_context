import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/log_entry.dart';
import '../models/network_log.dart';
import 'log_capture.dart';

/// Pluggable loader for `PackageInfo.fromPlatform()`. Tests substitute a
/// fake implementation via [ContextCapturer.packageInfoLoaderOverride] to
/// avoid touching the platform channel.
typedef PackageInfoLoader = Future<PackageInfo> Function();

/// Gathers the side-channel data that `DeveloperView` displays and that
/// `ProductionView` optionally attaches: a screenshot of the live render
/// tree, a device snapshot, the current route name, and the rolling
/// log/network buffers drained from [LogCapture].
///
/// The capturer is constructed and owned by `ShakeContext`. Each method is
/// safe to call on the main isolate at any time outside the build phase —
/// they swallow plugin failures and return empty values so a missing platform
/// channel never blocks the report flow.
class ContextCapturer {
  ContextCapturer({
    required this.boundaryKey,
    this.logBufferSize = 200,
    this.networkBufferSize = 50,
    DeviceInfoPlugin? deviceInfo,
    ImagePicker? imagePicker,
    LogCapture? logCapture,
    PackageInfoLoader? packageInfoLoader,
  })  : _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
        _imagePicker = imagePicker ?? ImagePicker(),
        _logCapture = logCapture ?? LogCapture.instance,
        _packageInfoLoader =
            packageInfoLoader ?? packageInfoLoaderOverride ?? PackageInfo.fromPlatform {
    _logCapture.logBufferSize = logBufferSize;
    _logCapture.networkBufferSize = networkBufferSize;
  }

  /// Process-wide override hook for the package-info loader. Tests use this
  /// instead of constructor injection when the capturer is built deep inside
  /// `ShakeContext` and direct injection isn't ergonomic.
  @visibleForTesting
  static PackageInfoLoader? packageInfoLoaderOverride;

  /// Key attached to the `RepaintBoundary` that wraps the app tree. The
  /// boundary's render object is the source of screenshot bytes.
  final GlobalKey boundaryKey;

  /// Maximum number of log entries retained by the underlying [LogCapture].
  final int logBufferSize;

  /// Maximum number of network entries retained by the underlying [LogCapture].
  final int networkBufferSize;

  final DeviceInfoPlugin _deviceInfo;
  final ImagePicker _imagePicker;
  final LogCapture _logCapture;
  final PackageInfoLoader _packageInfoLoader;

  /// Ensure `debugPrint` is being captured. Idempotent — safe to call from
  /// `initState`. The widget calls this when the developer-mode config has
  /// `captureConsoleLogs: true`; `ShakeContext.guard` also calls it so logs
  /// are captured even before any widget mounts.
  void installLogInterceptor() => _logCapture.hookDebugPrint();

  /// Restore the previous `debugPrint` callback. Called when the widget is
  /// disposed. Does not clear the buffer — entries logged outside the widget
  /// (e.g. during boot via `guard`) are kept.
  void restoreLogInterceptor() => _logCapture.unhookDebugPrint();

  /// Snapshot and clear the rolling log buffer.
  List<LogEntry> drainConsoleLogs() => _logCapture.drainLogs();

  /// Snapshot and clear the rolling network buffer.
  List<NetworkLog> drainNetworkLogs() => _logCapture.drainNetwork();

  /// Render the subtree under [boundaryKey] to PNG bytes.
  ///
  /// Returns `null` when no boundary is mounted yet, or when the underlying
  /// `toImage` call fails (for example on platforms with no GL context).
  Future<Uint8List?> captureScreenshot({double pixelRatio = 3.0}) async {
    final ctx = boundaryKey.currentContext;
    if (ctx == null) return null;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;

    try {
      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (error, stack) {
      _debugWarn('captureScreenshot', error, stack);
      return null;
    }
  }

  /// Collect a curated platform-specific device snapshot. Keys are intentionally
  /// stable strings so consumers can rely on them across releases.
  ///
  /// User-identifying fields are deliberately excluded so the production
  /// sheet can advertise the payload as PII-free: iOS `name`
  /// (e.g. "Sakar's iPhone"), macOS `computerName`, and Windows
  /// `computerName` are all user-configurable and frequently contain the
  /// owner's first name.
  ///
  /// The map also includes `appVersion`, `appBuildNumber`, and `appPackageName`
  /// from `package_info_plus` — the version that produced the report is the
  /// single most-asked field on a bug ticket. When the platform-info or
  /// package-info call fails, the corresponding keys are absent rather than
  /// present-with-empty-string so consumers can tell "we tried and didn't
  /// know" from "the field is the empty string."
  Future<Map<String, Object?>> captureDeviceInfo() async {
    final platformInfo = await _capturePlatformInfo();
    final packageInfo = await _capturePackageInfo();
    return {...platformInfo, ...packageInfo};
  }

  Future<Map<String, Object?>> _capturePlatformInfo() async {
    try {
      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        return {
          'platform': 'web',
          'browser': info.browserName.name,
          'userAgent': info.userAgent,
          'appVersion': info.appVersion,
        };
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await _deviceInfo.androidInfo;
          return {
            'platform': 'android',
            'manufacturer': info.manufacturer,
            'model': info.model,
            'release': info.version.release,
            'sdkInt': info.version.sdkInt,
          };
        case TargetPlatform.iOS:
          final info = await _deviceInfo.iosInfo;
          return {
            'platform': 'ios',
            'systemName': info.systemName,
            'systemVersion': info.systemVersion,
            'model': info.model,
          };
        case TargetPlatform.macOS:
          final info = await _deviceInfo.macOsInfo;
          return {
            'platform': 'macos',
            'model': info.model,
            'osRelease': info.osRelease,
          };
        case TargetPlatform.windows:
          final info = await _deviceInfo.windowsInfo;
          return {
            'platform': 'windows',
            'productName': info.productName,
            'displayVersion': info.displayVersion,
          };
        case TargetPlatform.linux:
          final info = await _deviceInfo.linuxInfo;
          return {
            'platform': 'linux',
            'name': info.name,
            'version': info.version,
            'prettyName': info.prettyName,
          };
        case TargetPlatform.fuchsia:
          return {'platform': 'fuchsia'};
      }
    } catch (error, stack) {
      _debugWarn('captureDeviceInfo.platform', error, stack);
      return _fallbackPlatform();
    }
  }

  Future<Map<String, Object?>> _capturePackageInfo() async {
    try {
      final info = await _packageInfoLoader();
      return {
        'appName': info.appName,
        'appPackageName': info.packageName,
        'appVersion': info.version,
        'appBuildNumber': info.buildNumber,
      };
    } catch (error, stack) {
      _debugWarn('captureDeviceInfo.package', error, stack);
      return const <String, Object?>{};
    }
  }

  Map<String, Object?> _fallbackPlatform() {
    if (kIsWeb) return {'platform': 'web'};
    try {
      return {'platform': Platform.operatingSystem};
    } catch (error, stack) {
      _debugWarn('captureDeviceInfo.fallback', error, stack);
      return const {};
    }
  }

  /// Best-effort current route name. Uses `Navigator.popUntil` purely as an
  /// inspection trick — the predicate always returns true, so nothing is
  /// actually popped. Returns `null` when no route has a name set.
  String? currentRoute(NavigatorState? nav) {
    if (nav == null || !nav.mounted) return null;
    String? name;
    nav.popUntil((route) {
      name = route.settings.name;
      return true;
    });
    return name;
  }

  /// Open the system gallery picker and return the chosen image bytes.
  /// Returns `null` when the user cancels or the picker is unavailable.
  Future<Uint8List?> pickImageFromGallery() async {
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) return null;
      return await file.readAsBytes();
    } catch (error, stack) {
      _debugWarn('pickImageFromGallery', error, stack);
      return null;
    }
  }

  /// Surface swallowed capture failures on `debugPrint` in debug builds so
  /// developers can see why a screenshot/device-info/picker call silently
  /// returned null. No-op in release.
  static void _debugWarn(String operation, Object error, StackTrace stack) {
    if (!kDebugMode) return;
    debugPrint('[shake_context] $operation failed: $error');
  }
}
