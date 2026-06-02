import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/log_entry.dart';
import '../models/network_log.dart';

/// Immutable snapshot of a session's rolling buffers, used as the unit of
/// persistence.
@immutable
class SessionSnapshot {
  const SessionSnapshot({
    required this.startedAt,
    required this.logs,
    required this.network,
  });

  /// When the persisted session began. Surfaces in the developer overlay
  /// header for the "Previous session" panels so the engineer can tell how
  /// stale the recovered data is.
  final DateTime startedAt;

  final List<LogEntry> logs;
  final List<NetworkLog> network;

  bool get isEmpty => logs.isEmpty && network.isEmpty;
}

/// Pluggable backing store for crash-recovery persistence.
///
/// Implementations must be safe against partial writes — a crash mid-write
/// must not corrupt the next [load] call. [FilePersistenceStore] satisfies
/// this with a write-to-temp-then-rename strategy.
///
/// All methods are best-effort: implementations should swallow I/O failures
/// rather than propagate them, because persistence is a debugging aid, not
/// load-bearing app behavior.
abstract class PersistenceStore {
  /// Read and delete any persisted snapshot. Returns `null` when no
  /// snapshot exists (first launch, or the previous session cleaned up).
  ///
  /// Deletion is intentional — without it, recovered entries would replay
  /// indefinitely until a clean exit. If the new session itself crashes,
  /// only its own logs are persisted; the previous run's data is already
  /// in memory as "recovered".
  Future<SessionSnapshot?> loadAndClear();

  /// Persist [snapshot] in full. Implementations should overwrite atomically.
  Future<void> save(SessionSnapshot snapshot);

  /// Persist [snapshot] synchronously. Called from error handlers where
  /// the process may be moments from death; the async path may not
  /// complete in time.
  void saveSync(SessionSnapshot snapshot);

  /// Discard any persisted snapshot. Called on clean shutdown by
  /// [LogCapture.disablePersistence].
  Future<void> clear();
}

/// File-backed [PersistenceStore]. Writes to
/// `<applicationSupportDirectory>/shake_context/session.json` via a
/// temp-and-rename to keep replacements atomic on POSIX.
class FilePersistenceStore implements PersistenceStore {
  FilePersistenceStore._(this._file);

  /// Resolve the canonical file path under
  /// `getApplicationSupportDirectory()`. Returns `null` on web (where the
  /// directory APIs aren't applicable) or if path_provider throws.
  static Future<FilePersistenceStore?> open() async {
    if (kIsWeb) return null;
    try {
      final dir = await getApplicationSupportDirectory();
      final sub = Directory('${dir.path}/shake_context');
      if (!await sub.exists()) {
        await sub.create(recursive: true);
      }
      return FilePersistenceStore._(File('${sub.path}/session.json'));
    } catch (error, stack) {
      _debugWarn('FilePersistenceStore.open', error, stack);
      return null;
    }
  }

  /// Test seam — point the store at an arbitrary file.
  @visibleForTesting
  factory FilePersistenceStore.forFile(File file) =>
      FilePersistenceStore._(file);

  final File _file;

  File get _tempFile => File('${_file.path}.tmp');

  @override
  Future<SessionSnapshot?> loadAndClear() async {
    try {
      if (!await _file.exists()) return null;
      final raw = await _file.readAsString();
      await _file.delete();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return _decodeSnapshot(decoded);
    } catch (error, stack) {
      // Corrupt file, decode failure, transient I/O — swallow and clear.
      _debugWarn('loadAndClear', error, stack);
      try {
        if (await _file.exists()) await _file.delete();
      } catch (cleanupError, cleanupStack) {
        _debugWarn('loadAndClear.cleanup', cleanupError, cleanupStack);
      }
      return null;
    }
  }

  @override
  Future<void> save(SessionSnapshot snapshot) async {
    try {
      final encoded = jsonEncode(_encodeSnapshot(snapshot));
      final tmp = _tempFile;
      await tmp.writeAsString(encoded, flush: true);
      await tmp.rename(_file.path);
    } catch (error, stack) {
      // Persistence is best-effort; never let it bring down the host app.
      _debugWarn('save', error, stack);
    }
  }

  @override
  void saveSync(SessionSnapshot snapshot) {
    try {
      final encoded = jsonEncode(_encodeSnapshot(snapshot));
      final tmp = _tempFile;
      tmp.writeAsStringSync(encoded, flush: true);
      tmp.renameSync(_file.path);
    } catch (error, stack) {
      // Same swallow policy as the async path.
      _debugWarn('saveSync', error, stack);
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (await _file.exists()) await _file.delete();
    } catch (error, stack) {
      _debugWarn('clear', error, stack);
    }
  }

  // ---- JSON shape ----

  static Map<String, dynamic> _encodeSnapshot(SessionSnapshot s) => {
        'startedAt': s.startedAt.toIso8601String(),
        'logs': s.logs.map(_encodeLog).toList(),
        'network': s.network.map(_encodeNetwork).toList(),
      };

  static SessionSnapshot _decodeSnapshot(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) =>
        v is String ? DateTime.tryParse(v) ?? DateTime.now() : DateTime.now();

    final logs = <LogEntry>[];
    final logsRaw = json['logs'];
    if (logsRaw is List) {
      for (final item in logsRaw) {
        if (item is Map<String, dynamic>) {
          final decoded = _decodeLog(item);
          if (decoded != null) logs.add(decoded);
        }
      }
    }

    final network = <NetworkLog>[];
    final netRaw = json['network'];
    if (netRaw is List) {
      for (final item in netRaw) {
        if (item is Map<String, dynamic>) {
          final decoded = _decodeNetwork(item);
          if (decoded != null) network.add(decoded);
        }
      }
    }

    return SessionSnapshot(
      startedAt: parseDate(json['startedAt']),
      logs: logs,
      network: network,
    );
  }

  /// Surface swallowed failures on `debugPrint` in debug builds so developers
  /// can see why persistence isn't sticking. No-op in release — best-effort
  /// stays best-effort and the host's console stays quiet.
  static void _debugWarn(String operation, Object error, StackTrace stack) {
    if (!kDebugMode) return;
    debugPrint('[shake_context] $operation failed: $error');
  }

  static Map<String, dynamic> _encodeLog(LogEntry e) => {
        'message': e.message,
        'level': e.level.name,
        if (e.source != null) 'source': e.source,
        if (e.stackTrace != null) 'stackTrace': e.stackTrace.toString(),
        'timestamp': e.timestamp.toIso8601String(),
      };

  static LogEntry? _decodeLog(Map<String, dynamic> j) {
    try {
      final levelName = j['level'] as String? ?? 'info';
      final level = LogLevel.values.firstWhere(
        (l) => l.name == levelName,
        orElse: () => LogLevel.info,
      );
      final ts = DateTime.tryParse(j['timestamp'] as String? ?? '') ??
          DateTime.now();
      final stack = j['stackTrace'] as String?;
      return LogEntry(
        message: j['message'] as String? ?? '',
        level: level,
        source: j['source'] as String?,
        stackTrace: stack == null ? null : StackTrace.fromString(stack),
        timestamp: ts,
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _encodeNetwork(NetworkLog e) => {
        'method': e.method,
        'url': e.url,
        if (e.statusCode != null) 'statusCode': e.statusCode,
        if (e.durationMs != null) 'durationMs': e.durationMs,
        if (e.requestHeaders != null) 'requestHeaders': e.requestHeaders,
        if (e.responseHeaders != null) 'responseHeaders': e.responseHeaders,
        if (e.requestBody != null) 'requestBody': e.requestBody,
        if (e.responseBody != null) 'responseBody': e.responseBody,
        if (e.error != null) 'error': e.error,
        'timestamp': e.timestamp.toIso8601String(),
      };

  static NetworkLog? _decodeNetwork(Map<String, dynamic> j) {
    try {
      Map<String, String>? decodeHeaders(dynamic raw) {
        if (raw is! Map) return null;
        return {
          for (final entry in raw.entries) entry.key.toString(): entry.value.toString(),
        };
      }

      return NetworkLog(
        method: j['method'] as String? ?? 'GET',
        url: j['url'] as String? ?? '',
        statusCode: j['statusCode'] as int?,
        durationMs: j['durationMs'] as int?,
        requestHeaders: decodeHeaders(j['requestHeaders']),
        responseHeaders: decodeHeaders(j['responseHeaders']),
        requestBody: j['requestBody'] as String?,
        responseBody: j['responseBody'] as String?,
        error: j['error'] as String?,
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}
