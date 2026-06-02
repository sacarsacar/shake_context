import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  group('ReportMetadata', () {
    test('empty() is the production default shape', () {
      final m = ReportMetadata.empty();
      expect(m.currentRoute, isNull);
      expect(m.deviceInfo, isEmpty);
      expect(m.logs, isEmpty);
      expect(m.networkLogs, isEmpty);
      expect(m.timestamp, isA<DateTime>());
    });

    test('fields are unmodifiable', () {
      final ts = DateTime(2026);
      final m = ReportMetadata(
        deviceInfo: {'model': 'iPhone 17'},
        logs: [LogEntry(message: 'boot', timestamp: ts)],
        networkLogs: [
          NetworkLog(method: 'GET', url: 'https://x.test', timestamp: ts),
        ],
      );
      expect(() => m.deviceInfo['x'] = 1, throwsUnsupportedError);
      expect(() => m.logs.add(LogEntry(message: 'y')), throwsUnsupportedError);
      expect(
        () => m.networkLogs.add(NetworkLog(method: 'POST', url: 'x')),
        throwsUnsupportedError,
      );
    });

    test('equality compares contents', () {
      final ts = DateTime(2026);
      ReportMetadata build(String route) => ReportMetadata(
            currentRoute: route,
            deviceInfo: const {'os': 'iOS 26'},
            logs: [LogEntry(message: 'hello', timestamp: ts)],
            networkLogs: [
              NetworkLog(method: 'GET', url: 'https://x.test', timestamp: ts),
            ],
            timestamp: ts,
          );
      final a = build('/home');
      final b = build('/home');
      final c = build('/other');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('ReportPayload', () {
    test('defaults to empty images and empty metadata', () {
      final p = ReportPayload(
        mode: InspectMode.production,
        userDescription: 'broken',
      );
      expect(p.images, isEmpty);
      expect(p.metadata.deviceInfo, isEmpty);
      expect(p.metadata.logs, isEmpty);
      expect(p.metadata.networkLogs, isEmpty);
    });

    test('images list is unmodifiable', () {
      final p = ReportPayload(
        mode: InspectMode.developer,
        userDescription: '',
        images: [Uint8List.fromList([1, 2, 3])],
      );
      expect(() => p.images.add(Uint8List(0)), throwsUnsupportedError);
    });

    test('equality compares all fields including image bytes', () {
      final ts = DateTime(2026);
      final bytes = Uint8List.fromList([1, 2, 3]);
      final meta = ReportMetadata(timestamp: ts);
      final a = ReportPayload(
        mode: InspectMode.production,
        userDescription: 'x',
        images: [bytes],
        metadata: meta,
      );
      final b = ReportPayload(
        mode: InspectMode.production,
        userDescription: 'x',
        images: [bytes],
        metadata: meta,
      );
      final c = ReportPayload(
        mode: InspectMode.developer,
        userDescription: 'x',
        images: [bytes],
        metadata: meta,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('extras default to an empty unmodifiable map', () {
      final p = ReportPayload(
        mode: InspectMode.production,
        userDescription: '',
      );
      expect(p.extras, isEmpty);
      expect(() => p.extras['k'] = 'v', throwsUnsupportedError);
    });

    test('extras flow through and participate in equality', () {
      // Share metadata so the auto-generated timestamps don't desync the
      // two operands of the equality comparison.
      final meta = ReportMetadata(timestamp: DateTime.utc(2026));
      final a = ReportPayload(
        mode: InspectMode.production,
        userDescription: '',
        metadata: meta,
        extras: const {'installationId': 'abc', 'flavor': 'prod'},
      );
      final b = ReportPayload(
        mode: InspectMode.production,
        userDescription: '',
        metadata: meta,
        extras: const {'installationId': 'abc', 'flavor': 'prod'},
      );
      final c = ReportPayload(
        mode: InspectMode.production,
        userDescription: '',
        metadata: meta,
        extras: const {'installationId': 'xyz'},
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('primaryImage returns first byte buffer or null', () {
      final empty = ReportPayload(
        mode: InspectMode.production,
        userDescription: '',
      );
      expect(empty.primaryImage, isNull);

      final first = Uint8List.fromList([1, 2, 3]);
      final second = Uint8List.fromList([4, 5, 6]);
      final filled = ReportPayload(
        mode: InspectMode.production,
        userDescription: '',
        images: [first, second],
      );
      expect(filled.primaryImage, same(first));
    });
  });

  group('toJson', () {
    test('LogEntry serialises with iso timestamp and lowercase level', () {
      final ts = DateTime.utc(2026, 5, 19, 16, 32, 0);
      final entry = LogEntry(
        message: 'boom',
        level: LogLevel.error,
        source: 'parser',
        stackTrace: StackTrace.fromString('#0 example\n#1 trace'),
        timestamp: ts,
      );
      final json = entry.toJson();
      expect(json['message'], 'boom');
      expect(json['level'], 'error');
      expect(json['source'], 'parser');
      expect(json['stackTrace'], contains('example'));
      expect(json['timestamp'], '2026-05-19T16:32:00.000Z');
    });

    test('LogEntry omits null source and stackTrace', () {
      final json = LogEntry(message: 'plain').toJson();
      expect(json.containsKey('source'), isFalse);
      expect(json.containsKey('stackTrace'), isFalse);
    });

    test('NetworkLog omits null optionals and preserves required fields', () {
      final ts = DateTime.utc(2026, 5, 19);
      final json = NetworkLog(
        method: 'GET',
        url: 'https://x.test/api',
        timestamp: ts,
      ).toJson();
      expect(json['method'], 'GET');
      expect(json['url'], 'https://x.test/api');
      expect(json['timestamp'], '2026-05-19T00:00:00.000Z');
      // Every optional should be absent — keeps the wire payload compact.
      for (final key in [
        'statusCode',
        'durationMs',
        'requestHeaders',
        'responseHeaders',
        'requestBody',
        'responseBody',
        'error',
      ]) {
        expect(json.containsKey(key), isFalse, reason: 'unexpected $key');
      }
    });

    test('NetworkLog includes populated optionals', () {
      final json = NetworkLog(
        method: 'POST',
        url: 'https://x.test/api',
        statusCode: 500,
        durationMs: 240,
        requestHeaders: const {'Authorization': '[REDACTED]'},
        responseBody: '{"error":"boom"}',
        error: null,
      ).toJson();
      expect(json['statusCode'], 500);
      expect(json['durationMs'], 240);
      expect(json['requestHeaders'], {'Authorization': '[REDACTED]'});
      expect(json['responseBody'], '{"error":"boom"}');
      expect(json.containsKey('error'), isFalse);
    });

    test('ReportMetadata always emits collections for predictable shape', () {
      final json = ReportMetadata.empty().toJson();
      expect(json['logs'], const <dynamic>[]);
      expect(json['networkLogs'], const <dynamic>[]);
      expect(json['previousSessionLogs'], const <dynamic>[]);
      expect(json['previousSessionNetwork'], const <dynamic>[]);
      expect(json['deviceInfo'], const <String, dynamic>{});
      expect(json.containsKey('currentRoute'), isFalse);
      expect(json.containsKey('previousSessionStartedAt'), isFalse);
    });

    test('ReportMetadata flattens nested logs via their toJson', () {
      final ts = DateTime.utc(2026, 1, 1);
      final meta = ReportMetadata(
        currentRoute: '/checkout',
        deviceInfo: const {'platform': 'android', 'model': 'Pixel 7'},
        logs: [LogEntry(message: 'hi', timestamp: ts)],
        networkLogs: [
          NetworkLog(method: 'GET', url: 'https://x.test', timestamp: ts),
        ],
        timestamp: ts,
      );
      final json = meta.toJson();
      expect(json['currentRoute'], '/checkout');
      expect(json['deviceInfo'], {'platform': 'android', 'model': 'Pixel 7'});
      expect((json['logs'] as List).single, isA<Map<String, dynamic>>());
      expect((json['logs'] as List).single['message'], 'hi');
      expect((json['networkLogs'] as List).single['method'], 'GET');
    });

    test('ReportPayload excludes images by default but reports count', () {
      final payload = ReportPayload(
        mode: InspectMode.production,
        userDescription: 'broken',
        images: [
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([4, 5]),
        ],
      );
      final json = payload.toJson();
      expect(json['mode'], 'production');
      expect(json['userDescription'], 'broken');
      expect(json['imageCount'], 2);
      expect(json.containsKey('images'), isFalse);
      // Whole thing must be jsonEncodable end-to-end.
      expect(() => jsonEncode(json), returnsNormally);
    });

    test('ReportPayload includes extras only when non-empty', () {
      final without = ReportPayload(
        mode: InspectMode.production,
        userDescription: '',
      ).toJson();
      expect(without.containsKey('extras'), isFalse);

      final with_ = ReportPayload(
        mode: InspectMode.production,
        userDescription: '',
        extras: const {'installationId': 'abc-123', 'flavor': 'prod'},
      ).toJson();
      expect(with_['extras'], {'installationId': 'abc-123', 'flavor': 'prod'});
      expect(() => jsonEncode(with_), returnsNormally);
    });

    test('ReportPayload base64-encodes images when opted in', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final payload = ReportPayload(
        mode: InspectMode.developer,
        userDescription: '',
        images: [bytes],
      );
      final json = payload.toJson(includeImages: true);
      expect(json['imageCount'], 1);
      expect(json['images'], [base64Encode(bytes)]);
    });

    test('jsonEncode(payload) round-trips without manual conversion', () {
      final ts = DateTime.utc(2026, 5, 19);
      final payload = ReportPayload(
        mode: InspectMode.developer,
        userDescription: 'crash on /home',
        metadata: ReportMetadata(
          currentRoute: '/home',
          deviceInfo: const {'platform': 'ios'},
          logs: [
            LogEntry(message: 'a', level: LogLevel.warning, timestamp: ts),
          ],
          timestamp: ts,
        ),
      );
      final encoded = jsonEncode(payload);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['mode'], 'developer');
      expect(decoded['userDescription'], 'crash on /home');
      expect(decoded['metadata']['currentRoute'], '/home');
      expect(decoded['metadata']['logs'].first['level'], 'warning');
    });
  });
}
