import 'package:dio/dio.dart';

import '../../shake_context.dart';
import '../core/log_capture.dart';

/// Dio interceptor that pushes every request/response/error cycle into the
/// shake_context rolling network buffer. The captured [NetworkLog] entries
/// appear in the developer overlay's Network panel on shake.
///
/// Wire it up once at the Dio configuration site:
///
/// ```dart
/// import 'package:shake_context/dio.dart';
///
/// final dio = Dio()..interceptors.add(ShakeDioInterceptor());
/// ```
///
/// Headers and bodies are run through [RedactionConfig] before being
/// stored. Pass a custom [redaction] to widen or tighten the policy for
/// this interceptor only; otherwise it inherits the singleton policy on
/// `LogCapture.instance.redaction`.
class ShakeDioInterceptor extends Interceptor {
  ShakeDioInterceptor({
    this.captureRequestBody = true,
    this.captureResponseBody = true,
    this.captureHeaders = true,
    RedactionConfig? redaction,
  }) : _explicitRedaction = redaction;

  /// When `false`, request bodies are omitted from the captured entry.
  final bool captureRequestBody;

  /// When `false`, response bodies are omitted from the captured entry.
  final bool captureResponseBody;

  /// When `false`, no headers are captured at all (lighter, less debuggable).
  final bool captureHeaders;

  final RedactionConfig? _explicitRedaction;

  RedactionConfig get _redaction =>
      _explicitRedaction ?? LogCapture.instance.redaction;

  // Key under which the request's start time is stashed on
  // `RequestOptions.extra`. Riding on the request itself (rather than a
  // side-table keyed by identityHashCode) means the timing data is GC'd
  // with the request — even if another interceptor rejects/short-circuits
  // and neither onResponse nor onError ever fires for us.
  static const String _startKey = '_shakeContextStart';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now();
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start = _readStart(response.requestOptions);
    _record(
      method: response.requestOptions.method,
      url: response.requestOptions.uri.toString(),
      statusCode: response.statusCode,
      start: start,
      requestHeaders: _flattenHeaders(response.requestOptions.headers),
      responseHeaders: _flattenHeaders(response.headers.map),
      requestBodyRaw: response.requestOptions.data?.toString(),
      responseBodyRaw: response.data?.toString(),
      error: null,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final start = _readStart(err.requestOptions);
    _record(
      method: err.requestOptions.method,
      url: err.requestOptions.uri.toString(),
      statusCode: err.response?.statusCode,
      start: start,
      requestHeaders: _flattenHeaders(err.requestOptions.headers),
      responseHeaders:
          err.response == null ? null : _flattenHeaders(err.response!.headers.map),
      requestBodyRaw: err.requestOptions.data?.toString(),
      responseBodyRaw: err.response?.data?.toString(),
      error: err.message ?? err.type.name,
    );
    handler.next(err);
  }

  void _record({
    required String method,
    required String url,
    required int? statusCode,
    required DateTime? start,
    required Map<String, String>? requestHeaders,
    required Map<String, String>? responseHeaders,
    required String? requestBodyRaw,
    required String? responseBodyRaw,
    required String? error,
  }) {
    final redaction = _redaction;
    final duration = start == null
        ? null
        : DateTime.now().difference(start).inMilliseconds;
    ShakeContext.recordNetwork(NetworkLog(
      method: method,
      url: url,
      statusCode: statusCode,
      durationMs: duration,
      requestHeaders: captureHeaders && requestHeaders != null
          ? redaction.redactHeaders(requestHeaders)
          : null,
      responseHeaders: captureHeaders && responseHeaders != null
          ? redaction.redactHeaders(responseHeaders)
          : null,
      requestBody:
          captureRequestBody ? redaction.redactBody(requestBodyRaw) : null,
      responseBody:
          captureResponseBody ? redaction.redactBody(responseBodyRaw) : null,
      error: error,
      timestamp: start ?? DateTime.now(),
    ));
  }

  /// Read the start time stashed on `RequestOptions.extra` during
  /// [onRequest]. Returns `null` if a downstream interceptor swapped the
  /// request out or this interceptor was added after another already ran.
  DateTime? _readStart(RequestOptions options) {
    final raw = options.extra[_startKey];
    return raw is DateTime ? raw : null;
  }

  Map<String, String> _flattenHeaders(Map<String, dynamic> raw) {
    return {
      for (final entry in raw.entries)
        entry.key: entry.value is List
            ? (entry.value as List).join(', ')
            : entry.value.toString(),
    };
  }
}
