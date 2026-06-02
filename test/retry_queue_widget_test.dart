import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

/// Static-API surface coverage for `ShakeContext.queuedReportCount`,
/// `replayQueuedReports`, `clearQueuedReports`, and the callback
/// registration that happens on widget mount.
///
/// File-system operations inside `testWidgets` need `tester.runAsync(...)`
/// because the default fake clock won't progress real `Directory.list()` /
/// `File.writeAsString` futures. The end-to-end "submission failure → file
/// lands on disk" path is exercised by the unit tests in
/// `test/core/retry_queue_test.dart` (which drive `RetryQueue.enqueue`
/// directly under the regular `test(...)` runner where real-time async
/// works without ceremony).
void main() {
  late Directory dir;
  late RetryQueueStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shake_q_widget_');
    store = RetryQueueStore.forDirectory(dir);
    RetryQueue.debugSetInstance(RetryQueue(store: store));
  });

  tearDown(() async {
    RetryQueue.debugSetInstance(null);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Widget app({required ReportSubmittedCallback onSubmit}) => MaterialApp(
        home: ShakeContext(
          mode: InspectMode.production,
          // Skip the real accelerometer subscription — without an injected
          // stream the platform channel never resolves in unit tests.
          isShakeEnabled: false,
          onReportSubmitted: onSubmit,
          child: const Scaffold(body: SizedBox.shrink()),
        ),
      );

  testWidgets('queuedReportCount reflects the on-disk queue size',
      (tester) async {
    await tester.pumpWidget(app(onSubmit: (_) async {}));

    await tester.runAsync(() async {
      expect(await ShakeContext.queuedReportCount(), 0);
      await store.write(ReportPayload(
        mode: InspectMode.production,
        userDescription: 'one',
      ));
      expect(await ShakeContext.queuedReportCount(), 1);
      await store.write(ReportPayload(
        mode: InspectMode.production,
        userDescription: 'two',
      ));
      expect(await ShakeContext.queuedReportCount(), 2);
    });
  });

  testWidgets('queuedReportCount returns 0 when the queue is disabled',
      (tester) async {
    RetryQueue.debugSetInstance(null);
    await tester.runAsync(() async {
      expect(await ShakeContext.queuedReportCount(), 0);
    });
  });

  testWidgets('clearQueuedReports drains the queue', (tester) async {
    await tester.runAsync(() async {
      await store.write(ReportPayload(
        mode: InspectMode.production,
        userDescription: 'one',
      ));
      await store.write(ReportPayload(
        mode: InspectMode.production,
        userDescription: 'two',
      ));
      expect(await ShakeContext.queuedReportCount(), 2);

      await ShakeContext.clearQueuedReports();
      expect(await ShakeContext.queuedReportCount(), 0);
    });
  });

  testWidgets('clearQueuedReports is a no-op when the queue is disabled',
      (tester) async {
    RetryQueue.debugSetInstance(null);
    await tester.runAsync(() async {
      // Must not throw.
      await ShakeContext.clearQueuedReports();
    });
  });

  testWidgets(
      'replayQueuedReports flushes queued payloads through the mounted widget callback',
      (tester) async {
    final delivered = <String>[];

    await tester.runAsync(() async {
      await store.write(ReportPayload(
        mode: InspectMode.production,
        userDescription: 'pre-seeded',
      ));
    });

    await tester.pumpWidget(app(onSubmit: (payload) async {
      delivered.add(payload.userDescription);
    }));
    await tester.pump();

    await tester.runAsync(() async {
      final n = await ShakeContext.replayQueuedReports();
      expect(n, 1);
      expect(delivered, ['pre-seeded']);
      expect(await ShakeContext.queuedReportCount(), 0);
    });
  });

  testWidgets('replayQueuedReports returns 0 with no widget callback registered',
      (tester) async {
    await tester.runAsync(() async {
      await store.write(ReportPayload(
        mode: InspectMode.production,
        userDescription: 'no-handler',
      ));
      expect(await ShakeContext.replayQueuedReports(), 0);
      expect(await ShakeContext.queuedReportCount(), 1);
    });
  });

  testWidgets('replayQueuedReports returns 0 when the queue is disabled',
      (tester) async {
    RetryQueue.debugSetInstance(null);
    await tester.runAsync(() async {
      expect(await ShakeContext.replayQueuedReports(), 0);
    });
  });

  testWidgets('widget disposal clears the registered callback', (tester) async {
    await tester.pumpWidget(app(onSubmit: (_) async {}));
    await tester.pump();
    // Tear down the widget.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.runAsync(() async {
      await store.write(ReportPayload(
        mode: InspectMode.production,
        userDescription: 'orphaned',
      ));
      // No callback registered after dispose → replay can't consume it.
      expect(await ShakeContext.replayQueuedReports(), 0);
      expect(await ShakeContext.queuedReportCount(), 1);
    });
  });

  testWidgets('didUpdateWidget rewires the callback when onReportSubmitted changes',
      (tester) async {
    final calls = <String>[];

    Future<void> first(ReportPayload p) async {
      calls.add('first:${p.userDescription}');
    }

    Future<void> second(ReportPayload p) async {
      calls.add('second:${p.userDescription}');
    }

    await tester.pumpWidget(app(onSubmit: first));
    await tester.pump();
    await tester.pumpWidget(app(onSubmit: second));
    await tester.pump();

    await tester.runAsync(() async {
      await store.write(ReportPayload(
        mode: InspectMode.production,
        userDescription: 'after-rewire',
      ));
      await ShakeContext.replayQueuedReports();
    });
    expect(calls, ['second:after-rewire']);
  });
}
