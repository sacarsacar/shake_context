import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  group('RedactionConfig.redactHeaders', () {
    test('masks the default sensitive header keys case-insensitively', () {
      const cfg = RedactionConfig();
      final out = cfg.redactHeaders({
        'Authorization': 'Bearer abc',
        'Cookie': 'session=xyz',
        'Content-Type': 'application/json',
        'X-API-KEY': 'apikey-123',
      });
      expect(out['Authorization'], '«redacted»');
      expect(out['Cookie'], '«redacted»');
      expect(out['X-API-KEY'], '«redacted»');
      expect(out['Content-Type'], 'application/json');
    });

    test('leaves headers untouched when the policy is disabled', () {
      final out = RedactionConfig.disabled.redactHeaders({
        'Authorization': 'Bearer abc',
      });
      expect(out['Authorization'], 'Bearer abc');
    });
  });

  group('RedactionConfig.redactBody', () {
    test('masks JSON-shaped secret keys', () {
      const cfg = RedactionConfig();
      final out = cfg.redactBody(
        '{"username":"alice","password":"hunter2","token":"abc","ok":true}',
      );
      expect(out, contains('"password":"«redacted»"'));
      expect(out, contains('"token":"«redacted»"'));
      expect(out, contains('"username":"alice"'));
    });

    test('masks form-encoded secret keys', () {
      const cfg = RedactionConfig();
      final out = cfg.redactBody('username=alice&password=hunter2&keep=1');
      expect(out, contains('password=«redacted»'));
      expect(out, contains('username=alice'));
      expect(out, contains('keep=1'));
    });

    test('truncates bodies exceeding maxBodyChars', () {
      const cfg = RedactionConfig(maxBodyChars: 10);
      final out = cfg.redactBody('a' * 50);
      expect(out, startsWith('a' * 10));
      expect(out, contains('40 more chars'));
    });
  });

  group('RedactionConfig.truncateLog', () {
    test('caps log messages at maxLogChars', () {
      const cfg = RedactionConfig(maxLogChars: 5);
      expect(cfg.truncateLog('hello world'), contains('6 more chars'));
      expect(cfg.truncateLog('hi'), 'hi');
    });
  });
}
