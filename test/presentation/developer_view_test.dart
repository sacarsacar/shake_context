import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';
import 'package:shake_context/src/presentation/developer_view.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('submit emits developer-mode payload with metadata + screenshot',
      (tester) async {
    ReportPayload? captured;
    final shot = Uint8List.fromList([1, 2, 3]);
    final ts = DateTime.utc(2026, 5, 18, 12, 30);
    final meta = ReportMetadata(
      currentRoute: '/checkout',
      deviceInfo: const {'model': 'Pixel 11', 'os': 'Android 17'},
      logs: [
        LogEntry(message: 'tap', source: 'debugPrint', timestamp: ts),
        LogEntry(
          message: 'crash',
          level: LogLevel.error,
          source: 'FlutterError',
          timestamp: ts,
        ),
      ],
      networkLogs: [
        NetworkLog(
          method: 'GET',
          url: 'https://api.test/cart',
          statusCode: 500,
          durationMs: 88,
          timestamp: ts,
        ),
      ],
      timestamp: ts,
    );

    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(),
        metadata: meta,
        screenshot: shot,
        onSubmit: (p) async => captured = p,
      ),
    ));

    expect(find.text('/checkout'), findsOneWidget);
    expect(find.textContaining('Pixel 11'), findsOneWidget);
    expect(find.textContaining('tap'), findsWidgets);
    expect(find.textContaining('500 GET'), findsOneWidget);

    final sendButton = find.widgetWithText(FilledButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.pumpAndSettle();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.mode, InspectMode.developer);
    expect(captured!.metadata.currentRoute, '/checkout');
    expect(captured!.metadata.deviceInfo['model'], 'Pixel 11');
    expect(captured!.images, [shot]);
  });

  testWidgets('shows placeholder text when no screenshot or logs are provided',
      (tester) async {
    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(),
        metadata: ReportMetadata.empty(),
        onSubmit: (_) async {},
      ),
    ));

    expect(find.text('No screenshot captured'), findsOneWidget);
    expect(find.text('No logs captured'), findsOneWidget);
    expect(find.text('(unknown)'), findsOneWidget);
    expect(find.text('(unavailable)'), findsOneWidget);
  });

  testWidgets('submission failure shows SnackBar and keeps sheet open',
      (tester) async {
    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(),
        metadata: ReportMetadata.empty(),
        onSubmit: (_) async {
          throw StateError('network down');
        },
      ),
    ));

    final sendButton = find.widgetWithText(FilledButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.pumpAndSettle();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('network down'), findsOneWidget);
    // Sheet stays open — the Send button is still there for retry.
    expect(sendButton, findsOneWidget);
  });

  testWidgets('extras flow through into the emitted payload',
      (tester) async {
    ReportPayload? captured;
    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(),
        metadata: ReportMetadata.empty(),
        extras: const {'installationId': 'abc-123', 'flavor': 'dev'},
        onSubmit: (p) async => captured = p,
      ),
    ));

    final sendButton = find.widgetWithText(FilledButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.pumpAndSettle();
    await tester.tap(sendButton);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.extras, {'installationId': 'abc-123', 'flavor': 'dev'});
  });

  testWidgets('hides diagnostic rows that the config disables', (tester) async {
    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(
          captureRoute: false,
          captureDeviceInfo: false,
          captureConsoleLogs: false,
          captureNetworkLogs: false,
          captureScreenshot: false,
        ),
        metadata: ReportMetadata.empty(),
        onSubmit: (_) async {},
      ),
    ));

    expect(find.text('Route'), findsNothing);
    expect(find.text('Device'), findsNothing);
    expect(find.text('Recent logs'), findsNothing);
    expect(find.text('Network'), findsNothing);
    expect(find.text('No screenshot captured'), findsNothing);
  });

  testWidgets('ScreenshotEditor mounts with pen-only annotation controls',
      (tester) async {
    final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

    await tester.pumpWidget(MaterialApp(
      home: ScreenshotEditor(bytes: bytes),
    ));
    await tester.pump();

    expect(find.text('Annotate'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Stroke'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Clear all'), findsOneWidget);
    expect(find.text('Drag on the screenshot to draw'), findsOneWidget);
  });

  testWidgets('log panel filters by search query', (tester) async {
    final ts = DateTime.utc(2026, 5, 18, 12, 30);
    final meta = ReportMetadata(
      logs: [
        LogEntry(message: 'cart updated', source: 'print', timestamp: ts),
        LogEntry(
            message: 'checkout started', source: 'debugPrint', timestamp: ts),
        LogEntry(
            message: 'payment failed',
            level: LogLevel.error,
            source: 'FlutterError',
            timestamp: ts),
      ],
      timestamp: ts,
    );

    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(),
        metadata: meta,
        onSubmit: (_) async {},
      ),
    ));

    expect(find.textContaining('cart updated'), findsOneWidget);
    expect(find.textContaining('payment failed'), findsOneWidget);

    final searchField = find.widgetWithText(TextField, 'Search logs…');
    await tester.enterText(searchField, 'payment');
    await tester.pumpAndSettle();

    expect(find.textContaining('payment failed'), findsOneWidget);
    expect(find.textContaining('cart updated'), findsNothing);
  });

  testWidgets('log panel level chip filters out an entire level',
      (tester) async {
    final ts = DateTime.utc(2026, 5, 18, 12, 30);
    final meta = ReportMetadata(
      logs: [
        LogEntry(message: 'normal line', source: 'print', timestamp: ts),
        LogEntry(
            message: 'boom',
            level: LogLevel.error,
            source: 'FlutterError',
            timestamp: ts),
      ],
      timestamp: ts,
    );

    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(),
        metadata: meta,
        onSubmit: (_) async {},
      ),
    ));

    // Default: both visible.
    expect(find.textContaining('normal line'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);

    // Tap the 'info' chip to deselect — only error should remain.
    final infoChip = find.widgetWithText(FilterChip, 'info');
    await tester.ensureVisible(infoChip);
    await tester.pumpAndSettle();
    await tester.tap(infoChip);
    await tester.pumpAndSettle();
    expect(find.textContaining('normal line'), findsNothing);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('network panel filters by failed-only', (tester) async {
    final ts = DateTime.utc(2026, 5, 18, 12, 30);
    final meta = ReportMetadata(
      networkLogs: [
        NetworkLog(
            method: 'GET',
            url: 'https://api.test/ok',
            statusCode: 200,
            timestamp: ts),
        NetworkLog(
            method: 'POST',
            url: 'https://api.test/boom',
            statusCode: 500,
            timestamp: ts),
      ],
      timestamp: ts,
    );

    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(),
        metadata: meta,
        onSubmit: (_) async {},
      ),
    ));

    final failedChip = find.widgetWithText(FilterChip, 'failed');
    await tester.ensureVisible(failedChip);
    await tester.pumpAndSettle();

    expect(find.textContaining('api.test/ok'), findsOneWidget);
    expect(find.textContaining('api.test/boom'), findsOneWidget);

    await tester.tap(failedChip);
    await tester.pumpAndSettle();

    expect(find.textContaining('api.test/ok'), findsNothing);
    expect(find.textContaining('api.test/boom'), findsOneWidget);
  });

  testWidgets('previous session panels appear when recovered data exists',
      (tester) async {
    // Local DateTime so the human-readable format is deterministic on any
    // test runner timezone.
    final priorTs = DateTime(2026, 5, 18, 9);
    final meta = ReportMetadata(
      logs: [LogEntry(message: 'current', timestamp: DateTime(2026, 5, 19))],
      previousSessionLogs: [
        LogEntry(
            message: 'last-run boot', source: 'debugPrint', timestamp: priorTs),
      ],
      previousSessionNetwork: [
        NetworkLog(
            method: 'GET',
            url: 'https://api.test/prior',
            statusCode: 500,
            timestamp: priorTs),
      ],
      previousSessionStartedAt: priorTs,
    );

    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(),
        metadata: meta,
        onSubmit: (_) async {},
      ),
    ));

    expect(find.textContaining('Previous session — logs'), findsOneWidget);
    expect(find.textContaining('Previous session — network'), findsOneWidget);
    // The header should embed the prior-session start timestamp in the
    // human-readable form produced by _formatTimestamp(..., includeSeconds: false).
    expect(find.textContaining('May 18, 2026 · 9:00 AM'), findsWidgets);
  });

  testWidgets('honors ReportTheme overrides on the Send button', (tester) async {
    const customBg = Color(0xFFFFEB3B);
    const customFg = Color(0xFF222222);

    await tester.pumpWidget(_wrap(
      DeveloperView(
        config: const DeveloperConfig(
          theme: ReportTheme(
            submitButtonColor: customBg,
            submitButtonTextColor: customFg,
          ),
        ),
        metadata: ReportMetadata.empty(),
        onSubmit: (_) async {},
      ),
    ));

    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send'),
    );
    expect(sendButton.style?.backgroundColor?.resolve({}), customBg);
    expect(sendButton.style?.foregroundColor?.resolve({}), customFg);
  });
}
