// A tiny, zero-dependency bug-report receiver for manually verifying
// shake_context end-to-end.
//
// It accepts the JSON a `ReportPayload.toJson(includeImages: true)` produces,
// keeps the reports in memory, prints a summary to the console, and serves a
// live web dashboard that renders the description, device info, logs, network
// entries, and attached screenshots.
//
// Run it with the plain Dart VM — no `pub get`, no pubspec needed:
//
//   dart run test_backend/server.dart
//
// Then open http://localhost:8080 in a browser and submit a report from the
// example app (which POSTs to this server). See test_backend/README.md.

import 'dart:convert';
import 'dart:io';

const _port = 8080;

/// Newest-first list of received reports. In memory only — restarting the
/// server clears them.
final List<Map<String, dynamic>> _reports = [];

Future<void> main() async {
  // Bind dual-stack (IPv6 + IPv4 via `v6Only: false`). On macOS `localhost`
  // resolves to IPv6 `::1` first, so an IPv4-only bind (`anyIPv4`) gets
  // "connection refused" from clients that dial `localhost` — even though the
  // server is up. Listening on `anyIPv6` with v6Only off covers both.
  final server =
      await HttpServer.bind(InternetAddress.anyIPv6, _port, v6Only: false);
  stdout.writeln('┌──────────────────────────────────────────────────────────┐');
  stdout.writeln('│  shake_context test backend                                │');
  stdout.writeln('│                                                            │');
  stdout.writeln('│  Dashboard:  http://localhost:$_port                          │');
  stdout.writeln('│  POST here:  http://localhost:$_port/report                   │');
  stdout.writeln('│  Android emulator → use http://10.0.2.2:$_port                │');
  stdout.writeln('│                                                            │');
  stdout.writeln('│  Waiting for reports… (Ctrl-C to stop)                     │');
  stdout.writeln('└──────────────────────────────────────────────────────────┘');

  await for (final req in server) {
    try {
      await _handle(req);
    } catch (e, st) {
      stderr.writeln('Request error: $e\n$st');
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    }
  }
}

Future<void> _handle(HttpRequest req) async {
  final res = req.response;
  // Permissive CORS so a Flutter-web build can POST here too.
  res.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    ..set('Access-Control-Allow-Headers', 'Content-Type');

  final path = req.uri.path;

  if (req.method == 'OPTIONS') {
    res.statusCode = HttpStatus.noContent;
    return res.close();
  }

  if (req.method == 'POST' && path == '/report') {
    final body = await utf8.decoder.bind(req).join();
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      res.statusCode = HttpStatus.badRequest;
      res.write('{"ok":false,"error":"invalid JSON"}');
      return res.close();
    }
    payload['_receivedAt'] = DateTime.now().toIso8601String();
    _reports.insert(0, payload);
    _printSummary(payload);
    res
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write('{"ok":true}');
    return res.close();
  }

  if (req.method == 'POST' && path == '/clear') {
    _reports.clear();
    stdout.writeln('— Reports cleared —');
    res.statusCode = HttpStatus.ok;
    return res.close();
  }

  if (req.method == 'GET' && path == '/reports.json') {
    res
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(_reports));
    return res.close();
  }

  if (req.method == 'GET' && path == '/') {
    res
      ..headers.contentType = ContentType.html
      ..write(_dashboardHtml());
    return res.close();
  }

  res.statusCode = HttpStatus.notFound;
  return res.close();
}

void _printSummary(Map<String, dynamic> p) {
  final meta = (p['metadata'] as Map?) ?? const {};
  final logs = (meta['logs'] as List?) ?? const [];
  final net = (meta['networkLogs'] as List?) ?? const [];
  stdout.writeln('');
  stdout.writeln('── Report #${_reports.length} received ─────────────────────');
  stdout.writeln('  mode:        ${p['mode']}');
  stdout.writeln('  description: ${(p['userDescription'] as String?)?.trim().isEmpty ?? true ? '(none)' : p['userDescription']}');
  stdout.writeln('  images:      ${p['imageCount'] ?? (p['images'] as List?)?.length ?? 0}');
  stdout.writeln('  route:       ${meta['currentRoute'] ?? '(none)'}');
  stdout.writeln('  logs:        ${logs.length}');
  stdout.writeln('  network:     ${net.length}');
  if (p['extras'] != null) stdout.writeln('  extras:      ${jsonEncode(p['extras'])}');
  stdout.writeln('  → open http://localhost:$_port to inspect');
}

String _dashboardHtml() {
  final reportsJson = jsonEncode(_reports);
  // The dashboard renders entirely client-side from the embedded JSON, then
  // polls /reports.json every 3s so new submissions show up without a manual
  // reload.
  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>shake_context — received reports</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; background: #0f1115; color: #e7e9ee; }
  header { position: sticky; top: 0; background: #161922; border-bottom: 1px solid #262a36; padding: 14px 20px; display: flex; align-items: center; gap: 14px; }
  header h1 { font-size: 16px; margin: 0; }
  header .count { color: #8b90a0; font-size: 13px; }
  header button { margin-left: auto; background: #2a2f3d; color: #e7e9ee; border: 1px solid #3a4150; border-radius: 7px; padding: 6px 12px; cursor: pointer; }
  header button:hover { background: #343b4c; }
  main { padding: 20px; max-width: 1100px; margin: 0 auto; }
  .empty { color: #8b90a0; text-align: center; padding: 80px 20px; }
  .report { background: #161922; border: 1px solid #262a36; border-radius: 12px; margin-bottom: 18px; overflow: hidden; }
  .report > .top { display: flex; align-items: center; gap: 10px; padding: 14px 16px; border-bottom: 1px solid #262a36; flex-wrap: wrap; }
  .badge { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .04em; padding: 3px 9px; border-radius: 20px; }
  .badge.developer { background: #1d3a5f; color: #7fb6ff; }
  .badge.production { background: #1d4d2f; color: #74e39a; }
  .top .when { color: #8b90a0; font-size: 12px; }
  .top .meta-chip { background: #20242f; border: 1px solid #2c3140; border-radius: 6px; padding: 2px 8px; font-size: 12px; color: #aeb3c2; }
  .section { padding: 12px 16px; border-top: 1px solid #20242f; }
  .section h3 { margin: 0 0 8px; font-size: 12px; text-transform: uppercase; letter-spacing: .05em; color: #8b90a0; }
  .desc { font-size: 15px; white-space: pre-wrap; }
  .desc.none { color: #6b7080; font-style: italic; }
  .imgs { display: flex; gap: 10px; flex-wrap: wrap; }
  .imgs img { max-height: 240px; border-radius: 8px; border: 1px solid #2c3140; background: #fff; }
  table.kv { border-collapse: collapse; width: 100%; }
  table.kv td { padding: 3px 10px 3px 0; vertical-align: top; }
  table.kv td.k { color: #8b90a0; white-space: nowrap; }
  table.kv td.v { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; word-break: break-all; }
  .log { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12.5px; padding: 2px 0; border-bottom: 1px solid #1b1f29; }
  .lvl { display: inline-block; width: 64px; font-weight: 700; }
  .lvl.error { color: #ff6b6b; } .lvl.warning { color: #ffb454; } .lvl.info { color: #74e39a; } .lvl.debug { color: #8b90a0; }
  .net { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12.5px; padding: 4px 0; border-bottom: 1px solid #1b1f29; }
  .net .m { font-weight: 700; color: #7fb6ff; }
  .net .ok { color: #74e39a; } .net .warn { color: #ffb454; } .net .err { color: #ff6b6b; }
  details summary { cursor: pointer; color: #8b90a0; font-size: 12px; }
  pre { background: #11141b; padding: 8px 10px; border-radius: 6px; overflow: auto; font-size: 12px; margin: 6px 0 0; }
</style>
</head>
<body>
<header>
  <h1>🐛 shake_context</h1>
  <span class="count" id="count"></span>
  <button onclick="clearReports()">Clear</button>
</header>
<main id="root"></main>
<script>
let reports = $reportsJson;

function esc(s) { return String(s == null ? '' : s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c])); }

function kvTable(obj) {
  const keys = Object.keys(obj || {});
  if (!keys.length) return '<span style="color:#6b7080">(empty)</span>';
  return '<table class="kv">' + keys.map(k =>
    '<tr><td class="k">' + esc(k) + '</td><td class="v">' + esc(typeof obj[k] === 'object' ? JSON.stringify(obj[k]) : obj[k]) + '</td></tr>'
  ).join('') + '</table>';
}

function render() {
  document.getElementById('count').textContent = reports.length + ' report' + (reports.length === 1 ? '' : 's') + ' received';
  const root = document.getElementById('root');
  if (!reports.length) { root.innerHTML = '<div class="empty">No reports yet.<br>Submit one from the example app — it should appear here within a few seconds.</div>'; return; }
  root.innerHTML = reports.map(r => {
    const meta = r.metadata || {};
    const logs = meta.logs || [];
    const net = meta.networkLogs || [];
    const imgs = r.images || [];
    let html = '<div class="report">';
    html += '<div class="top">';
    html += '<span class="badge ' + esc(r.mode) + '">' + esc(r.mode) + '</span>';
    if (meta.currentRoute) html += '<span class="meta-chip">route: ' + esc(meta.currentRoute) + '</span>';
    html += '<span class="meta-chip">' + (r.imageCount != null ? r.imageCount : imgs.length) + ' image(s)</span>';
    html += '<span class="meta-chip">' + logs.length + ' log(s)</span>';
    html += '<span class="meta-chip">' + net.length + ' network</span>';
    html += '<span class="when">' + esc(r._receivedAt) + '</span>';
    html += '</div>';

    const desc = (r.userDescription || '').trim();
    html += '<div class="section"><h3>Description</h3><div class="desc' + (desc ? '' : ' none') + '">' + (desc ? esc(desc) : '(no description)') + '</div></div>';

    if (imgs.length) {
      html += '<div class="section"><h3>Attachments</h3><div class="imgs">' +
        imgs.map(b64 => '<img src="data:image/png;base64,' + b64 + '">').join('') + '</div></div>';
    }

    if (r.extras) html += '<div class="section"><h3>Extras</h3>' + kvTable(r.extras) + '</div>';
    if (meta.deviceInfo && Object.keys(meta.deviceInfo).length) html += '<div class="section"><h3>Device info</h3>' + kvTable(meta.deviceInfo) + '</div>';

    if (logs.length) {
      html += '<div class="section"><h3>Logs (' + logs.length + ')</h3>' + logs.map(l =>
        '<div class="log"><span class="lvl ' + esc(l.level) + '">' + esc(l.level) + '</span>' +
        (l.source ? '<span style="color:#8b90a0">[' + esc(l.source) + ']</span> ' : '') + esc(l.message) +
        (l.stackTrace ? '<details><summary>stack</summary><pre>' + esc(l.stackTrace) + '</pre></details>' : '') +
        '</div>'
      ).join('') + '</div>';
    }

    if (net.length) {
      html += '<div class="section"><h3>Network (' + net.length + ')</h3>' + net.map(n => {
        const code = n.statusCode;
        const cls = n.error ? 'err' : (code >= 400 ? 'warn' : 'ok');
        const status = n.error ? 'ERR' : (code != null ? code : '—');
        return '<div class="net"><span class="m">' + esc(n.method) + '</span> ' + esc(n.url) +
          ' <span class="' + cls + '">' + esc(status) + '</span>' +
          (n.durationMs != null ? ' <span style="color:#8b90a0">' + n.durationMs + 'ms</span>' : '') +
          (n.error ? ' <span class="err">' + esc(n.error) + '</span>' : '') + '</div>';
      }).join('') + '</div>';
    }

    html += '</div>';
    return html;
  }).join('');
}

async function poll() {
  try {
    const res = await fetch('/reports.json');
    reports = await res.json();
    render();
  } catch (_) {}
}

async function clearReports() {
  await fetch('/clear', { method: 'POST' });
  reports = []; render();
}

render();
setInterval(poll, 3000);
</script>
</body>
</html>
''';
}
