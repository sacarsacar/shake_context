import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  group('ReportTheme', () {
    test('defaults leave every slot null so consumers can override piecemeal',
        () {
      const t = ReportTheme();
      expect(t.backgroundColor, isNull);
      expect(t.cardColor, isNull);
      expect(t.borderColor, isNull);
      expect(t.primaryColor, isNull);
      expect(t.onPrimaryColor, isNull);
      expect(t.textColor, isNull);
      expect(t.subtitleColor, isNull);
      expect(t.submitButtonColor, isNull);
      expect(t.submitButtonTextColor, isNull);
      expect(t.cancelButtonColor, isNull);
    });

    test('equality and hashCode are value-based', () {
      const a = ReportTheme(
        primaryColor: Colors.red,
        textColor: Colors.black,
      );
      const b = ReportTheme(
        primaryColor: Colors.red,
        textColor: Colors.black,
      );
      const c = ReportTheme(
        primaryColor: Colors.green,
        textColor: Colors.black,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith overrides only provided fields', () {
      const a = ReportTheme(
        backgroundColor: Colors.white,
        primaryColor: Colors.red,
      );
      final b = a.copyWith(primaryColor: Colors.blue);
      expect(b.backgroundColor, Colors.white);
      expect(b.primaryColor, Colors.blue);
      expect(b.cardColor, isNull);
    });
  });

  group('Config theme passthrough', () {
    test('ProductionConfig stores and equates theme', () {
      const a = ProductionConfig(theme: ReportTheme(primaryColor: Colors.red));
      const b = ProductionConfig(theme: ReportTheme(primaryColor: Colors.red));
      const c = ProductionConfig(theme: ReportTheme(primaryColor: Colors.blue));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('DeveloperConfig stores and equates theme', () {
      const a = DeveloperConfig(theme: ReportTheme(primaryColor: Colors.red));
      const b = DeveloperConfig(theme: ReportTheme(primaryColor: Colors.red));
      const c = DeveloperConfig(theme: ReportTheme(primaryColor: Colors.blue));
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith propagates the theme override', () {
      const a = ProductionConfig();
      final b = a.copyWith(theme: const ReportTheme(textColor: Colors.pink));
      expect(b.theme?.textColor, Colors.pink);
      expect(b.title, a.title);
    });
  });
}
