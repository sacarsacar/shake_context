import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  late Directory dir;
  late RetryQueueStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shake_context_queue_');
    store = RetryQueueStore.forDirectory(dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
    RetryQueue.debugSetInstance(null);
  });

  ReportPayload sample({String desc = 'broken', InspectMode? mode}) =>
      ReportPayload(
        mode: mode ?? InspectMode.production,
        userDescription: desc,
        images: [Uint8List.fromList([1, 2, 3, 4])],
        extras: const {'flag': 'beta'},
      );

  group('RetryQueueStore', () {
    test('write() persists a JSON file with the expected envelope',
        () async {
      await store.write(sample(desc: 'one'));
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .toList();
      expect(files, hasLength(1));
      final raw = await (files.single as File).readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], RetryQueueStore.schemaVersion);
      expect(decoded['queuedAt'], isA<String>());
      expect(decoded['payload'], isA<Map<String, dynamic>>());
      expect(decoded['payload']['userDescription'], 'one');
      // Images are inlined as base64 (includeImages: true at enqueue time).
      expect(decoded['payload']['images'], isA<List<dynamic>>());
    });

    test('count() reflects the number of JSON files', () async {
      expect(await store.count(), 0);
      await store.write(sample());
      await store.write(sample());
      await store.write(sample());
      expect(await store.count(), 3);
    });

    test('loadAll() returns entries oldest-first', () async {
      await store.write(sample(desc: 'first'));
      // Small gap so filenames differ deterministically.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.write(sample(desc: 'second'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.write(sample(desc: 'third'));

      final entries = await store.loadAll();
      expect(entries.map((e) => e.payload.userDescription).toList(),
          ['first', 'second', 'third']);
    });

    test('loadAll() drops + deletes schema-version mismatches', () async {
      final bad = File('${dir.path}/0000000000000_0001_aabbccdd.json');
      await bad.writeAsString(jsonEncode({
        'schemaVersion': 999, // unknown future version
        'queuedAt': DateTime.now().toIso8601String(),
        'payload': sample().toJson(includeImages: true),
      }));
      expect(await store.count(), 1);

      final entries = await store.loadAll();
      expect(entries, isEmpty);
      expect(await bad.exists(), isFalse);
    });

    test('loadAll() drops + deletes unparseable JSON', () async {
      final junk = File('${dir.path}/0000000000000_0002_aabbccde.json');
      await junk.writeAsString('this is not json');

      final entries = await store.loadAll();
      expect(entries, isEmpty);
      expect(await junk.exists(), isFalse);
    });

    test('loadAll() restores payload fields including image bytes',
        () async {
      final original = sample();
      await store.write(original);
      final entries = await store.loadAll();
      expect(entries, hasLength(1));
      final restored = entries.single.payload;
      expect(restored.mode, original.mode);
      expect(restored.userDescription, original.userDescription);
      expect(restored.extras, original.extras);
      expect(restored.images, hasLength(1));
      expect(restored.images.first, original.images.first);
    });

    test('clear() empties the directory', () async {
      await store.write(sample());
      await store.write(sample());
      await store.clear();
      expect(await store.count(), 0);
    });

    test('delete() removes a single entry', () async {
      await store.write(sample(desc: 'keep'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await store.write(sample(desc: 'drop'));

      final entries = await store.loadAll();
      final target =
          entries.firstWhere((e) => e.payload.userDescription == 'drop');
      await store.delete(target.file);

      final remaining = await store.loadAll();
      expect(remaining.map((e) => e.payload.userDescription), ['keep']);
    });
  });

  group('RetryQueue', () {
    test('enqueue() writes through the store', () async {
      final queue = RetryQueue(store: store);
      await queue.enqueue(sample(desc: 'fail'));
      expect(await queue.count(), 1);
    });

    test('count() returns 0 on an empty queue', () async {
      final queue = RetryQueue(store: store);
      expect(await queue.count(), 0);
    });

    test('replay() invokes the callback for each entry in order',
        () async {
      final queue = RetryQueue(store: store);
      await queue.enqueue(sample(desc: 'a'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(sample(desc: 'b'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(sample(desc: 'c'));

      final seen = <String>[];
      final delivered =
          await queue.replay((payload) async => seen.add(payload.userDescription));

      expect(seen, ['a', 'b', 'c']);
      expect(delivered, 3);
      expect(await queue.count(), 0);
    });

    test('replay() leaves the file in place when the callback throws',
        () async {
      final queue = RetryQueue(store: store);
      await queue.enqueue(sample(desc: 'flaky'));

      final delivered =
          await queue.replay((_) async => throw StateError('500'));
      expect(delivered, 0);
      expect(await queue.count(), 1);
    });

    test('replay() handles a mix of success and failure correctly',
        () async {
      final queue = RetryQueue(store: store);
      await queue.enqueue(sample(desc: 'ok-1'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(sample(desc: 'fail-1'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(sample(desc: 'ok-2'));

      final delivered = await queue.replay((payload) async {
        if (payload.userDescription.startsWith('fail')) {
          throw StateError('500');
        }
      });
      expect(delivered, 2);

      // Only the failed entry should remain.
      final remaining = await queue.store.loadAll();
      expect(remaining.map((e) => e.payload.userDescription),
          ['fail-1']);
    });

    test('enqueue beyond maxEntries evicts the oldest', () async {
      final queue = RetryQueue(store: store, maxEntries: 3);
      await queue.enqueue(sample(desc: 'a'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(sample(desc: 'b'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(sample(desc: 'c'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(sample(desc: 'd'));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await queue.enqueue(sample(desc: 'e'));

      expect(await queue.count(), 3);
      final entries = await queue.store.loadAll();
      expect(entries.map((e) => e.payload.userDescription), ['c', 'd', 'e']);
    });

    test('replay() drops entries older than maxAge without invoking callback',
        () async {
      final queue =
          RetryQueue(store: store, maxAge: const Duration(hours: 1));
      // Hand-write a stale entry whose queuedAt is far in the past.
      final stale =
          File('${dir.path}/0000000000000_0001_aabbccdd.json');
      await stale.writeAsString(jsonEncode({
        'schemaVersion': RetryQueueStore.schemaVersion,
        'queuedAt':
            DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        'payload': sample(desc: 'stale').toJson(includeImages: true),
      }));
      // ...and a fresh one through the queue.
      await queue.enqueue(sample(desc: 'fresh'));

      final seen = <String>[];
      final delivered =
          await queue.replay((p) async => seen.add(p.userDescription));

      expect(seen, ['fresh']);
      expect(delivered, 1);
      expect(await stale.exists(), isFalse, reason: 'stale entry deleted');
      expect(await queue.count(), 0);
    });

    test('clear() empties the queue', () async {
      final queue = RetryQueue(store: store);
      await queue.enqueue(sample());
      await queue.enqueue(sample());
      await queue.clear();
      expect(await queue.count(), 0);
    });

    test('round-trip: enqueued payload re-emerges byte-identical via replay',
        () async {
      final queue = RetryQueue(store: store);
      final original = sample(desc: 'roundtrip', mode: InspectMode.developer);
      await queue.enqueue(original);

      ReportPayload? captured;
      await queue.replay((p) async {
        captured = p;
      });

      expect(captured, isNotNull);
      expect(captured!.mode, original.mode);
      expect(captured!.userDescription, original.userDescription);
      expect(captured!.extras, original.extras);
      expect(captured!.images, hasLength(1));
      expect(captured!.images.first, original.images.first);
    });

    test('concurrent replay calls collapse onto the same future', () async {
      final queue = RetryQueue(store: store);
      await queue.enqueue(sample(desc: 'one'));
      await queue.enqueue(sample(desc: 'two'));

      var callCount = 0;
      Future<void> callback(ReportPayload p) async {
        callCount++;
        // Yield once so the second `replay` call lands while the first
        // is still in flight.
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final r1 = queue.replay(callback);
      final r2 = queue.replay(callback);

      final results = await Future.wait([r1, r2]);
      // Both callers see the same result because the second collapsed
      // onto the first — no double-send.
      expect(results[0], results[1]);
      expect(callCount, 2, reason: 'each payload delivered exactly once');
    });

    test('replayWithRegisteredCallback returns 0 with no callback', () async {
      final queue = RetryQueue(store: store);
      await queue.enqueue(sample());
      expect(await queue.replayWithRegisteredCallback(), 0);
      // The entry was not consumed.
      expect(await queue.count(), 1);
    });

    test('replayWithRegisteredCallback uses the registered callback',
        () async {
      final queue = RetryQueue(store: store);
      await queue.enqueue(sample(desc: 'via-registered'));

      String? seen;
      queue.registerCallback((p) async {
        seen = p.userDescription;
      });

      final delivered = await queue.replayWithRegisteredCallback();
      expect(delivered, 1);
      expect(seen, 'via-registered');
      expect(await queue.count(), 0);
    });

    test('instance handle survives debugSetInstance round-trip', () async {
      expect(RetryQueue.instance, isNull);
      final queue = RetryQueue(store: store);
      RetryQueue.debugSetInstance(queue);
      expect(identical(RetryQueue.instance, queue), isTrue);
      RetryQueue.debugSetInstance(null);
      expect(RetryQueue.instance, isNull);
    });
  });
}
