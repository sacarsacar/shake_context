import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shake_context/shake_context.dart';

/// Set this to your development machine's LAN IP when testing on a **physical
/// device** (iPhone or Android phone). The phone can't reach your Mac via
/// `localhost` — that points at the phone itself. Find it on macOS with
/// `ipconfig getifaddr en0`. The phone and the Mac must be on the same network.
///
/// Leave it `''` (empty) for simulators / emulators / desktop, which reach the
/// host directly (localhost, or `10.0.2.2` on the Android emulator).
const String lanHostOverride = '';

/// Where the local `test_backend/server.dart` is reachable from the running
/// app.
Uri get backendEndpoint {
  final String host;
  if (lanHostOverride.isNotEmpty) {
    host = lanHostOverride;
  } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    host = '10.0.2.2'; // Android emulator → host machine's loopback
  } else {
    host = 'localhost'; // iOS simulator / macOS / desktop / web
  }
  return Uri.parse('http://$host:8080/report');
}

/// Result of an upload attempt, surfaced to the UI so the example can show a
/// "delivered / failed" SnackBar.
class UploadResult {
  const UploadResult.ok(this.statusCode)
      : success = true,
        error = null;
  const UploadResult.failed(this.error)
      : success = false,
        statusCode = null;

  final bool success;
  final int? statusCode;
  final Object? error;
}

/// POST a [ReportPayload] to the local test backend as a single JSON blob
/// with images base64-encoded inline (`includeImages: true`).
///
/// This mirrors the README's "JSON-only webhook" recipe. For production you'd
/// usually prefer the multipart path (images out-of-band) — see the README's
/// "Sending the report" section — but inline JSON keeps this demo backend to
/// a single `jsonDecode`.
Future<UploadResult> uploadReport(ReportPayload payload) async {
  try {
    final body = jsonEncode(payload.toJson(includeImages: true));
    final resp = await http
        .post(
          backendEndpoint,
          headers: const {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode >= 400) {
      return UploadResult.failed('HTTP ${resp.statusCode}');
    }
    return UploadResult.ok(resp.statusCode);
  } catch (e) {
    // Surfaced to the user. Throwing here instead would let shake_context's
    // retry queue (if enabled) capture the payload — see README.
    return UploadResult.failed(e);
  }
}
