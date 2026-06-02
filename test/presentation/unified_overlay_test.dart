import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';
import 'package:shake_context/src/presentation/developer_view.dart';
import 'package:shake_context/src/presentation/production_view.dart';
import 'package:shake_context/src/presentation/unified_overlay.dart';

void main() {
  Future<void> pumpAndOpen(WidgetTester tester, InspectMode mode) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => UnifiedOverlay.show(
                context: ctx,
                mode: mode,
                productionConfig: const ProductionConfig(),
                developerConfig: const DeveloperConfig(),
                onSubmit: (_) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('developer mode opens DeveloperView', (tester) async {
    await pumpAndOpen(tester, InspectMode.developer);
    expect(find.byType(DeveloperView), findsOneWidget);
    expect(find.byType(ProductionView), findsNothing);
  });

  testWidgets('production mode opens ProductionView', (tester) async {
    await pumpAndOpen(tester, InspectMode.production);
    expect(find.byType(ProductionView), findsOneWidget);
    expect(find.byType(DeveloperView), findsNothing);
  });

  testWidgets('sheet closes after successful submission', (tester) async {
    ReportPayload? captured;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => UnifiedOverlay.show(
                context: ctx,
                mode: InspectMode.production,
                productionConfig: const ProductionConfig(),
                developerConfig: const DeveloperConfig(),
                onSubmit: (p) async => captured = p,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(ProductionView), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(find.byType(ProductionView), findsNothing);
  });
}
