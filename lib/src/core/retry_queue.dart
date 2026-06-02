import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/report_payload.dart';
import 'retry_queue_store.dart';

/// Persistent retry queue for [ReportPayload]s whose submission failed.
///
/// Lifecycle:
///
///  1. Submission failure → `enqueue(payload)` writes the payload to disk.
///  2. On next launch (or when the host calls [replay] manually), each
///     queued payload is handed back to the host's
///     [ReportSubmittedCallback]. On success the file is deleted; on
///     failure it stays on disk to retry on the launch after that.
///  3. Eviction caps damage: entries older than [maxAge] are dropped on
///     replay; on enqueue, if more than [maxEntries] entries are on disk,
///     the oldest is dropped.
///
/// All disk I/O is best-effort — a failure to enqueue or evict never throws
/// out of [RetryQueue] (the host's submission flow continues).
///
/// Single-process re-entrancy: concurrent calls to [replay] collapse onto
/// the same in-flight future, so a manual "Retry now" tap that races the
/// post-boot auto-replay won't double-send any report.
class RetryQueue {
  RetryQueue({
    required RetryQueueStore store,
    Duration maxAge = const Duration(days: 7),
    int maxEntries = 20,
  })  : assert(maxEntries > 0, 'maxEntries must be at least 1'),
        assert(maxAge > Duration.zero, 'maxAge must be positive'),
        _store = store,
        _maxAge = maxAge,
        _maxEntries = maxEntries;

  /// Process-wide handle, set by [ShakeContext.guard] when
  /// `enableRetryQueue: true`. Stays `null` when the queue is disabled —
  /// callers must null-check before using.
  static RetryQueue? get instance => _instance;
  static RetryQueue? _instance;

  /// Install [queue] as the process-wide handle. Passing `null` clears it
  /// (used in tests). Visible to other library files; not part of the
  /// public API.
  static void debugSetInstance(RetryQueue? queue) {
    _instance = queue;
  }

  final RetryQueueStore _store;
  final Duration _maxAge;
  final int _maxEntries;

  Future<int>? _activeReplay;

  /// The most recently registered host callback. Set by [ShakeContext]'s
  /// state on mount so the static [ShakeContext.replayQueuedReports] entry
  /// point has something to call.
  ReportSubmittedCallback? _registeredCallback;

  /// Register the host's submit callback for use by the post-boot auto
  /// replay and the static `replayQueuedReports` entry point. Called by
  /// [ShakeContext]'s state on mount; cleared on dispose.
  void registerCallback(ReportSubmittedCallback? callback) {
    _registeredCallback = callback;
  }

  /// Underlying store — exposed only for tests that need to observe the
  /// on-disk state directly.
  @visibleForTesting
  RetryQueueStore get store => _store;

  /// Append [payload] to the queue. Evicts the oldest entry if the queue
  /// is at capacity so the cap is a hard ceiling, not a soft one.
  Future<void> enqueue(ReportPayload payload) async {
    try {
      await _store.write(payload);
      await _evictOverflow();
    } catch (error, stack) {
      _debugWarn('enqueue', error, stack);
    }
  }

  /// Number of payloads currently queued on disk.
  Future<int> count() => _store.count();

  /// Replay every queued payload through [callback]. Successful replays
  /// are deleted from disk; failures are left in place for the next
  /// invocation. Entries older than [maxAge] are dropped without being
  /// replayed.
  ///
  /// Returns the number of payloads delivered successfully.
  ///
  /// Concurrent callers collapse onto the same in-flight future — calling
  /// [replay] while one is already running returns that running future
  /// instead of starting a second pass.
  Future<int> replay(ReportSubmittedCallback callback) {
    final existing = _activeReplay;
    if (existing != null) return existing;
    final future = _doReplay(callback);
    _activeReplay = future;
    return future.whenComplete(() {
      if (identical(_activeReplay, future)) _activeReplay = null;
    });
  }

  /// Replay using the callback registered via [registerCallback]. Returns
  /// `0` when no callback is registered.
  Future<int> replayWithRegisteredCallback() {
    final cb = _registeredCallback;
    if (cb == null) return Future.value(0);
    return replay(cb);
  }

  /// Drop every queued payload without trying to send.
  Future<void> clear() => _store.clear();

  Future<int> _doReplay(ReportSubmittedCallback callback) async {
    var delivered = 0;
    try {
      final entries = await _store.loadAll();
      final now = DateTime.now();
      for (final entry in entries) {
        if (now.difference(entry.queuedAt) > _maxAge) {
          // Stale beyond `maxAge` — bin it and move on. Replaying it
          // would just fail again (e.g. expired auth) or land hours of
          // outdated context with engineering.
          await _store.delete(entry.file);
          continue;
        }
        try {
          await callback(entry.payload);
          await _store.delete(entry.file);
          delivered++;
        } catch (error, stack) {
          // Leave on disk so the next launch tries again. Eviction caps
          // damage if it never succeeds.
          _debugWarn('replay.entry', error, stack);
        }
      }
    } catch (error, stack) {
      _debugWarn('replay', error, stack);
    }
    return delivered;
  }

  Future<void> _evictOverflow() async {
    try {
      final entries = await _store.loadAll();
      if (entries.length <= _maxEntries) return;
      final excess = entries.length - _maxEntries;
      // `loadAll()` returns oldest first — drop from the front.
      for (var i = 0; i < excess; i++) {
        await _store.delete(entries[i].file);
      }
    } catch (error, stack) {
      _debugWarn('evictOverflow', error, stack);
    }
  }

  static void _debugWarn(String operation, Object error, StackTrace stack) {
    if (!kDebugMode) return;
    debugPrint('[shake_context] retry queue $operation failed: $error');
  }
}
