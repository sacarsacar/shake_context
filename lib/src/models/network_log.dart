import 'package:flutter/foundation.dart';

/// One captured HTTP request/response cycle.
///
/// Produced by `ShakeDioInterceptor` (see `package:shake_context/dio.dart`)
/// or any custom adapter the host wires up via
/// [ShakeContext.recordNetwork]. The developer overlay shows these in a
/// dedicated panel, separate from text logs, so request bodies and status
/// codes stay scannable.
@immutable
class NetworkLog {
  NetworkLog({
    required this.method,
    required this.url,
    this.statusCode,
    this.durationMs,
    Map<String, String>? requestHeaders,
    Map<String, String>? responseHeaders,
    this.requestBody,
    this.responseBody,
    this.error,
    DateTime? timestamp,
  })  : requestHeaders =
            requestHeaders == null ? null : Map.unmodifiable(requestHeaders),
        responseHeaders =
            responseHeaders == null ? null : Map.unmodifiable(responseHeaders),
        timestamp = timestamp ?? DateTime.now();

  /// HTTP verb — `GET`, `POST`, etc. Uppercased by convention but not enforced.
  final String method;

  /// Full request URL including query string.
  final String url;

  /// Response status code, when the request completed.
  /// Null while in-flight or on transport error.
  final int? statusCode;

  /// Wall-clock duration of the request in milliseconds, when known.
  final int? durationMs;

  /// Request headers as captured by the adapter. The adapter is expected to
  /// apply [RedactionConfig] before passing them here — the model itself
  /// performs no masking. Null when the adapter did not capture headers.
  final Map<String, String>? requestHeaders;

  /// Response headers as captured by the adapter. Same redaction guidance
  /// as [requestHeaders].
  final Map<String, String>? responseHeaders;

  /// Request body as a string, when one was sent and the adapter chose to
  /// serialise it. Adapters should run the body through
  /// [RedactionConfig.redactBody] before passing it here.
  final String? requestBody;

  /// Response body as a string. Same redaction guidance as [requestBody].
  final String? responseBody;

  /// Error message for transport-level failures (timeouts, DNS, cancelled).
  /// Null for any response that came back, even a non-2xx one.
  final String? error;

  /// When the request was logged (start time, as observed by the adapter).
  final DateTime timestamp;

  /// True when the cycle did not complete with a 2xx status.
  bool get isFailure =>
      error != null || (statusCode != null && (statusCode! < 200 || statusCode! >= 300));

  /// JSON-serializable representation. Null/empty optional fields are
  /// omitted so the payload stays compact; required fields and timestamps
  /// are always present. Safe to pass to `jsonEncode` without further
  /// conversion, assuming the adapter passed JSON-compatible header values.
  Map<String, dynamic> toJson() => {
        'method': method,
        'url': url,
        if (statusCode != null) 'statusCode': statusCode,
        if (durationMs != null) 'durationMs': durationMs,
        if (requestHeaders != null) 'requestHeaders': requestHeaders,
        if (responseHeaders != null) 'responseHeaders': responseHeaders,
        if (requestBody != null) 'requestBody': requestBody,
        if (responseBody != null) 'responseBody': responseBody,
        if (error != null) 'error': error,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Inverse of [toJson]. Defensive — wrong-typed or missing fields fall
  /// back to their defaults rather than throwing.
  factory NetworkLog.fromJson(Map<String, dynamic> json) {
    Map<String, String>? decodeHeaders(dynamic raw) {
      if (raw is! Map) return null;
      return <String, String>{
        for (final entry in raw.entries)
          entry.key.toString(): entry.value.toString(),
      };
    }

    return NetworkLog(
      method: json['method'] is String ? json['method'] as String : 'GET',
      url: json['url'] is String ? json['url'] as String : '',
      statusCode: json['statusCode'] is int ? json['statusCode'] as int : null,
      durationMs: json['durationMs'] is int ? json['durationMs'] as int : null,
      requestHeaders: decodeHeaders(json['requestHeaders']),
      responseHeaders: decodeHeaders(json['responseHeaders']),
      requestBody:
          json['requestBody'] is String ? json['requestBody'] as String : null,
      responseBody: json['responseBody'] is String
          ? json['responseBody'] as String
          : null,
      error: json['error'] is String ? json['error'] as String : null,
      timestamp: json['timestamp'] is String
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NetworkLog &&
        other.method == method &&
        other.url == url &&
        other.statusCode == statusCode &&
        other.durationMs == durationMs &&
        mapEquals(other.requestHeaders, requestHeaders) &&
        mapEquals(other.responseHeaders, responseHeaders) &&
        other.requestBody == requestBody &&
        other.responseBody == responseBody &&
        other.error == error &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode => Object.hash(
        method,
        url,
        statusCode,
        durationMs,
        requestHeaders == null
            ? null
            : Object.hashAllUnordered(requestHeaders!.entries.map((e) => e.key)),
        responseHeaders == null
            ? null
            : Object.hashAllUnordered(
                responseHeaders!.entries.map((e) => e.key)),
        requestBody,
        responseBody,
        error,
        timestamp,
      );
}
