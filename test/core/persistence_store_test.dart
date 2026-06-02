import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';
import 'package:shake_context/src/core/log_capture.dart';

void main() {
  late Directory tmp;
  late File sessionFile;
  late FilePersistenceStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('shake_context_test_');
    sessionFile = File('${tmp.path}/session.json');
    store = FilePersistenceStore.forFile(sessionFile);
  });

  tearDown(() async {
    LogCapture.instance.reset();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  group('FilePersistenceStore', () {
    test('returns null when no file exists', () async {
      expect(await store.loadAndClear(), isNull);
    });

    test('save() round-trips logs + network through loadAndClear()', () async {
      final ts = DateTime.utc(2026, 5, 19, 10, 30);
      await store.save(SessionSnapshot(
        startedAt: ts,
        logs: [
          LogEntry(
            message: 'boot',
            level: LogLevel.info,
            source: 'debugPrint',
            timestamp: ts,
          ),
          LogEntry(
            message: 'crash',
            level: LogLevel.error,
            source: 'FlutterError',
            stackTrace: StackTrace.fromString('  #0 main (file.dart:1:1)'),
            timestamp: ts,
          ),
        ],
        network: [
          NetworkLog(
            method: 'GET',
            url: 'https://api.test/items',
            statusCode: 200,
            durationMs: 42,
            requestHeaders: const {'Accept': 'application/json'},
            responseHeaders: const {'Content-Type': 'application/json'},
            requestBody: 'null',
            responseBody: '{"ok":true}',
            timestamp: ts,
          ),
        ],
      ));

      expect(await sessionFile.exists(), isTrue);

      final loaded = await store.loadAndClear();
      expect(loaded, isNotNull);
      expect(loaded!.startedAt, ts);
      expect(loaded.logs.length, 2);
      expect(loaded.logs[0].message, 'boot');
      expect(loaded.logs[0].source, 'debugPrint');
      expect(loaded.logs[1].level, LogLevel.error);
      expect(loaded.logs[1].stackTrace?.toString(),
          contains('main (file.dart:1:1)'));
      expect(loaded.network.length, 1);
      expect(loaded.network.single.url, 'https://api.test/items');
      expect(loaded.network.single.responseBody, '{"ok":true}');

      // loadAndClear deletes the file so a second call yields null.
      expect(await sessionFile.exists(), isFalse);
      expect(await store.loadAndClear(), isNull);
    });

    test('saveSync() produces a file readable by loadAndClear()', () async {
      final ts = DateTime.utc(2026, 5, 19);
      store.saveSync(SessionSnapshot(
        startedAt: ts,
        logs: [LogEntry(message: 'sync-write', timestamp: ts)],
        network: const [],
      ));
      expect(await sessionFile.exists(), isTrue);
      final loaded = await store.loadAndClear();
      expect(loaded!.logs.single.message, 'sync-write');
    });

    test('loadAndClear() swallows a corrupt file and deletes it', () async {
      await sessionFile.writeAsString('this is not json {{{');
      expect(await store.loadAndClear(), isNull);
      expect(await sessionFile.exists(), isFalse);
    });

    test('clear() removes the file if present', () async {
      await sessionFile.writeAsString('{}');
      await store.clear();
      expect(await sessionFile.exists(), isFalse);
    });
  });

  group('LogCapture persistence integration', () {
    test('error-level entries trigger immediate sync flush', () async {
      await LogCapture.instance.enablePersistence(store);

      // Initial enable writes an empty snapshot — verify by reading via a
      // fresh store (loadAndClear would consume it).
      expect(await sessionFile.exists(), isTrue);
      var raw = await sessionFile.readAsString();
      expect(raw, contains('"logs":[]'));

      LogCapture.instance.log('boom',
          level: LogLevel.error, source: 'unit', stackTrace: StackTrace.current);

      raw = await sessionFile.readAsString();
      expect(raw, contains('"boom"'));
      expect(raw, contains('"level":"error"'));
    });

    test('non-error entries are written after the debounce', () async {
      LogCapture.instance.persistenceDebounce =
          const Duration(milliseconds: 30);
      await LogCapture.instance.enablePersistence(store);

      LogCapture.instance.log('hello');
      // Immediately after, the file should still hold the empty-init payload.
      var raw = await sessionFile.readAsString();
      expect(raw.contains('"hello"'), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 80));
      raw = await sessionFile.readAsString();
      expect(raw, contains('"hello"'));
    });

    test('enablePersistence surfaces a prior snapshot as recoveredSession',
        () async {
      // Seed the file with a "previous session".
      final ts = DateTime.utc(2026, 5, 18);
      await store.save(SessionSnapshot(
        startedAt: ts,
        logs: [LogEntry(message: 'prior', timestamp: ts)],
        network: const [],
      ));

      // Fresh capture instance simulating next app launch.
      LogCapture.instance.reset();
      await LogCapture.instance.enablePersistence(store);

      expect(LogCapture.instance.recoveredSession, isNotNull);
      expect(LogCapture.instance.recoveredSession!.logs.single.message,
          'prior');
      // File should now hold the *new* session's empty snapshot.
      final raw = await sessionFile.readAsString();
      expect(raw.contains('prior'), isFalse);
    });
  }, skip: kIsWeb);
}
