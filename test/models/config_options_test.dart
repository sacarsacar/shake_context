// The deprecation back-compat assertions intentionally exercise the
// soft-deprecated `title` / `hintText` / `submitLabel` / `privacyNote` params
// to prove they keep flowing through unchanged.
// ignore_for_file: deprecated_member_use_from_same_package

import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  group('ProductionConfig', () {
    test('defaults are stable and const-constructible', () {
      const a = ProductionConfig();
      const b = ProductionConfig();
      expect(identical(a, b), isTrue);
      expect(a.allowGalleryUpload, isTrue);
      expect(a.allowScreenshotAttachment, isTrue);
      expect(a.title, 'Report an Issue');
      expect(a.strings.title, 'Report an Issue');
    });

    test('equality is value-based', () {
      const a = ProductionConfig(title: 'Send Feedback');
      const b = ProductionConfig(title: 'Send Feedback');
      const c = ProductionConfig(title: 'Other');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('deprecated string params flow into config.strings', () {
      const cfg = ProductionConfig(
        title: 'Send Feedback',
        hintText: 'Tell us more',
        submitLabel: 'Submit',
        privacyNote: 'We only share what you type.',
      );
      expect(cfg.strings.title, 'Send Feedback');
      expect(cfg.strings.hintText, 'Tell us more');
      expect(cfg.strings.submitLabel, 'Submit');
      expect(cfg.strings.privacyNote, 'We only share what you type.');
      // Non-overridden fields still come from ProductionStrings defaults.
      expect(cfg.strings.cancelLabel, 'Cancel');
      expect(cfg.strings.autoBadge, 'Auto');
    });

    test('explicit strings: parameter wins as the canonical surface', () {
      const cfg = ProductionConfig(
        strings: ProductionStrings(
          title: 'Localized title',
          cancelLabel: 'Annuler',
        ),
      );
      expect(cfg.strings.title, 'Localized title');
      expect(cfg.strings.cancelLabel, 'Annuler');
      // The deprecated getter mirrors the same value.
      expect(cfg.title, 'Localized title');
    });

    test('deprecated params override fields from the passed strings', () {
      // Mixing old + new APIs: the deprecated `title` should layer on top of
      // the ProductionStrings provided via `strings:`.
      const cfg = ProductionConfig(
        strings: ProductionStrings(
          title: 'From strings',
          cancelLabel: 'Annuler',
        ),
        title: 'From deprecated param',
      );
      expect(cfg.strings.title, 'From deprecated param');
      // Fields not overridden by the deprecated params keep the strings value.
      expect(cfg.strings.cancelLabel, 'Annuler');
    });

    test('two configs reach equality regardless of which API set the title',
        () {
      const viaDeprecated = ProductionConfig(title: 'Send Feedback');
      const viaStrings = ProductionConfig(
        strings: ProductionStrings(title: 'Send Feedback'),
      );
      expect(viaDeprecated, equals(viaStrings));
      expect(viaDeprecated.hashCode, equals(viaStrings.hashCode));
    });

    test('copyWith overrides only provided fields', () {
      const a = ProductionConfig();
      final b = a.copyWith(allowGalleryUpload: false);
      expect(b.allowGalleryUpload, isFalse);
      expect(b.title, a.title);
      expect(b.hintText, a.hintText);
    });

    test('copyWith(title: …) still threads through to strings', () {
      const a = ProductionConfig();
      final b = a.copyWith(title: 'Renamed');
      expect(b.strings.title, 'Renamed');
      // Other strings stay at their defaults.
      expect(b.strings.cancelLabel, 'Cancel');
    });

    test('copyWith(strings: …) replaces the whole copy block', () {
      const a = ProductionConfig(title: 'Old title');
      final b = a.copyWith(
        strings: const ProductionStrings(title: 'New title'),
      );
      expect(b.strings.title, 'New title');
    });

    test('screenshotPixelRatio defaults to 3.0 and is overridable', () {
      const a = ProductionConfig();
      expect(a.screenshotPixelRatio, 3.0);
      final b = a.copyWith(screenshotPixelRatio: 1.5);
      expect(b.screenshotPixelRatio, 1.5);
      expect(b.title, a.title);
    });

    test('screenshotPixelRatio participates in equality', () {
      const a = ProductionConfig(screenshotPixelRatio: 2.0);
      const b = ProductionConfig(screenshotPixelRatio: 2.0);
      const c = ProductionConfig(screenshotPixelRatio: 3.0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('non-positive screenshotPixelRatio is rejected', () {
      expect(
        () => ProductionConfig(screenshotPixelRatio: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ProductionConfig(screenshotPixelRatio: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('DeveloperConfig', () {
    test('defaults capture everything with bounded log/network buffers', () {
      const cfg = DeveloperConfig();
      expect(cfg.captureRoute, isTrue);
      expect(cfg.captureDeviceInfo, isTrue);
      expect(cfg.captureConsoleLogs, isTrue);
      expect(cfg.captureNetworkLogs, isTrue);
      expect(cfg.captureScreenshot, isTrue);
      expect(cfg.logBufferSize, 200);
      expect(cfg.networkBufferSize, 50);
    });

    test('equality is value-based', () {
      const a = DeveloperConfig(logBufferSize: 50);
      const b = DeveloperConfig(logBufferSize: 50);
      const c = DeveloperConfig(logBufferSize: 250);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith overrides only provided fields', () {
      const a = DeveloperConfig();
      final b = a.copyWith(
        captureScreenshot: false,
        captureNetworkLogs: false,
        networkBufferSize: 10,
      );
      expect(b.captureScreenshot, isFalse);
      expect(b.captureNetworkLogs, isFalse);
      expect(b.networkBufferSize, 10);
      expect(b.captureRoute, a.captureRoute);
      expect(b.logBufferSize, a.logBufferSize);
    });

    test('screenshotPixelRatio defaults to 3.0 and is overridable', () {
      const a = DeveloperConfig();
      expect(a.screenshotPixelRatio, 3.0);
      final b = a.copyWith(screenshotPixelRatio: 2.0);
      expect(b.screenshotPixelRatio, 2.0);
      expect(b.captureScreenshot, a.captureScreenshot);
    });

    test('screenshotPixelRatio participates in equality', () {
      const a = DeveloperConfig(screenshotPixelRatio: 2.0);
      const b = DeveloperConfig(screenshotPixelRatio: 2.0);
      const c = DeveloperConfig(screenshotPixelRatio: 3.0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('non-positive screenshotPixelRatio is rejected', () {
      expect(
        () => DeveloperConfig(screenshotPixelRatio: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
