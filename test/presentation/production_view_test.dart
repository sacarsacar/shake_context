import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';
import 'package:shake_context/src/presentation/production_view.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('submit emits payload with typed description and production mode',
      (tester) async {
    ReportPayload? captured;

    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(),
        onSubmit: (p) async => captured = p,
      ),
    ));

    await tester.enterText(find.byType(TextField), 'It broke when I tapped X');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.mode, InspectMode.production);
    expect(captured!.userDescription, 'It broke when I tapped X');
    expect(captured!.images, isEmpty);
  });

  testWidgets('submission failure shows generic SnackBar and keeps sheet open',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(),
        onSubmit: (_) async {
          throw StateError('500 boom');
        },
      ),
    ));

    await tester.enterText(find.byType(TextField), 'still broken');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    // Production users see a generic message — the raw error stays internal.
    expect(find.text("Couldn't send your report. Please try again."),
        findsOneWidget);
    expect(find.textContaining('500 boom'), findsNothing);
    // The typed description is preserved for retry.
    expect(find.text('still broken'), findsOneWidget);
  });

  testWidgets('extras flow through into the emitted payload',
      (tester) async {
    ReportPayload? captured;
    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(),
        extras: const {'installationId': 'xyz-789'},
        onSubmit: (p) async => captured = p,
      ),
    ));

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.extras, {'installationId': 'xyz-789'});
  });

  testWidgets('attaches the initial screenshot when allowed by config',
      (tester) async {
    ReportPayload? captured;
    final shot = Uint8List.fromList([1, 2, 3]);

    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(),
        initialScreenshot: shot,
        onSubmit: (p) async => captured = p,
      ),
    ));

    await tester.ensureVisible(find.text('Send'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(captured!.images, hasLength(1));
    expect(captured!.images.first, shot);
  });

  testWidgets('user can remove the attached screenshot before sending',
      (tester) async {
    ReportPayload? captured;
    final shot = Uint8List.fromList([1, 2, 3]);

    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(),
        initialScreenshot: shot,
        onSubmit: (p) async => captured = p,
      ),
    ));

    await tester.tap(find.byTooltip('Remove image'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(captured!.images, isEmpty);
  });

  testWidgets('Add image button is hidden when onPickImage is null',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(),
        onSubmit: (_) async {},
      ),
    ));

    expect(find.text('Add image'), findsNothing);
  });

  testWidgets('Add image button is hidden when allowGalleryUpload is false',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(allowGalleryUpload: false),
        onPickImage: () async => Uint8List.fromList([9]),
        onSubmit: (_) async {},
      ),
    ));

    expect(find.text('Add image'), findsNothing);
  });

  testWidgets('Add image button appends an image when onPickImage returns bytes',
      (tester) async {
    ReportPayload? captured;
    final picked = Uint8List.fromList([9, 9, 9]);

    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(),
        onPickImage: () async => picked,
        onSubmit: (p) async => captured = p,
      ),
    ));

    await tester.tap(find.text('Add image'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Send'));
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(captured!.images, hasLength(1));
    expect(captured!.images.first, picked);
  });

  testWidgets('respects custom labels from ProductionConfig', (tester) async {
    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(
          // ignore: deprecated_member_use
          title: 'Send Feedback',
          // ignore: deprecated_member_use
          submitLabel: 'Submit it',
          // ignore: deprecated_member_use
          privacyNote: 'Only what you type is shared.',
        ),
        onSubmit: (_) async {},
      ),
    ));

    expect(find.text('Send Feedback'), findsOneWidget);
    expect(find.text('Submit it'), findsOneWidget);
    expect(find.text('Only what you type is shared.'), findsOneWidget);
  });

  testWidgets('renders every custom string from ProductionStrings',
      (tester) async {
    const strings = ProductionStrings(
      title: 'Localized title',
      hintText: 'Localized hint',
      submitLabel: 'Localized submit',
      cancelLabel: 'Localized cancel',
      privacyNote: 'Localized privacy line.',
      headerSubtitle: 'Localized subtitle',
      descriptionPrompt: 'Localized prompt',
      attachmentsLabel: 'Localized attachments',
      addImage: 'Localized add image',
      addAttachmentHint: 'Localized add-attachment hint.',
      sentWithReport: 'Localized sent-with-report heading',
      timeLabel: 'Localized time',
    );

    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(strings: strings),
        // Provide a picker so the empty attachments slot + add-image button
        // both render (the early-return collapses the section otherwise).
        onPickImage: () async => null,
        onSubmit: (_) async {},
      ),
    ));

    // Header
    expect(find.text('Localized title'), findsOneWidget);
    expect(find.text('Localized subtitle'), findsOneWidget);
    // Description
    expect(find.text('Localized prompt'), findsOneWidget);
    expect(find.text('Localized hint'), findsOneWidget);
    // Attachments header + empty slot + add button
    expect(find.textContaining('Localized attachments'), findsOneWidget);
    expect(find.text('Localized add image'), findsOneWidget);
    expect(find.text('Localized add-attachment hint.'), findsOneWidget);
    // Diagnostics card
    expect(find.text('Localized sent-with-report heading'), findsOneWidget);
    expect(find.text('Localized time'), findsOneWidget);
    // Privacy note
    expect(find.text('Localized privacy line.'), findsOneWidget);
    // Action bar
    expect(find.text('Localized cancel'), findsOneWidget);
    expect(find.text('Localized submit'), findsOneWidget);
  });

  testWidgets('uses localized SnackBar message on submission failure',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(
          strings: ProductionStrings(
            submissionFailedMessage: 'Échec de l\'envoi du rapport.',
          ),
        ),
        onSubmit: (_) async {
          throw StateError('500 boom');
        },
      ),
    ));

    await tester.enterText(find.byType(TextField), 'still broken');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text("Échec de l'envoi du rapport."), findsOneWidget);
    expect(find.text("Couldn't send your report. Please try again."),
        findsNothing);
  });

  testWidgets('honors ReportTheme overrides on the submit button',
      (tester) async {
    const customBg = Color(0xFF7C4DFF);
    const customFg = Color(0xFFFFFFFF);

    await tester.pumpWidget(_wrap(
      ProductionView(
        config: const ProductionConfig(
          submitLabel: 'Send it',
          theme: ReportTheme(
            submitButtonColor: customBg,
            submitButtonTextColor: customFg,
          ),
        ),
        onSubmit: (_) async {},
      ),
    ));

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Send it'),
    );
    expect(button.style?.backgroundColor?.resolve({}), customBg);
    expect(button.style?.foregroundColor?.resolve({}), customFg);
  });
}
