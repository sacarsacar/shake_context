import 'package:flutter/foundation.dart';

/// Severity of a captured [LogEntry].
///
/// The level is assigned by the capture source — `print`, `debugPrint`, and
/// any text the host app passes through [ShakeContext.log] without a level
/// land as [info]. Entries produced by `FlutterError.onError` and
/// `PlatformDispatcher.onError` are tagged [error]. Other levels are only
/// produced when the host opts in via [ShakeContext.log].
enum LogLevel { debug, info, warning, error }

/// One line in the rolling log buffer.
///
/// Carries enough structure for the developer overlay to color-code by
/// severity and surface the origin of the line — without the package having
/// to guess the level from the text.
@immutable
class LogEntry {
  LogEntry({
    required this.message,
    this.level = LogLevel.info,
    this.source,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Raw line as emitted by the source.
  final String message;

  /// Severity. See [LogLevel] for how each value gets assigned.
  final LogLevel level;

  /// Free-form origin tag — `'debugPrint'`, `'print'`, `'FlutterError'`,
  /// `'PlatformDispatcher'`, or whatever the host passed to
  /// [ShakeContext.log]. Useful for filtering in the overlay.
  final String? source;

  /// Stack trace for error-level entries from the global error handlers.
  /// Null for plain log lines.
  final StackTrace? stackTrace;

  /// When the line was captured.
  final DateTime timestamp;

  /// JSON-serializable representation. Timestamps are ISO 8601 strings,
  /// the level is its lowercase name, and stack traces are flattened to
  /// strings — safe to pass to `jsonEncode` without further conversion.
  Map<String, dynamic> toJson() => {
        'message': message,
        'level': level.name,
        if (source != null) 'source': source,
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
        'timestamp': timestamp.toIso8601String(),
      };

  /// Inverse of [toJson]. Defensive — wrong-typed or missing fields fall
  /// back to their defaults rather than throwing, so a partly-corrupt queue
  /// file still yields a usable entry instead of taking the whole batch
  /// down.
  factory LogEntry.fromJson(Map<String, dynamic> json) {
    final levelRaw = json['level'];
    final level = LogLevel.values.firstWhere(
      (l) => l.name == levelRaw,
      orElse: () => LogLevel.info,
    );
    final stackRaw = json['stackTrace'];
    return LogEntry(
      message: json['message'] is String ? json['message'] as String : '',
      level: level,
      source: json['source'] is String ? json['source'] as String : null,
      stackTrace:
          stackRaw is String ? StackTrace.fromString(stackRaw) : null,
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LogEntry &&
        other.message == message &&
        other.level == level &&
        other.source == source &&
        other.stackTrace.toString() == stackTrace.toString() &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(
        message,
        level,
        source,
        stackTrace?.toString(),
        timestamp,
      );
}
