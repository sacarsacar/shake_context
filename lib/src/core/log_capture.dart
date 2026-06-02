import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import '../models/network_log.dart';
import '../models/redaction_config.dart';
import 'persistence_store.dart';

/// Process-wide rolling buffer for everything the package can intercept.
///
/// Owned as a singleton because the interception points run *before* any
/// widget mounts: the `runZoned` `print` hook, `FlutterError.onError`, and
/// `PlatformDispatcher.onError` are all installed inside
/// `ShakeContext.guard`, which the host calls from `main`. The widget-tree
/// `ContextCapturer` then drains from here on shake.
///
/// All public methods are safe to call on any isolate that shares this
/// instance — in practice the main isolate. Buffers use `ListQueue` so
/// eviction is O(1) when the cap is reached.
class LogCapture {
  LogCapture._();

  /// Singleton handle. Tests can clear state via [reset].
  static final LogCapture instance = LogCapture._();

  /// Maximum number of [LogEntry] rows retained. Older entries are evicted.
  int logBufferSize = 200;

  /// Maximum number of [NetworkLog] rows retained.
  int networkBufferSize = 50;

  /// Redaction policy applied to log messages before they enter the buffer.
  /// Override on the singleton (e.g. `LogCapture.instance.redaction = ...`)
  /// to widen or tighten the policy globally.
  RedactionConfig redaction = const RedactionConfig();

  /// Debounce window for the async persistence write. Set short enough to
  /// minimise data loss on crash, long enough to avoid I/O storms under
  /// heavy logging.
  Duration persistenceDebounce = const Duration(milliseconds: 500);

  PersistenceStore? _store;
  DateTime _sessionStartedAt = DateTime.now();
  Timer? _persistTimer;
  bool _persistScheduled = false;

  /// Snapshot recovered from a previous session. Populated by
  /// [enablePersistence] when [PersistenceStore.loadAndClear] returns
  /// non-null. Drained by [ContextCapturer] alongside the live buffers.
  SessionSnapshot? recoveredSession;

  final ListQueue<LogEntry> _logs = ListQueue<LogEntry>();
  final ListQueue<NetworkLog> _network = ListQueue<NetworkLog>();

  DebugPrintCallback? _previousDebugPrint;
  bool _debugPrintHooked = false;

  /// Wrap [debugPrint] so every line is added as an [LogLevel.info] entry
  /// tagged `source: 'debugPrint'`. Safe to call repeatedly; no-op on
  /// subsequent calls. Chained on top of the previous callback so existing
  /// console output is preserved.
  void hookDebugPrint() {
    if (_debugPrintHooked) return;
    _previousDebugPrint = debugPrint;
    debugPrint = _capturingDebugPrint;
    _debugPrintHooked = true;
  }

  /// Restore the previous [debugPrint] callback. Safe to call repeatedly.
  void unhookDebugPrint() {
    if (!_debugPrintHooked) return;
    if (debugPrint == _capturingDebugPrint && _previousDebugPrint != null) {
      debugPrint = _previousDebugPrint!;
    }
    _previousDebugPrint = null;
    _debugPrintHooked = false;
  }

  void _capturingDebugPrint(String? message, {int? wrapWidth}) {
    if (message != null) {
      _push(LogEntry(
        message: message,
        level: LogLevel.info,
        source: 'debugPrint',
      ));
    }
    _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
  }

  /// Record a `print(...)` line intercepted by the zone hook installed in
  /// `ShakeContext.guard`. The zone forwards to the parent's print so stdout
  /// is unaffected — this method only adds the buffered entry.
  void recordPrint(String line) {
    _push(LogEntry(
      message: line,
      level: LogLevel.info,
      source: 'print',
    ));
  }

  /// Public log API for host code. Recommended replacement for
  /// `developer.log` calls, which cannot be intercepted from Dart.
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? source,
    StackTrace? stackTrace,
  }) {
    _push(LogEntry(
      message: message,
      level: level,
      source: source ?? 'log',
      stackTrace: stackTrace,
    ));
  }

  /// Record an uncaught Flutter framework error. Called from the
  /// `FlutterError.onError` chain installed in `ShakeContext.guard`.
  void recordFlutterError(FlutterErrorDetails details) {
    _push(LogEntry(
      message: details.exceptionAsString(),
      level: LogLevel.error,
      source: 'FlutterError',
      stackTrace: details.stack,
    ));
  }

  /// Record an uncaught async error from `PlatformDispatcher.onError`.
  void recordUncaughtError(Object error, StackTrace stack, {String? source}) {
    _push(LogEntry(
      message: error.toString(),
      level: LogLevel.error,
      source: source ?? 'uncaught',
      stackTrace: stack,
    ));
  }

  /// Append a network log entry. Called by `ShakeDioInterceptor` or any
  /// host-provided HTTP adapter.
  void recordNetwork(NetworkLog entry) {
    if (_network.length >= networkBufferSize) {
      _network.removeFirst();
    }
    _network.add(entry);
    _onMutated(isError: entry.isFailure);
  }

  /// Attach a [PersistenceStore]. Loads any prior session (exposing it via
  /// [recoveredSession]), then enables periodic + on-error writes for the
  /// active session.
  ///
  /// Safe to call multiple times — subsequent calls replace the store and
  /// reload the recovered snapshot. Always succeeds; a missing or unusable
  /// store simply means [recoveredSession] stays null.
  Future<void> enablePersistence(PersistenceStore? store) async {
    _cancelPendingWrite();
    _store = store;
    _sessionStartedAt = DateTime.now();
    if (store == null) {
      recoveredSession = null;
      return;
    }
    try {
      final snapshot = await store.loadAndClear();
      if (snapshot != null && !snapshot.isEmpty) {
        recoveredSession = snapshot;
      }
    } catch (error, stack) {
      recoveredSession = null;
      _debugWarn('enablePersistence.loadAndClear', error, stack);
    }
    // Persist the (empty) new session immediately so that even a crash
    // before the first log line produces a recoverable file marker. We
    // await this — the write is small, and finishing it before
    // [enablePersistence] returns guarantees no async write is in flight
    // that could overwrite a later sync error-flush.
    try {
      await store.save(_currentSnapshot());
    } catch (error, stack) {
      _debugWarn('enablePersistence.save', error, stack);
    }
  }

  /// Detach the active store and discard its persisted snapshot. Intended
  /// for clean-shutdown paths; tests can use it to reset state.
  Future<void> disablePersistence() async {
    _cancelPendingWrite();
    final store = _store;
    _store = null;
    if (store != null) {
      await store.clear();
    }
  }

  void _onMutated({required bool isError}) {
    final store = _store;
    if (store == null) return;
    if (isError) {
      // Synchronous write — the process may be moments from death and the
      // event-loop tick that would run the async write may never arrive.
      _cancelPendingWrite();
      try {
        store.saveSync(_currentSnapshot());
      } catch (error, stack) {
        _debugWarn('saveSync (error-flush)', error, stack);
      }
      return;
    }
    if (_persistScheduled) return;
    _persistScheduled = true;
    _persistTimer = Timer(persistenceDebounce, () {
      _persistScheduled = false;
      _persistTimer = null;
      final s = _store;
      if (s == null) return;
      unawaited(s.save(_currentSnapshot()));
    });
  }

  void _cancelPendingWrite() {
    _persistTimer?.cancel();
    _persistTimer = null;
    _persistScheduled = false;
  }

  SessionSnapshot _currentSnapshot() => SessionSnapshot(
        startedAt: _sessionStartedAt,
        logs: List<LogEntry>.of(_logs),
        network: List<NetworkLog>.of(_network),
      );

  /// Force any pending debounced write to flush now. Tests use this to
  /// avoid relying on Timer scheduling.
  @visibleForTesting
  Future<void> flushPersistence() async {
    final store = _store;
    if (store == null) return;
    _cancelPendingWrite();
    await store.save(_currentSnapshot());
  }

  void _push(LogEntry entry) {
    if (_logs.length >= logBufferSize) {
      _logs.removeFirst();
    }
    final truncated = redaction.truncateLog(entry.message);
    final stored = identical(truncated, entry.message)
        ? entry
        : LogEntry(
            message: truncated,
            level: entry.level,
            source: entry.source,
            stackTrace: entry.stackTrace,
            timestamp: entry.timestamp,
          );
    _logs.add(stored);
    _onMutated(isError: stored.level == LogLevel.error);
  }

  /// Snapshot and clear the log buffer. Called by `ContextCapturer` on shake.
  List<LogEntry> drainLogs() {
    final out = List<LogEntry>.of(_logs);
    _logs.clear();
    return out;
  }

  /// Snapshot and clear the network buffer.
  List<NetworkLog> drainNetwork() {
    final out = List<NetworkLog>.of(_network);
    _network.clear();
    return out;
  }

  /// Peek at the current log buffer without draining it. Test helper.
  @visibleForTesting
  List<LogEntry> get bufferedLogs => List.unmodifiable(_logs);

  /// Peek at the current network buffer without draining it. Test helper.
  @visibleForTesting
  List<NetworkLog> get bufferedNetwork => List.unmodifiable(_network);

  /// Wipe state and unhook `debugPrint`. Mostly for tests; production code
  /// should never need this because the package outlives the shake events.
  void reset() {
    unhookDebugPrint();
    _cancelPendingWrite();
    _store = null;
    recoveredSession = null;
    _sessionStartedAt = DateTime.now();
    _logs.clear();
    _network.clear();
    logBufferSize = 200;
    networkBufferSize = 50;
    redaction = const RedactionConfig();
    persistenceDebounce = const Duration(milliseconds: 500);
  }
}

/// Surface a swallowed failure on `debugPrint` in debug builds so developers
/// can see why a best-effort operation (persistence write, screenshot, etc.)
/// silently dropped a value. In release builds this is a no-op — the
/// best-effort contract holds and no diagnostic noise reaches the console.
///
/// Routed through `debugPrint` (not `LogCapture.log`) on purpose: recording
/// a persistence failure *into* the buffer that triggered the failure risks
/// recursing if the cause was buffer corruption.
void _debugWarn(String operation, Object error, StackTrace stack) {
  if (!kDebugMode) return;
  debugPrint('[shake_context] $operation failed: $error');
}

/// Top-level helper used by `ShakeContext.guard` to wrap the app entry point
/// in a `Zone` whose `print` redirects into [LogCapture]. Kept here (rather
/// than on the widget) so it can run before `WidgetsFlutterBinding` is
/// initialised — that ordering is what lets us catch boot-time `print`
/// output.
///
/// Crucially, this does **not** install a `runZonedGuarded` error handler.
/// Doing so would intercept every uncaught async error in the host app and
/// prevent it from reaching `PlatformDispatcher.onError` — which is what
/// Crashlytics, Sentry, and friends hook into. Instead, errors are captured
/// via the `PlatformDispatcher.onError` chain installed in
/// `ShakeContext._installGlobalErrorHandlers`, which records *and* forwards
/// to whatever handler the host already had.
T runWithLogCapture<T>(T Function() body, {required bool captureUncaught}) {
  // `captureUncaught` only controls the global error-handler install (done
  // by the caller). The zone itself is uniform regardless.
  final spec = ZoneSpecification(
    print: (self, parent, zone, line) {
      LogCapture.instance.recordPrint(line);
      parent.print(zone, line);
    },
  );
  return Zone.current.fork(specification: spec).run(body);
}
