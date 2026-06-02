import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  group('ProductionStrings', () {
    test('defaults match the historically shipped English copy', () {
      const s = ProductionStrings();
      expect(s.title, 'Report an Issue');
      expect(s.hintText, 'What went wrong? Describe it here...');
      expect(s.submitLabel, 'Send');
      expect(s.cancelLabel, 'Cancel');
      expect(
        s.privacyNote,
        'We include your device model and the time of the report to help us reproduce the issue.',
      );
      expect(s.headerSubtitle, "We'll read every word.");
      expect(s.descriptionPrompt, 'What happened?');
      expect(s.attachmentsLabel, 'Attachments');
      expect(s.addImage, 'Add image');
      expect(s.limitReached, 'Limit reached');
      expect(s.noAttachments, 'No attachments.');
      expect(s.addAttachmentHint,
          'Add a screenshot to help us understand the issue.');
      expect(s.sentWithReport, 'Sent with your report');
      expect(s.timeLabel, 'Time');
      expect(s.deviceLabel, 'Device');
      expect(s.resolvingDeviceInfo, 'Resolving device info…');
      expect(s.showDetails, 'Show details');
      expect(s.hideDetails, 'Hide details');
      expect(s.dismissTooltip, 'Dismiss');
      expect(s.removeImageTooltip, 'Remove image');
      expect(s.annotateTooltip, 'Annotate');
      expect(s.tapToView, 'Tap to view');
      expect(s.autoBadge, 'Auto');
      expect(s.submissionFailedMessage,
          "Couldn't send your report. Please try again.");
    });

    test('is const-constructible and canonicalised', () {
      const a = ProductionStrings();
      const b = ProductionStrings();
      expect(identical(a, b), isTrue);
    });

    test('copyWith overrides only the provided fields', () {
      const a = ProductionStrings();
      final b = a.copyWith(title: 'Signaler un bug', submitLabel: 'Envoyer');
      expect(b.title, 'Signaler un bug');
      expect(b.submitLabel, 'Envoyer');
      expect(b.hintText, a.hintText);
      expect(b.privacyNote, a.privacyNote);
      expect(b.cancelLabel, a.cancelLabel);
      expect(b.autoBadge, a.autoBadge);
    });

    test('equality and hashCode are value-based across every field', () {
      const a = ProductionStrings(title: 'Foo', removeImageTooltip: 'Retirer');
      const b = ProductionStrings(title: 'Foo', removeImageTooltip: 'Retirer');
      const c = ProductionStrings(title: 'Foo', removeImageTooltip: 'Different');
      const d = ProductionStrings(title: 'Bar', removeImageTooltip: 'Retirer');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });

    test('identical objects compare equal via the short-circuit', () {
      const s = ProductionStrings(title: 'X');
      expect(s == s, isTrue);
    });
  });
}
