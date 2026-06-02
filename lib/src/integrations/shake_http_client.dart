import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../shake_context.dart';
import '../core/log_capture.dart';

/// `http`-package equivalent of `ShakeDioInterceptor`. Wrap your existing
/// `http.Client` with `ShakeHttpClient(inner)` and every request that flows
/// through it is recorded as a [NetworkLog].
///
/// ```dart
/// import 'package:http/http.dart' as http;
/// import 'package:shake_context/http.dart';
///
/// final client = ShakeHttpClient(http.Client());
/// await client.get(Uri.parse('https://api.example.com/items'));
/// ```
///
/// Headers and bodies are run through [RedactionConfig] before being
/// stored. Pass a custom [redaction] to override the singleton policy on
/// `LogCapture.instance.redaction`.
class ShakeHttpClient extends http.BaseClient {
  ShakeHttpClient(
    this._inner, {
    this.captureRequestBody = true,
    this.captureResponseBody = true,
    this.captureHeaders = true,
    RedactionConfig? redaction,
  }) : _explicitRedaction = redaction;

  final http.Client _inner;

  /// When `false`, request bodies are omitted from the captured entry.
  final bool captureRequestBody;

  /// When `false`, response bodies are omitted from the captured entry.
  final bool captureResponseBody;

  /// When `false`, no headers are captured at all.
  final bool captureHeaders;

  final RedactionConfig? _explicitRedaction;

  RedactionConfig get _redaction =>
      _explicitRedaction ?? LogCapture.instance.redaction;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final start = DateTime.now();
    final method = request.method;
    final url = request.url.toString();
    final reqHeaders = captureHeaders ? Map<String, String>.from(request.headers) : null;
    final reqBody = captureRequestBody ? await _readRequestBody(request) : null;

    try {
      final response = await _inner.send(request);
      // Buffer the response body so we can both record it and pass an
      // intact stream back to the caller. Streaming responses lose this
      // property — there's no way to tee a stream once consumed.
      final bytes = await response.stream.toBytes();
      final responseBody = captureResponseBody ? _safeDecode(bytes) : null;

      _emit(
        method: method,
        url: url,
        statusCode: response.statusCode,
        start: start,
        requestHeaders: reqHeaders,
        responseHeaders:
            captureHeaders ? Map<String, String>.from(response.headers) : null,
        requestBodyRaw: reqBody,
        responseBodyRaw: responseBody,
        error: null,
      );

      return http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (error) {
      _emit(
        method: method,
        url: url,
        statusCode: null,
        start: start,
        requestHeaders: reqHeaders,
        responseHeaders: null,
        requestBodyRaw: reqBody,
        responseBodyRaw: null,
        error: error.toString(),
      );
      rethrow;
    }
  }

  void _emit({
    required String method,
    required String url,
    required int? statusCode,
    required DateTime start,
    required Map<String, String>? requestHeaders,
    required Map<String, String>? responseHeaders,
    required String? requestBodyRaw,
    required String? responseBodyRaw,
    required String? error,
  }) {
    final redaction = _redaction;
    final duration = DateTime.now().difference(start).inMilliseconds;
    ShakeContext.recordNetwork(NetworkLog(
      method: method,
      url: url,
      statusCode: statusCode,
      durationMs: duration,
      requestHeaders:
          requestHeaders == null ? null : redaction.redactHeaders(requestHeaders),
      responseHeaders: responseHeaders == null
          ? null
          : redaction.redactHeaders(responseHeaders),
      requestBody: redaction.redactBody(requestBodyRaw),
      responseBody: redaction.redactBody(responseBodyRaw),
      error: error,
      timestamp: start,
    ));
  }

  Future<String?> _readRequestBody(http.BaseRequest request) async {
    if (request is http.Request) {
      return request.body;
    }
    if (request is http.MultipartRequest) {
      // Multipart bodies are streaming and may include file bytes. Surface
      // a compact summary rather than dumping arbitrary binary into the buffer.
      return '«multipart: ${request.fields.length} fields, '
          '${request.files.length} files»';
    }
    return null;
  }

  String _safeDecode(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return '«${bytes.length} bytes binary»';
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
