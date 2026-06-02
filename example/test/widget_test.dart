import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('example app boots into the home page', (tester) async {
    await tester.pumpWidget(const ShakeContextExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('shake_context demo'), findsOneWidget);
    expect(find.text('Trigger a fake bug (debugPrint)'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('settings toggle flips the shake-detection status line',
      (tester) async {
    await tester.pumpWidget(const ShakeContextExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Shake detection is ON.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.text('Shake detection is OFF — turn it back on in Settings.'),
      findsOneWidget,
    );
  });
}
