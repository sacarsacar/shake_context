import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/report_payload.dart';

/// One on-disk entry in the retry queue: the queued payload plus the
/// `File` handle it was loaded from. The handle lets [RetryQueue] delete
/// the file after a successful replay without re-listing the directory.
@immutable
class RetryQueueEntry {
  const RetryQueueEntry({
    required this.id,
    required this.queuedAt,
    required this.payload,
    required this.file,
  });

  /// Filename stem (without `.json`). Sortable lexically by enqueue order
  /// because the prefix is the enqueue millisecond timestamp.
  final String id;

  /// When the payload was first written to disk. Authoritative for age-based
  /// eviction — file mtime is unreliable across filesystems.
  final DateTime queuedAt;

  final ReportPayload payload;

  /// The on-disk file backing this entry. [RetryQueue] uses it to delete
  /// the entry after a successful replay.
  final File file;
}

/// File-backed store for the retry queue. Mirrors [FilePersistenceStore] in
/// shape: a [open] factory that locates
/// `<applicationSupportDirectory>/shake_context/queue/`, and a
/// `forDirectory` seam for tests.
///
/// Each queued report lives in its own `<id>.json` file so partial failures
/// only affect one entry, never the whole batch. The file shape is:
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "queuedAt": "2026-05-23T16:32:00.000Z",
///   "payload": { /* ReportPayload.toJson(includeImages: true) */ }
/// }
/// ```
///
/// Schema-version mismatches on load surface as a [null] entry which
/// [RetryQueue] treats as "drop and continue" — the version field exists
/// precisely so we can evolve [ReportPayload] without crashing users
/// mid-upgrade.
class RetryQueueStore {
  RetryQueueStore._(this._directory);

  /// On-disk schema version. Bump only when a breaking change to
  /// [ReportPayload]'s JSON shape lands; entries from older versions are
  /// dropped (rather than crashing on a shape mismatch).
  static const int schemaVersion = 1;

  /// Resolve the canonical queue directory under
  /// `getApplicationSupportDirectory()`. Returns `null` on web (where the
  /// directory APIs aren't applicable) or if path_provider throws.
  static Future<RetryQueueStore?> open() async {
    if (kIsWeb) return null;
    try {
      final root = await getApplicationSupportDirectory();
      final dir = Directory('${root.path}/shake_context/queue');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return RetryQueueStore._(dir);
    } catch (error, stack) {
      _debugWarn('RetryQueueStore.open', error, stack);
      return null;
    }
  }

  /// Test seam — point the store at an arbitrary directory. The caller is
  /// responsible for ensuring the directory exists.
  @visibleForTesting
  factory RetryQueueStore.forDirectory(Directory dir) =>
      RetryQueueStore._(dir);

  final Directory _directory;

  /// Directory holding the queue files. Exposed for tests and diagnostics.
  Directory get directory => _directory;

  /// Number of queue files currently on disk.
  Future<int> count() async {
    try {
      if (!await _directory.exists()) return 0;
      var n = 0;
      await for (final entity in _directory.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.json')) n++;
      }
      return n;
    } catch (error, stack) {
      _debugWarn('count', error, stack);
      return 0;
    }
  }

  /// Append [payload] as a fresh entry, returning its [id].
  ///
  /// Atomic on POSIX: writes to `<id>.json.tmp` then renames into place.
  Future<String> write(
    ReportPayload payload, {
    DateTime? queuedAt,
  }) async {
    final id = _newId();
    final file = File('${_directory.path}/$id.json');
    final tmp = File('${file.path}.tmp');
    final encoded = jsonEncode({
      'schemaVersion': schemaVersion,
      'queuedAt': (queuedAt ?? DateTime.now()).toIso8601String(),
      'payload': payload.toJson(includeImages: true),
    });
    await tmp.writeAsString(encoded, flush: true);
    await tmp.rename(file.path);
    return id;
  }

  /// Load every entry currently on disk in enqueue order (oldest first).
  ///
  /// Files that are unreadable, malformed JSON, missing keys, or have a
  /// mismatched [schemaVersion] are deleted in place and not returned —
  /// they would never replay successfully and would keep tripping `count`.
  Future<List<RetryQueueEntry>> loadAll() async {
    final entries = <RetryQueueEntry>[];
    try {
      if (!await _directory.exists()) return entries;
      final files = await _listJsonFiles();
      for (final file in files) {
        final entry = await _loadOne(file);
        if (entry != null) entries.add(entry);
      }
    } catch (error, stack) {
      _debugWarn('loadAll', error, stack);
    }
    return entries;
  }

  /// Delete a specific entry. Used by [RetryQueue] after a successful replay
  /// and during overflow / age eviction.
  Future<void> delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error, stack) {
      _debugWarn('delete', error, stack);
    }
  }

  /// Drop every queued entry on disk.
  Future<void> clear() async {
    try {
      if (!await _directory.exists()) return;
      await for (final entity in _directory.list(followLinks: false)) {
        if (entity is File) {
          try {
            await entity.delete();
          } catch (error, stack) {
            _debugWarn('clear.entry', error, stack);
          }
        }
      }
    } catch (error, stack) {
      _debugWarn('clear', error, stack);
    }
  }

  /// Files sorted lexically by name = oldest-first by enqueue time, because
  /// the filename prefix is the enqueue millisecond timestamp.
  Future<List<File>> _listJsonFiles() async {
    final files = <File>[];
    await for (final entity in _directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.json')) files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<RetryQueueEntry?> _loadOne(File file) async {
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        await delete(file);
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await delete(file);
        return null;
      }
      final version = decoded['schemaVersion'];
      if (version != schemaVersion) {
        // Future-version or unknown shape — drop rather than crash on
        // missing keys. The version field exists for exactly this case.
        await delete(file);
        return null;
      }
      final payloadJson = decoded['payload'];
      if (payloadJson is! Map<String, dynamic>) {
        await delete(file);
        return null;
      }
      final queuedAtRaw = decoded['queuedAt'];
      final queuedAt = queuedAtRaw is String
          ? DateTime.tryParse(queuedAtRaw) ?? DateTime.now()
          : DateTime.now();
      return RetryQueueEntry(
        id: _idFromPath(file.path),
        queuedAt: queuedAt,
        payload: ReportPayload.fromJson(payloadJson),
        file: file,
      );
    } catch (error, stack) {
      _debugWarn('_loadOne', error, stack);
      await delete(file);
      return null;
    }
  }

  static String _idFromPath(String path) {
    final slash = path.lastIndexOf(Platform.pathSeparator);
    final name = slash >= 0 ? path.substring(slash + 1) : path;
    return name.endsWith('.json')
        ? name.substring(0, name.length - '.json'.length)
        : name;
  }

  static final math.Random _random = math.Random();

  // Counter ensures enqueues within the same millisecond produce
  // monotonically-increasing filenames so loadAll() returns them in
  // enqueue order.
  static int _counter = 0;

  static String _newId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toString().padLeft(13, '0');
    final seq = (_counter++ & 0xFFFF).toRadixString(16).padLeft(4, '0');
    final rand = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '${ts}_${seq}_$rand';
  }

  static void _debugWarn(String operation, Object error, StackTrace stack) {
    if (!kDebugMode) return;
    debugPrint('[shake_context] retry queue $operation failed: $error');
  }
}
