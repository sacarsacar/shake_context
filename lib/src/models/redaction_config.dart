import 'package:flutter/foundation.dart';

/// Privacy / size guardrails applied to captured network entries and
/// individual log messages.
///
/// Defaults are conservative: common auth and session header keys are
/// masked, request and response bodies are truncated to 2 KB, and any
/// single log message longer than 8 KB is truncated. Pass a custom
/// instance to [ShakeContext.recordNetwork] or to the
/// `ShakeDioInterceptor` constructor to widen or tighten the policy.
@immutable
class RedactionConfig {
  const RedactionConfig({
    this.redactedHeaderKeys = const {
      'authorization',
      'cookie',
      'set-cookie',
      'proxy-authorization',
      'x-api-key',
      'x-auth-token',
    },
    this.redactedBodyKeys = const {
      'password',
      'pass',
      'pwd',
      'token',
      'access_token',
      'refresh_token',
      'api_key',
      'apikey',
      'secret',
      'authorization',
    },
    this.maxBodyChars = 2048,
    this.maxLogChars = 8192,
    this.maskText = '«redacted»',
  });

  /// Header keys (case-insensitive) whose values are replaced with [maskText]
  /// before being stored on a [NetworkLog]. Match is exact, not substring.
  final Set<String> redactedHeaderKeys;

  /// JSON-ish body keys whose values are replaced with [maskText] before
  /// being stored. Applies a simple regex over the serialized body string —
  /// this is heuristic, not a JSON parser, but it catches the common shapes
  /// (`"password":"hunter2"`, `password=hunter2`, `"token": "abc"`).
  final Set<String> redactedBodyKeys;

  /// Maximum length, in characters, of request/response bodies stored on a
  /// [NetworkLog]. Excess is replaced with `… <N more chars>`. Set to
  /// `null` to skip truncation.
  final int? maxBodyChars;

  /// Maximum length, in characters, of any single log message. Excess is
  /// truncated with the same `… <N more chars>` suffix. Set to `null` to
  /// keep the full string (use with care — a single multi-MB line can
  /// dominate the buffer).
  final int? maxLogChars;

  /// Replacement text inserted in place of redacted values.
  final String maskText;

  /// No-op policy: nothing is masked or truncated. Useful for tests or
  /// for fully trusted environments.
  static const RedactionConfig disabled = RedactionConfig(
    redactedHeaderKeys: <String>{},
    redactedBodyKeys: <String>{},
    maxBodyChars: null,
    maxLogChars: null,
  );

  /// Return a copy of [headers] where any key listed in [redactedHeaderKeys]
  /// is replaced with [maskText]. Lookup is case-insensitive.
  Map<String, String> redactHeaders(Map<String, String> headers) {
    if (redactedHeaderKeys.isEmpty || headers.isEmpty) return headers;
    final lowered = redactedHeaderKeys.map((k) => k.toLowerCase()).toSet();
    return {
      for (final entry in headers.entries)
        entry.key: lowered.contains(entry.key.toLowerCase())
            ? maskText
            : entry.value,
    };
  }

  /// Apply body redaction + truncation to a request/response body string.
  String? redactBody(String? body) {
    if (body == null) return null;
    final masked = _maskBody(body);
    return _truncate(masked, maxBodyChars);
  }

  /// Apply truncation to a free-form log message.
  String truncateLog(String message) => _truncate(message, maxLogChars);

  String _maskBody(String body) {
    if (redactedBodyKeys.isEmpty) return body;
    var out = body;
    for (final key in redactedBodyKeys) {
      final escaped = RegExp.escape(key);
      // "key" : "value"   or   "key":"value"
      out = out.replaceAllMapped(
        RegExp('"$escaped"\\s*:\\s*"[^"]*"', caseSensitive: false),
        (_) => '"$key":"$maskText"',
      );
      // key=value (form-encoded, until & or end)
      out = out.replaceAllMapped(
        RegExp('(^|[&?])$escaped=[^&\\s]*', caseSensitive: false),
        (m) => '${m.group(1)}$key=$maskText',
      );
    }
    return out;
  }

  String _truncate(String body, int? limit) {
    if (limit == null || body.length <= limit) return body;
    final dropped = body.length - limit;
    return '${body.substring(0, limit)}… <$dropped more chars>';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RedactionConfig &&
        setEquals(other.redactedHeaderKeys, redactedHeaderKeys) &&
        setEquals(other.redactedBodyKeys, redactedBodyKeys) &&
        other.maxBodyChars == maxBodyChars &&
        other.maxLogChars == maxLogChars &&
        other.maskText == maskText;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(redactedHeaderKeys),
        Object.hashAllUnordered(redactedBodyKeys),
        maxBodyChars,
        maxLogChars,
        maskText,
      );
}
