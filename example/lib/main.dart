import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shake_context/shake_context.dart';

import 'report_uploader.dart';

void main() {
  // ShakeContext.guard hooks `print`, `debugPrint`, FlutterError.onError, and
  // PlatformDispatcher.onError so the overlay can show everything the app
  // emits — including third-party loggers and uncaught async errors.
  ShakeContext.guard(() => runApp(const ShakeContextExampleApp()));
}

/// Test harness for the shake_context package.
///
/// Exposes runtime controls for every knob worth verifying on a device:
///   * Theme mode (light / dark / system)
///   * Inspect mode (developer / production)
///   * Custom [ReportTheme] override
///   * Buttons that emit every supported log type
///   * Buttons that synthesise mock HTTP cycles, including failures
///   * A programmatic "open overlay" button for simulator/desktop
class ShakeContextExampleApp extends StatefulWidget {
  const ShakeContextExampleApp({super.key});

  @override
  State<ShakeContextExampleApp> createState() => _ShakeContextExampleAppState();
}

class _ShakeContextExampleAppState extends State<ShakeContextExampleApp> {
  // ShakeContext sits above MaterialApp so the engine survives navigation,
  // route changes, and theme rebuilds. The navigatorKey is shared with
  // MaterialApp so the overlay can find a Navigator from up here.
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  ThemeMode _themeMode = ThemeMode.system;
  // Without flavors: `InspectMode.resolve()` picks developer in debug/profile
  // and production in release. Pass `flavor: '...'` here if your build uses
  // flavors — see the "Using with flavors" section of the README.
  InspectMode _inspectMode = InspectMode.resolve();
  bool _shakeEnabled = true;
  bool _useCustomReportTheme = false;
  int _prodMaxImages = 2;
  ShakeSensitivity _shakeSensitivity = const ShakeSensitivity.medium();
  int _reportCount = 0;

  // Optional custom palette applied to the report sheet when the user
  // toggles "Custom report theme" on. Demonstrates how every field is
  // independently overridable — leave a field null and it falls back to
  // the inherited Material `colorScheme`.
  static const ReportTheme _customReportTheme = ReportTheme(
    backgroundColor: Color(0xFF101218),
    cardColor: Color(0xFF1B1F2A),
    borderColor: Color(0xFF2F3545),
    primaryColor: Color(0xFFFFB020),
    onPrimaryColor: Color(0xFF1A1300),
    textColor: Color(0xFFF5F6FA),
    subtitleColor: Color(0xFFB2B6C2),
    submitButtonColor: Color(0xFFFFB020),
    submitButtonTextColor: Color(0xFF1A1300),
    cancelButtonColor: Color(0xFFFFB020),
  );

  Future<void> _handleReport(ReportPayload payload) async {
    setState(() => _reportCount++);

    // Surface what the package handed us back. Anything missing here is
    // also missing from the report, which is what we want to verify.
    debugPrint(
      '[example] Report received — mode=${payload.mode.name}, '
      'description="${payload.userDescription}", '
      'images=${payload.images.length}, '
      'route=${payload.metadata.currentRoute}, '
      'logLines=${payload.metadata.logs.length}, '
      'networkLines=${payload.metadata.networkLogs.length}, '
      'deviceKeys=${payload.metadata.deviceInfo.keys.length}',
    );

    // Ship it to the local test backend (test_backend/server.dart) so you can
    // confirm the data actually leaves the app and renders on the dashboard.
    // Start the server first; if it isn't running the upload just fails and
    // the SnackBar says so — the report itself was still captured correctly.
    final result = await uploadReport(payload);
    debugPrint(
      result.success
          ? '[example] Uploaded to $backendEndpoint (HTTP ${result.statusCode})'
          : '[example] Upload failed: ${result.error}',
    );

    final messenger = _navKey.currentState?.context;
    if (messenger != null && messenger.mounted) {
      final summary =
          '${payload.mode.name} mode • ${payload.images.length} image(s) • '
          '${payload.metadata.logs.length} log(s) • '
          '${payload.metadata.networkLogs.length} network';
      ScaffoldMessenger.maybeOf(messenger)?.showSnackBar(
        SnackBar(
          backgroundColor: result.success ? null : Colors.red.shade700,
          content: Text(
            result.success
                ? '✓ Uploaded to test backend — $summary'
                : '✗ Upload failed (${result.error}) — is test_backend running? • $summary',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productionConfig = ProductionConfig(
      strings: const ProductionStrings(
        title: 'Send us feedback',
        hintText: 'What happened? Walk us through it.',
        submitLabel: 'Send',
      ),
      maxImages: _prodMaxImages,
      theme: _useCustomReportTheme ? _customReportTheme : null,
    );
    final developerConfig = DeveloperConfig(
      theme: _useCustomReportTheme ? _customReportTheme : null,
    );

    return ShakeContext(
      mode: _inspectMode,
      isShakeEnabled: _shakeEnabled,
      shakeSensitivity: _shakeSensitivity,
      navigatorKey: _navKey,
      productionConfig: productionConfig,
      developerConfig: developerConfig,
      onReportSubmitted: _handleReport,
      child: MaterialApp(
        title: 'shake_context demo',
        navigatorKey: _navKey,
        themeMode: _themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => _HomePage(
            themeMode: _themeMode,
            inspectMode: _inspectMode,
            shakeEnabled: _shakeEnabled,
            useCustomReportTheme: _useCustomReportTheme,
            prodMaxImages: _prodMaxImages,
            shakeSensitivity: _shakeSensitivity,
            reportCount: _reportCount,
            onThemeModeChanged: (m) => setState(() => _themeMode = m),
            onInspectModeChanged: (m) => setState(() => _inspectMode = m),
            onShakeToggled: (v) => setState(() => _shakeEnabled = v),
            onCustomThemeToggled: (v) =>
                setState(() => _useCustomReportTheme = v),
            onProdMaxImagesChanged: (n) => setState(() => _prodMaxImages = n),
            onShakeSensitivityChanged: (s) =>
                setState(() => _shakeSensitivity = s),
          ),
          '/checkout': (_) => const _CheckoutPage(),
        },
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.themeMode,
    required this.inspectMode,
    required this.shakeEnabled,
    required this.useCustomReportTheme,
    required this.prodMaxImages,
    required this.shakeSensitivity,
    required this.reportCount,
    required this.onThemeModeChanged,
    required this.onInspectModeChanged,
    required this.onShakeToggled,
    required this.onCustomThemeToggled,
    required this.onProdMaxImagesChanged,
    required this.onShakeSensitivityChanged,
  });

  final ThemeMode themeMode;
  final InspectMode inspectMode;
  final bool shakeEnabled;
  final bool useCustomReportTheme;
  final int prodMaxImages;
  final ShakeSensitivity shakeSensitivity;
  final int reportCount;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<InspectMode> onInspectModeChanged;
  final ValueChanged<bool> onShakeToggled;
  final ValueChanged<bool> onCustomThemeToggled;
  final ValueChanged<int> onProdMaxImagesChanged;
  final ValueChanged<ShakeSensitivity> onShakeSensitivityChanged;

  IconData get _themeIcon {
    switch (themeMode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.brightness_auto_outlined;
    }
  }

  void _cycleThemeMode() {
    const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
    final next = order[(order.indexOf(themeMode) + 1) % order.length];
    onThemeModeChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('shake_context test harness'),
        actions: [
          IconButton(
            icon: Icon(_themeIcon),
            tooltip: 'Theme mode: ${themeMode.name}',
            onPressed: _cycleThemeMode,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _StatusCard(
            themeMode: themeMode,
            inspectMode: inspectMode,
            shakeEnabled: shakeEnabled,
            useCustomReportTheme: useCustomReportTheme,
            reportCount: reportCount,
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            themeMode: themeMode,
            inspectMode: inspectMode,
            shakeEnabled: shakeEnabled,
            useCustomReportTheme: useCustomReportTheme,
            prodMaxImages: prodMaxImages,
            shakeSensitivity: shakeSensitivity,
            onThemeModeChanged: onThemeModeChanged,
            onInspectModeChanged: onInspectModeChanged,
            onShakeToggled: onShakeToggled,
            onCustomThemeToggled: onCustomThemeToggled,
            onProdMaxImagesChanged: onProdMaxImagesChanged,
            onShakeSensitivityChanged: onShakeSensitivityChanged,
          ),
          const SizedBox(height: 16),
          const _LogsCard(),
          const SizedBox(height: 16),
          const _ErrorsCard(),
          const SizedBox(height: 16),
          const _NetworkCard(),
          const SizedBox(height: 16),
          const _TriggerCard(),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.themeMode,
    required this.inspectMode,
    required this.shakeEnabled,
    required this.useCustomReportTheme,
    required this.reportCount,
  });

  final ThemeMode themeMode;
  final InspectMode inspectMode;
  final bool shakeEnabled;
  final bool useCustomReportTheme;
  final int reportCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Engine state',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.palette_outlined, size: 18),
                  label: Text('Theme: ${themeMode.name}'),
                ),
                Chip(
                  avatar: const Icon(Icons.science_outlined, size: 18),
                  label: Text('Mode: ${inspectMode.name}'),
                ),
                Chip(
                  avatar: Icon(
                    shakeEnabled
                        ? Icons.vibration
                        : Icons.do_not_disturb_on_outlined,
                    size: 18,
                  ),
                  label: Text(shakeEnabled ? 'Shake on' : 'Shake off'),
                ),
                Chip(
                  avatar: const Icon(Icons.brush_outlined, size: 18),
                  label: Text(
                    useCustomReportTheme
                        ? 'Custom sheet theme'
                        : 'Default sheet theme',
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.task_alt_outlined, size: 18),
                  label: Text('Reports submitted: $reportCount'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.themeMode,
    required this.inspectMode,
    required this.shakeEnabled,
    required this.useCustomReportTheme,
    required this.prodMaxImages,
    required this.shakeSensitivity,
    required this.onThemeModeChanged,
    required this.onInspectModeChanged,
    required this.onShakeToggled,
    required this.onCustomThemeToggled,
    required this.onProdMaxImagesChanged,
    required this.onShakeSensitivityChanged,
  });

  final ThemeMode themeMode;
  final InspectMode inspectMode;
  final bool shakeEnabled;
  final bool useCustomReportTheme;
  final int prodMaxImages;
  final ShakeSensitivity shakeSensitivity;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<InspectMode> onInspectModeChanged;
  final ValueChanged<bool> onShakeToggled;
  final ValueChanged<bool> onCustomThemeToggled;
  final ValueChanged<int> onProdMaxImagesChanged;
  final ValueChanged<ShakeSensitivity> onShakeSensitivityChanged;

  static const _low = ShakeSensitivity.low();
  static const _medium = ShakeSensitivity.medium();
  static const _high = ShakeSensitivity.high();

  /// Map a [ShakeSensitivity] back to the preset that produced it, so the
  /// SegmentedButton can highlight the right cell. A custom profile shows
  /// no selection.
  ShakeSensitivity? get _selectedPreset {
    if (shakeSensitivity == _low) return _low;
    if (shakeSensitivity == _medium) return _medium;
    if (shakeSensitivity == _high) return _high;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Theme mode'),
            subtitle: const Text('Light, dark, or follow system'),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (s) => onThemeModeChanged(s.first),
              showSelectedIcon: false,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Inspect mode'),
            subtitle: const Text('Developer overlay vs. production sheet'),
            trailing: SegmentedButton<InspectMode>(
              segments: const [
                ButtonSegment(value: InspectMode.developer, label: Text('Dev')),
                ButtonSegment(
                  value: InspectMode.production,
                  label: Text('Prod'),
                ),
              ],
              selected: {inspectMode},
              onSelectionChanged: (s) => onInspectModeChanged(s.first),
              showSelectedIcon: false,
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Shake to report'),
            subtitle: const Text(
              'Stops accelerometer sampling at runtime when off',
            ),
            value: shakeEnabled,
            onChanged: onShakeToggled,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Shake sensitivity'),
            subtitle: Text(
              _selectedPreset == _low
                  ? 'Low — needs a vigorous shake'
                  : _selectedPreset == _high
                  ? 'High — fires on lighter motion'
                  : _selectedPreset == _medium
                  ? 'Medium — balanced default'
                  : 'Custom profile (threshold '
                        '${shakeSensitivity.threshold.toStringAsFixed(1)}g, '
                        '${shakeSensitivity.minSpikes} spikes)',
            ),
            trailing: SegmentedButton<ShakeSensitivity>(
              segments: const [
                ButtonSegment(value: _low, label: Text('Low')),
                ButtonSegment(value: _medium, label: Text('Med')),
                ButtonSegment(value: _high, label: Text('High')),
              ],
              selected: _selectedPreset == null ? {} : {_selectedPreset!},
              emptySelectionAllowed: true,
              onSelectionChanged: (s) {
                if (s.isNotEmpty) onShakeSensitivityChanged(s.first);
              },
              showSelectedIcon: false,
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.brush_outlined),
            title: const Text('Custom report sheet theme'),
            subtitle: const Text(
              'Applies a ReportTheme to override the report surface colors',
            ),
            value: useCustomReportTheme,
            onChanged: onCustomThemeToggled,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Production image limit'),
            subtitle: const Text(
              'Caps how many images the production sheet will accept',
            ),
            trailing: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1')),
                ButtonSegment(value: 2, label: Text('2')),
                ButtonSegment(value: 4, label: Text('4')),
              ],
              selected: {prodMaxImages},
              onSelectionChanged: (s) => onProdMaxImagesChanged(s.first),
              showSelectedIcon: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogsCard extends StatelessWidget {
  const _LogsCard();

  void _notify(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logs', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Every source the package promises to capture has a button. '
              'Open the overlay after pressing to confirm the line shows up.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.terminal),
                  label: const Text('debugPrint'),
                  onPressed: () {
                    debugPrint(
                      '[example] debugPrint @ ${DateTime.now().toIso8601String()}',
                    );
                    _notify(context, 'debugPrint emitted');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('print (zone)'),
                  onPressed: () {
                    // ignore: avoid_print
                    print('[example] print() line — captured via Zone hook');
                    _notify(context, 'print emitted');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('log.debug'),
                  onPressed: () {
                    ShakeContext.log(
                      'Debug breadcrumb — entered checkout flow',
                      level: LogLevel.debug,
                      source: 'example',
                    );
                    _notify(context, 'log.debug emitted');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.info_outline),
                  label: const Text('log.info'),
                  onPressed: () {
                    ShakeContext.log(
                      'User added item to cart',
                      level: LogLevel.info,
                      source: 'cart',
                    );
                    _notify(context, 'log.info emitted');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.warning_amber_outlined),
                  label: const Text('log.warning'),
                  onPressed: () {
                    ShakeContext.log(
                      'Cache miss — fetched from network',
                      level: LogLevel.warning,
                      source: 'cache',
                    );
                    _notify(context, 'log.warning emitted');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.error_outline),
                  label: const Text('log.error + stack'),
                  onPressed: () {
                    ShakeContext.log(
                      'Failed to parse server response',
                      level: LogLevel.error,
                      source: 'parser',
                      stackTrace: StackTrace.current,
                    );
                    _notify(context, 'log.error emitted');
                  },
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.format_list_numbered),
                  label: const Text('Emit 25 log lines'),
                  onPressed: () {
                    for (var i = 0; i < 25; i++) {
                      ShakeContext.log(
                        'Bulk line #$i',
                        level: LogLevel.values[i % LogLevel.values.length],
                        source: 'stress',
                      );
                    }
                    _notify(context, '25 lines emitted');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorsCard extends StatelessWidget {
  const _ErrorsCard();

  void _notify(BuildContext context, String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Errors', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Verify that FlutterError.onError and PlatformDispatcher.onError '
              'both feed the rolling buffer.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.bolt_outlined),
                  label: const Text('Uncaught async (Future.error)'),
                  onPressed: () {
                    Future<void>.error(
                      StateError('simulated async failure'),
                      StackTrace.current,
                    );
                    _notify(context, 'async error dispatched');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flutter_dash),
                  label: const Text('FlutterError.reportError'),
                  onPressed: () {
                    FlutterError.reportError(
                      FlutterErrorDetails(
                        exception: Exception('simulated framework error'),
                        stack: StackTrace.current,
                        library: 'example',
                        context: ErrorDescription(
                          'manually reported for testing',
                        ),
                      ),
                    );
                    _notify(context, 'framework error dispatched');
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Delayed async error'),
                  onPressed: () {
                    Future.delayed(
                      const Duration(milliseconds: 500),
                      () => throw const FormatException(
                        'delayed format error — see overlay',
                      ),
                    );
                    _notify(context, 'delayed error scheduled');
                  },
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.whatshot_outlined),
                  label: const Text('Error storm (5x mixed)'),
                  onPressed: () {
                    Future<void>.error(ArgumentError('storm #1'));
                    Future<void>.error(
                      RangeError.range(99, 0, 10, 'index', 'storm #2'),
                    );
                    FlutterError.reportError(
                      FlutterErrorDetails(
                        exception: Exception('storm #3 — framework'),
                        stack: StackTrace.current,
                        library: 'example',
                      ),
                    );
                    ShakeContext.log(
                      'storm #4 — logged at error level',
                      level: LogLevel.error,
                      source: 'storm',
                      stackTrace: StackTrace.current,
                    );
                    Future<void>.error(
                      const FakeSocketException('storm #5 — fake socket'),
                    );
                    _notify(context, '5 mixed errors dispatched');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkCard extends StatefulWidget {
  const _NetworkCard();

  @override
  State<_NetworkCard> createState() => _NetworkCardState();
}

class _NetworkCardState extends State<_NetworkCard> {
  static const _baseUrl = 'https://api.example.com';
  final _rand = Random();
  int _inFlight = 0;

  void _notify(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  /// Simulate an HTTP cycle by recording a [NetworkLog] directly. This is
  /// what `ShakeDioInterceptor` does under the hood, so the developer
  /// overlay can't tell the difference.
  Future<void> _simulate({
    required String method,
    required String path,
    required int? status,
    String? body,
    String? error,
    Duration? overrideDuration,
  }) async {
    setState(() => _inFlight++);
    final start = DateTime.now();
    final duration =
        overrideDuration ?? Duration(milliseconds: 40 + _rand.nextInt(180));
    await Future<void>.delayed(duration);

    final responseBody = error == null
        ? (body ?? _defaultBodyForStatus(status))
        : null;

    ShakeContext.recordNetwork(
      NetworkLog(
        method: method,
        url: '$_baseUrl$path',
        statusCode: status,
        durationMs: duration.inMilliseconds,
        requestHeaders: const {
          'Accept': 'application/json',
          'Authorization': 'Bearer [REDACTED]',
        },
        responseHeaders: status == null
            ? null
            : const {'Content-Type': 'application/json'},
        requestBody: method == 'POST'
            ? '{"id": 42, "action": "checkout"}'
            : null,
        responseBody: responseBody,
        error: error,
        timestamp: start,
      ),
    );

    // Mirror the outcome to the log buffer too — handy when scanning the
    // overlay's mixed log feed.
    ShakeContext.log(
      error != null
          ? 'NET $method $path → ERROR $error'
          : 'NET $method $path → $status',
      level: error != null || (status != null && status >= 400)
          ? LogLevel.error
          : LogLevel.info,
      source: 'http',
    );

    if (mounted) setState(() => _inFlight--);
    _notify(
      error != null
          ? '$method $path failed: $error'
          : '$method $path → $status',
    );
  }

  String _defaultBodyForStatus(int? status) {
    switch (status) {
      case 200:
      case 201:
        return '{"ok": true, "id": ${_rand.nextInt(9999)}}';
      case 400:
        return '{"error": "validation_failed", "field": "email"}';
      case 401:
        return '{"error": "unauthorized"}';
      case 404:
        return '{"error": "not_found"}';
      case 500:
        return '{"error": "internal_server_error"}';
      default:
        return '{}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Mock API calls',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (_inFlight > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                Text('$_inFlight in-flight'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Each press records a NetworkLog (the same path '
              'ShakeDioInterceptor uses). Open the overlay to verify the '
              'Network panel.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _netButton(
                  label: 'GET 200',
                  color: Colors.green,
                  onPressed: () =>
                      _simulate(method: 'GET', path: '/users/me', status: 200),
                ),
                _netButton(
                  label: 'POST 201',
                  color: Colors.green,
                  onPressed: () =>
                      _simulate(method: 'POST', path: '/orders', status: 201),
                ),
                _netButton(
                  label: 'GET 400',
                  color: Colors.orange,
                  onPressed: () =>
                      _simulate(method: 'GET', path: '/search?q=', status: 400),
                ),
                _netButton(
                  label: 'GET 401',
                  color: Colors.orange,
                  onPressed: () =>
                      _simulate(method: 'GET', path: '/account', status: 401),
                ),
                _netButton(
                  label: 'GET 404',
                  color: Colors.orange,
                  onPressed: () => _simulate(
                    method: 'GET',
                    path: '/users/9999',
                    status: 404,
                  ),
                ),
                _netButton(
                  label: 'GET 500',
                  color: Colors.red,
                  onPressed: () =>
                      _simulate(method: 'POST', path: '/checkout', status: 500),
                ),
                _netButton(
                  label: 'Timeout (transport err)',
                  color: Colors.red,
                  onPressed: () => _simulate(
                    method: 'GET',
                    path: '/slow',
                    status: null,
                    error: 'Connection timed out after 5000ms',
                    overrideDuration: const Duration(seconds: 1),
                  ),
                ),
                _netButton(
                  label: 'DNS failure',
                  color: Colors.red,
                  onPressed: () => _simulate(
                    method: 'GET',
                    path: '/unknown',
                    status: null,
                    error: 'Failed host lookup: api.does-not-exist.invalid',
                  ),
                ),
                _netButton(
                  label: 'Slow 200 (2s)',
                  color: Colors.blueGrey,
                  onPressed: () => _simulate(
                    method: 'GET',
                    path: '/reports/heavy',
                    status: 200,
                    overrideDuration: const Duration(seconds: 2),
                  ),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.dynamic_feed),
                  label: const Text('Burst (mixed x10)'),
                  onPressed: () async {
                    final outcomes = [200, 201, 400, 401, 404, 500];
                    for (var i = 0; i < 10; i++) {
                      // Fire-and-forget so they overlap in time.
                      unawaited(
                        _simulate(
                          method: i.isEven ? 'GET' : 'POST',
                          path: '/burst/$i',
                          status: i == 7 ? null : outcomes[i % outcomes.length],
                          error: i == 7 ? 'Connection reset by peer' : null,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _netButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _TriggerCard extends StatelessWidget {
  const _TriggerCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open the report',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Shake the device, or use these buttons on a simulator/desktop '
              'where the accelerometer is unreliable.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.feedback_outlined),
                  label: const Text('Open overlay now'),
                  onPressed: () {
                    final ok = ShakeContext.triggerReport(context);
                    if (!ok) {
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not open — already open or no Navigator above ShakeContext.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Open /checkout'),
                  onPressed: () => Navigator.of(context).pushNamed('/checkout'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutPage extends StatelessWidget {
  const _CheckoutPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Shake from here (or use the button) to verify that the '
              'developer overlay shows "Route: /checkout".',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.feedback_outlined),
              label: const Text('Open overlay from /checkout'),
              onPressed: () => ShakeContext.triggerReport(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stand-in for `dart:io`'s `SocketException` — used so the error storm
/// includes a recognisable transport-layer error type without pulling in
/// `dart:io` (which would break web builds of the example).
class FakeSocketException implements Exception {
  const FakeSocketException(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
