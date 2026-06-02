import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  group('LogEntry.fromJson', () {
    test('round-trips through toJson', () {
      final original = LogEntry(
        message: 'boom',
        level: LogLevel.error,
        source: 'FlutterError',
        stackTrace: StackTrace.fromString('#0 main (file.dart:1:1)'),
        timestamp: DateTime.utc(2026, 5, 23, 12, 0),
      );
      final restored = LogEntry.fromJson(original.toJson());
      expect(restored.message, original.message);
      expect(restored.level, original.level);
      expect(restored.source, original.source);
      expect(restored.stackTrace.toString(), original.stackTrace.toString());
      expect(restored.timestamp, original.timestamp);
    });

    test('missing optional fields parse to defaults', () {
      final restored = LogEntry.fromJson({'message': 'hi'});
      expect(restored.message, 'hi');
      expect(restored.level, LogLevel.info);
      expect(restored.source, isNull);
      expect(restored.stackTrace, isNull);
    });

    test('unknown level falls back to info', () {
      final restored =
          LogEntry.fromJson({'message': 'x', 'level': 'cosmic-ray'});
      expect(restored.level, LogLevel.info);
    });

    test('wrong-typed fields fall through to defaults without throwing', () {
      final restored = LogEntry.fromJson({
        'message': 42, // int instead of string
        'level': 99, // int instead of string
        'source': false, // bool instead of string
        'stackTrace': [1, 2], // list instead of string
        'timestamp': 'not-a-date',
      });
      expect(restored.message, '');
      expect(restored.level, LogLevel.info);
      expect(restored.source, isNull);
      expect(restored.stackTrace, isNull);
      // Unparseable timestamp falls through to "now"; just confirm it's set.
      expect(restored.timestamp, isA<DateTime>());
    });
  });

  group('NetworkLog.fromJson', () {
    test('round-trips through toJson', () {
      final original = NetworkLog(
        method: 'POST',
        url: 'https://api.example.com/x',
        statusCode: 500,
        durationMs: 412,
        requestHeaders: const {'Content-Type': 'application/json'},
        responseHeaders: const {'X-Trace': 'abc'},
        requestBody: '{"k":"v"}',
        responseBody: '{"error":"oh no"}',
        timestamp: DateTime.utc(2026, 5, 23, 12, 0),
      );
      final restored = NetworkLog.fromJson(original.toJson());
      expect(restored.method, 'POST');
      expect(restored.url, original.url);
      expect(restored.statusCode, 500);
      expect(restored.durationMs, 412);
      expect(restored.requestHeaders, original.requestHeaders);
      expect(restored.responseHeaders, original.responseHeaders);
      expect(restored.requestBody, original.requestBody);
      expect(restored.responseBody, original.responseBody);
      expect(restored.timestamp, original.timestamp);
    });

    test('missing optional fields parse to defaults', () {
      final restored = NetworkLog.fromJson({
        'method': 'GET',
        'url': 'https://example.com',
      });
      expect(restored.method, 'GET');
      expect(restored.url, 'https://example.com');
      expect(restored.statusCode, isNull);
      expect(restored.durationMs, isNull);
      expect(restored.requestHeaders, isNull);
      expect(restored.responseBody, isNull);
    });

    test('wrong-typed required fields default to GET / empty url', () {
      final restored = NetworkLog.fromJson({
        'method': 7,
        'url': null,
        'statusCode': 'oops',
        'durationMs': 'oops',
      });
      expect(restored.method, 'GET');
      expect(restored.url, '');
      expect(restored.statusCode, isNull);
      expect(restored.durationMs, isNull);
    });
  });

  group('ReportMetadata.fromJson', () {
    test('round-trips through toJson', () {
      final original = ReportMetadata(
        currentRoute: '/checkout',
        deviceInfo: const {'platform': 'iOS', 'systemVersion': '17.0'},
        logs: [
          LogEntry(
            message: 'one',
            level: LogLevel.warning,
            timestamp: DateTime.utc(2026, 5, 23, 12, 0),
          ),
        ],
        networkLogs: [
          NetworkLog(
            method: 'GET',
            url: 'https://example.com',
            statusCode: 200,
            timestamp: DateTime.utc(2026, 5, 23, 12, 0),
          ),
        ],
        previousSessionStartedAt: DateTime.utc(2026, 5, 22),
        timestamp: DateTime.utc(2026, 5, 23, 12, 0),
      );
      final restored = ReportMetadata.fromJson(original.toJson());
      expect(restored.currentRoute, original.currentRoute);
      expect(restored.deviceInfo, original.deviceInfo);
      expect(restored.logs, hasLength(1));
      expect(restored.logs.first.message, 'one');
      expect(restored.networkLogs, hasLength(1));
      expect(restored.networkLogs.first.url, 'https://example.com');
      expect(restored.previousSessionStartedAt, original.previousSessionStartedAt);
      expect(restored.timestamp, original.timestamp);
    });

    test('missing collections parse to empty lists', () {
      final restored = ReportMetadata.fromJson(const {});
      expect(restored.logs, isEmpty);
      expect(restored.networkLogs, isEmpty);
      expect(restored.previousSessionLogs, isEmpty);
      expect(restored.previousSessionNetwork, isEmpty);
      expect(restored.deviceInfo, isEmpty);
    });

    test('wrong-typed collections parse to empty without throwing', () {
      final restored = ReportMetadata.fromJson(const {
        'logs': 'not-a-list',
        'networkLogs': 12,
        'deviceInfo': 'not-a-map',
      });
      expect(restored.logs, isEmpty);
      expect(restored.networkLogs, isEmpty);
      expect(restored.deviceInfo, isEmpty);
    });

    test('individually broken log entries are skipped', () {
      // One usable log entry alongside one structurally wrong one.
      final restored = ReportMetadata.fromJson({
        'logs': [
          {'message': 'good', 'level': 'info'},
          'this should be a map, not a string',
          42,
          {'level': 'info'}, // missing message — fromJson defaults to ''
        ],
      });
      expect(restored.logs.map((e) => e.message), ['good', '']);
    });
  });

  group('ReportPayload.fromJson', () {
    test('round-trips with includeImages: true', () {
      final original = ReportPayload(
        mode: InspectMode.developer,
        userDescription: 'broken',
        images: [
          Uint8List.fromList([1, 2, 3]),
          Uint8List.fromList([9, 9, 9, 9]),
        ],
        metadata: ReportMetadata(
          currentRoute: '/x',
          deviceInfo: const {'platform': 'iOS'},
          timestamp: DateTime.utc(2026, 5, 23),
        ),
        extras: const {'installationId': 'abc-123'},
      );
      final json = original.toJson(includeImages: true);
      final restored = ReportPayload.fromJson(json);

      expect(restored.mode, original.mode);
      expect(restored.userDescription, original.userDescription);
      expect(restored.extras, original.extras);
      expect(restored.images, hasLength(2));
      expect(restored.images[0], original.images[0]);
      expect(restored.images[1], original.images[1]);
      expect(restored.metadata.currentRoute, '/x');
    });

    test('round-trip without includeImages yields empty image list', () {
      final original = ReportPayload(
        mode: InspectMode.production,
        userDescription: 'no-images',
        images: [Uint8List.fromList([7])],
      );
      final json = original.toJson(); // includeImages: false
      final restored = ReportPayload.fromJson(json);
      expect(restored.userDescription, 'no-images');
      // toJson(includeImages: false) emits `imageCount`, not bytes — the
      // round-trip drops the bytes by design.
      expect(restored.images, isEmpty);
    });

    test('unknown mode falls back to production', () {
      final restored = ReportPayload.fromJson(const {
        'mode': 'martian',
        'userDescription': 'x',
      });
      expect(restored.mode, InspectMode.production);
    });

    test('missing scalar fields parse to defaults', () {
      final restored = ReportPayload.fromJson(const {});
      expect(restored.mode, InspectMode.production);
      expect(restored.userDescription, '');
      expect(restored.images, isEmpty);
      expect(restored.extras, isEmpty);
    });

    test('wrong-typed fields fall through to defaults without throwing', () {
      final restored = ReportPayload.fromJson(const {
        'mode': 42,
        'userDescription': false,
        'images': 'not-a-list',
        'extras': 'not-a-map',
      });
      expect(restored.mode, InspectMode.production);
      expect(restored.userDescription, '');
      expect(restored.images, isEmpty);
      expect(restored.extras, isEmpty);
    });

    test('individually-broken image strings are skipped', () {
      final restored = ReportPayload.fromJson({
        'mode': 'production',
        'userDescription': '',
        'images': [
          base64Encode([1, 2, 3]),
          'not-base64-at-all-!!!@@@',
          base64Encode([9]),
        ],
      });
      expect(restored.images, hasLength(2));
      expect(restored.images[0], Uint8List.fromList([1, 2, 3]));
      expect(restored.images[1], Uint8List.fromList([9]));
    });

    test('round-trip preserves payload contents (image bytes equal)', () {
      final original = ReportPayload(
        mode: InspectMode.production,
        userDescription: 'fine',
        images: [Uint8List.fromList([10, 20, 30])],
        metadata: ReportMetadata(timestamp: DateTime.utc(2026, 5, 23, 9, 0)),
        extras: const {'k': 'v'},
      );
      final restored =
          ReportPayload.fromJson(original.toJson(includeImages: true));
      // Image bytes survive the trip. `listEquals` on the outer
      // `List<Uint8List>` compares identity, so we walk pairwise.
      expect(restored.images.length, original.images.length);
      for (var i = 0; i < restored.images.length; i++) {
        expect(restored.images[i], orderedEquals(original.images[i]));
      }
      expect(restored.metadata, equals(original.metadata));
      expect(restored.extras, equals(original.extras));
    });
  });
}
