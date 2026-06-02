import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shake_context/shake_context.dart';
import 'package:shake_context/src/core/shake_listener.dart';
import 'package:shake_context/src/presentation/developer_view.dart';
import 'package:shake_context/src/presentation/production_view.dart';

void main() {
  late StreamController<AccelerometerEvent> stream;

  setUp(() {
    stream = StreamController<AccelerometerEvent>.broadcast();
    ShakeListener.streamFactoryOverride = () => stream.stream;
  });

  tearDown(() async {
    ShakeListener.streamFactoryOverride = null;
    if (!stream.isClosed) await stream.close();
  });

  testWidgets('renders child unchanged in both modes', (tester) async {
    Future<void> noop(ReportPayload _) async {}

    for (final mode in InspectMode.values) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ShakeContext(
            mode: mode,
            onReportSubmitted: noop,
            child: const Text('hi'),
          ),
        ),
      );
      expect(find.text('hi'), findsOneWidget);
    }
  });

  testWidgets('respects isShakeEnabled flips without crashing', (tester) async {
    Future<void> noop(ReportPayload _) async {}

    Widget build({required bool enabled}) => Directionality(
          textDirection: TextDirection.ltr,
          child: ShakeContext(
            mode: InspectMode.production,
            isShakeEnabled: enabled,
            onReportSubmitted: noop,
            child: const Text('hi'),
          ),
        );

    await tester.pumpWidget(build(enabled: true));
    await tester.pumpWidget(build(enabled: false));
    await tester.pumpWidget(build(enabled: true));
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('fires onShakeDetected when accelerometer reports a shake',
      (tester) async {
    Future<void> noop(ReportPayload _) async {}
    var shakes = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ShakeContext(
          mode: InspectMode.developer,
          onReportSubmitted: noop,
          onShakeDetected: () => shakes++,
          child: const Text('hi'),
        ),
      ),
    );

    // Emit three above-threshold spikes back-to-back. With default tuning
    // (>= 3 spikes within 500 ms) this should trigger exactly one shake.
    for (var i = 0; i < 3; i++) {
      stream.add(AccelerometerEvent(30, 0, 0, DateTime.now()));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(shakes, 1);
  });

  testWidgets('does not fire when isShakeEnabled is false', (tester) async {
    Future<void> noop(ReportPayload _) async {}
    var shakes = 0;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ShakeContext(
          mode: InspectMode.developer,
          isShakeEnabled: false,
          onReportSubmitted: noop,
          onShakeDetected: () => shakes++,
          child: const Text('hi'),
        ),
      ),
    );

    for (var i = 0; i < 5; i++) {
      stream.add(AccelerometerEvent(30, 0, 0, DateTime.now()));
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(shakes, 0);
  });

  Future<void> shakeThreeTimes(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      stream.add(AccelerometerEvent(30, 0, 0, DateTime.now()));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('shake opens DeveloperView in developer mode', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShakeContext(
        mode: InspectMode.developer,
        onReportSubmitted: (_) async {},
        child: const Scaffold(body: SizedBox.shrink()),
      ),
    ));

    await shakeThreeTimes(tester);
    expect(find.byType(DeveloperView), findsOneWidget);
  });

  testWidgets('shake opens ProductionView in production mode', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShakeContext(
        mode: InspectMode.production,
        onReportSubmitted: (_) async {},
        child: const Scaffold(body: SizedBox.shrink()),
      ),
    ));

    await shakeThreeTimes(tester);
    expect(find.byType(ProductionView), findsOneWidget);
  });

  testWidgets('navigatorKey placement above MaterialApp also opens the overlay',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(ShakeContext(
      mode: InspectMode.production,
      navigatorKey: navKey,
      onReportSubmitted: (_) async {},
      child: MaterialApp(
        navigatorKey: navKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    ));

    await shakeThreeTimes(tester);
    expect(find.byType(ProductionView), findsOneWidget);
  });

  testWidgets('shake while a sheet is open does not stack a second overlay',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShakeContext(
        mode: InspectMode.developer,
        onReportSubmitted: (_) async {},
        child: const Scaffold(body: SizedBox.shrink()),
      ),
    ));

    await shakeThreeTimes(tester);
    expect(find.byType(DeveloperView), findsOneWidget);

    // Second shake while the sheet is still up — should be ignored.
    await shakeThreeTimes(tester);
    expect(find.byType(DeveloperView), findsOneWidget);

    // Dismiss the sheet, then shake again — listener resumes and opens it.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(DeveloperView), findsNothing);

    await shakeThreeTimes(tester);
    expect(find.byType(DeveloperView), findsOneWidget);
  });

  testWidgets('shake with no Navigator above just logs and stays silent',
      (tester) async {
    // No MaterialApp, no navigatorKey — overlay launch should be skipped.
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ShakeContext(
        mode: InspectMode.production,
        onReportSubmitted: (_) async {},
        child: const Text('hi'),
      ),
    ));

    await shakeThreeTimes(tester);
    expect(find.byType(ProductionView), findsNothing);
    expect(find.byType(DeveloperView), findsNothing);
    expect(find.text('hi'), findsOneWidget);
  });

  testWidgets('ShakeContext.triggerReport opens the overlay programmatically',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ShakeContext(
        mode: InspectMode.developer,
        onReportSubmitted: (_) async {},
        child: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ShakeContext.triggerReport(context),
                child: const Text('Report bug'),
              ),
            ),
          );
        }),
      ),
    ));

    expect(find.byType(DeveloperView), findsNothing);
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();
    expect(find.byType(DeveloperView), findsOneWidget);
  });

  testWidgets('ShakeContext.triggerReport returns false without ancestor',
      (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  result = ShakeContext.triggerReport(context),
              child: const Text('Report bug'),
            ),
          ),
        );
      }),
    ));

    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
