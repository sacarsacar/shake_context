# shake_context

A dual-mode, privacy-first, shake-triggered bug reporting and user feedback engine for Flutter.

One widget. Two completely different surfaces depending on the build channel: a high-density diagnostic dashboard for engineers and QA, and a privacy-respecting feedback sheet for production consumers.

## Why two modes?

| Aspect           | Developer Mode (`InspectMode.developer`)        | Production Mode (`InspectMode.production`)         |
| :--------------- | :---------------------------------------------- | :------------------------------------------------- |
| **Shake trigger**| Auto-on in debug / profile builds               | Honors an explicit user toggle                     |
| **Screenshot**   | Captured automatically                          | Optional — user can remove it                      |
| **Telemetry**    | Route, device specs, console logs               | Only user-typed text and user-picked images        |
| **Audience**     | Engineers, QA, beta testers                     | Real consumers in production                       |

## Install

```yaml
dependencies:
  shake_context: ^0.2.0
```

## Demo
<table>
  <tr>
    <td align="center" width="50%">
      <b>Production Mode</b><br>
      <img src="https://raw.githubusercontent.com/sacarsacar/shake_context/demo/prod_shake.gif" width="250" alt="Production Demo">
    </td>
    <td align="center" width="50%">
      <b>Dev Mode</b><br>
      <img src="https://raw.githubusercontent.com/sacarsacar/shake_context/demo/dev_shake.gif" width="250" alt="Dev Mode">
    </td>
  </tr>
  <tr>
   
</table>


## Usage

```dart
import 'package:flutter/material.dart';
import 'package:shake_context/shake_context.dart';

void main() {
  // `ShakeContext.guard` hooks `print`, `debugPrint`, FlutterError.onError,
  // and PlatformDispatcher.onError so the overlay can show everything the
  // app emits — including third-party loggers and uncaught async errors.
  // Skip it and the overlay only sees `debugPrint` output.
  ShakeContext.guard(() {
    runApp(
      ShakeContext(
        mode: InspectMode.resolve(),
        onReportSubmitted: (ReportPayload payload) async {
          if (payload.mode == InspectMode.production) {
            await uploadToSupportDesk(payload.userDescription, payload.images);
          } else {
            await sendToDevOps(payload.metadata, payload.images);
          }
        },
        child: const MyApp(),
      ),
    );
  });
}
```

That's it — shake the device and the right overlay appears for the active mode. Both modes flow through the same `onReportSubmitted` callback; dispatch by `payload.mode`.

### Platform setup

* **iOS** — if `allowGalleryUpload` is on (the default), add `NSPhotoLibraryUsageDescription` to your `ios/Runner/Info.plist`. Without it, the gallery picker crashes the first time it's invoked:

  ```xml
  <key>NSPhotoLibraryUsageDescription</key>
  <string>Attach screenshots to your bug report.</string>
  ```

* **macOS** — if `allowGalleryUpload` is on, add the user-selected file read entitlement to **both** `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`. Without it, the sandbox silently blocks `NSOpenPanel` and the "Add image" button does nothing:

  ```xml
  <key>com.apple.security.files.user-selected.read-only</key>
  <true/>
  ```

* **Android / Windows / Linux / web** — no native config required. Shake detection is unavailable on macOS/Windows/Linux/web (no accelerometer); use `ShakeContext.triggerReport(context)` to open the overlay programmatically there.

## Picking the mode

`InspectMode.resolve()` codifies the rule **"release builds are for real consumers, every other build is internal."** It works whether or not your project uses flavors.

### Without flavors

```dart
mode: InspectMode.resolve(),
```

Equivalent to `kReleaseMode ? InspectMode.production : InspectMode.developer`. Debug and profile builds get the diagnostic overlay; release builds get the consumer feedback sheet.

### With flavors

If your project ships multiple flavors (`dev`, `prod`, `staging`, …), pass the active flavor identifier from your per-flavor entry point:

```dart
mode: InspectMode.resolve(flavor: 'dev'),   // from main_dev.dart
mode: InspectMode.resolve(flavor: 'prod'),  // from main_prod.dart
```

The helper returns `InspectMode.production` **only** when the build is a release build *and* the flavor is in `productionFlavors` (default `{'prod', 'production'}`). Every other combination — including a release build of the `dev` flavor (e.g. an internal TestFlight track) — returns `InspectMode.developer`. QA keeps the diagnostic overlay on signed builds without exposing it to real consumers.

### Mode matrix

| Flavor   | Build mode | Audience                | `resolve(flavor: …)` returns |
| :------- | :--------- | :---------------------- | :--------------------------- |
| `dev`    | debug      | local development       | `developer`                  |
| `dev`    | profile    | perf / staging          | `developer`                  |
| `dev`    | release    | TestFlight / internal   | `developer`                  |
| `prod`   | debug      | dev poking prod API     | `developer`                  |
| `prod`   | profile    | rare perf testing       | `developer`                  |
| `prod`   | release    | **App Store consumers** | `production`                 |

### Custom flavor names

For projects that don't call the consumer flavor `prod` / `production`:

```dart
mode: InspectMode.resolve(
  flavor: appFlavor,
  productionFlavors: {'live', 'appstore'},
),
```

## Using with flavors

The Flutter-idiomatic pattern is one entry point per flavor, both delegating to a shared bootstrap.

```dart
// lib/main_dev.dart
import 'app/bootstrap.dart';
void main() => bootstrap('dev');

// lib/main_prod.dart
import 'app/bootstrap.dart';
void main() => bootstrap('prod');
```

```dart
// lib/app/bootstrap.dart
import 'package:flutter/material.dart';
import 'package:shake_context/shake_context.dart';

void bootstrap(String flavor) {
  // Hooks print/debugPrint/FlutterError/PlatformDispatcher so the overlay
  // can show everything the app emits — flavor-agnostic.
  ShakeContext.guard(() {
    runApp(
      ShakeContext(
        mode: InspectMode.resolve(flavor: flavor),
        onReportSubmitted: (payload) => _send(flavor, payload),
        child: MyApp(flavor: flavor),
      ),
    );
  });
}

Future<void> _send(String flavor, ReportPayload payload) async {
  if (payload.mode == InspectMode.developer) {
    // QA / internal — diagnostic dump goes to engineering
    await sendToEngineeringChannel(payload);
  } else {
    // Real consumer feedback goes to the support desk
    await sendToSupportDesk(payload);
  }
}
```

### Build & run commands

```bash
# Local development against staging API
flutter run --flavor dev -t lib/main_dev.dart

# Internal TestFlight build — release-signed, but developer overlay
flutter build ipa --flavor dev -t lib/main_dev.dart --release

# App Store production build — release-signed, consumer sheet
flutter build ipa --flavor prod -t lib/main_prod.dart --release
```

### Platform flavor wiring

shake_context doesn't touch native build config — set up flavors however you normally would. Quick pointers:

* **Android** — `android/app/build.gradle` `productFlavors { dev { … }; prod { … } }`.
* **iOS** — Xcode schemes + build configurations (`Debug-dev` / `Release-dev` / `Debug-prod` / `Release-prod`), one scheme per flavor.

Follow the [Flutter flavors guide](https://docs.flutter.dev/deployment/flavors) for the full setup.

### Gotchas

* **TestFlight = release build.** Don't gate the mode on `kReleaseMode` alone — your TestFlight QA will see the consumer sheet instead of the diagnostic overlay. `InspectMode.resolve(flavor: …)` handles this for you.
* **Bundle ID alone is not enough.** A release build of either flavor has `kReleaseMode == true`. The package needs the explicit flavor string passed through from your entry point — it can't infer the flavor from the bundle ID at runtime.
* **Symbol obfuscation.** Release builds are obfuscated and tree-shaken by default. If you want readable stack traces in QA reports, build the dev flavor with `--no-obfuscate`, or pass `--split-debug-info=<dir>` per flavor and de-obfuscate server-side when you receive the report.
* **Different sinks per flavor.** It's usually a feature, not a bug, to send dev-flavor reports to your engineering Slack and prod-flavor reports to your support desk. Branch inside `onReportSubmitted` using either the captured `flavor` (closed over from `bootstrap`) or `payload.mode`.

### Placement: above vs. inside MaterialApp

The overlay needs a `Navigator`. Two options:

1. **Inside `MaterialApp`** — drop `ShakeContext` into `home:` (or wrap your screen tree inside `home`). The widget discovers the inherited `Navigator` automatically.
2. **Above `MaterialApp`** — share a `GlobalKey<NavigatorState>` with `MaterialApp.navigatorKey` and pass it to `ShakeContext(navigatorKey: ...)`. Useful when you want the engine to survive `MaterialApp` rebuilds.

### Host context (installation ID, user ID, …)

`ShakeContext` plumbs an `extras` map straight into every emitted `ReportPayload.extras`. Use it for identifiers and stage info the package can't know on its own:

```dart
ShakeContext(
  extras: {
    'installationId': await loadOrGenerateInstallationId(),  // dedupe
    'userId': currentUser?.id,                                // optional
    'releaseChannel': 'beta',                                 // build stage
    'experiments': activeFeatureFlags.toList(),               // anything JSON
  },
  // ...
)
```

Values must be JSON-encodable for `payload.toJson()` to round-trip cleanly. App version, build number, package name are **already captured automatically** under `metadata.deviceInfo` (`appVersion`, `appBuildNumber`, `appName`, `appPackageName`) via `package_info_plus` — you don't need to add them to `extras` yourself.

### Runtime master toggle

```dart
ShakeContext(
  // ...
  isShakeEnabled: userSettings.shakeReportingOn,
)
```

Flip `isShakeEnabled` at any time. The engine starts / stops sampling the accelerometer without rebuilding the rest of the app.

### Shake sensitivity

How hard the user has to shake before the sheet opens is tunable via `shakeSensitivity`. Three presets cover the common cases:

```dart
ShakeContext(
  shakeSensitivity: const ShakeSensitivity.medium(), // default
  // ...
)
```

| Preset                      | Feel                                  | When to use                                              |
| :-------------------------- | :------------------------------------ | :------------------------------------------------------- |
| `ShakeSensitivity.low()`    | Harder — needs a deliberate, vigorous shake | False positives are costly (the sheet would interrupt a critical flow) |
| `ShakeSensitivity.medium()` | Balanced — what most "shake to feedback" apps feel like | Default                                          |
| `ShakeSensitivity.high()`   | Easier — fires on lighter motion      | Accessibility, or QA builds where the trigger should be easy |

For exact tuning (tablets, kiosks, app-specific accessibility), use the unnamed constructor:

```dart
ShakeContext(
  shakeSensitivity: const ShakeSensitivity(
    threshold: 2.5,                              // min g-force for one sample to count as a spike (lower = easier)
    minSpikes: 3,                                // spikes needed inside `window` to fire
    window: Duration(milliseconds: 500),         // rolling window spikes are counted in
    cooldown: Duration(seconds: 1),              // quiet period after a trigger before the next can fire
  ),
  // ...
)
```

`shakeSensitivity` can be changed at runtime — the example app exposes a low/medium/high segmented button on its settings page.

### Configuration knobs

```dart
ShakeContext(
  productionConfig: const ProductionConfig(
    strings: ProductionStrings(
      title: 'Send us feedback',
      hintText: 'What happened? Walk us through it.',
      submitLabel: 'Send',
    ),
    allowGalleryUpload: true,
    allowScreenshotAttachment: true,
  ),
  developerConfig: const DeveloperConfig(
    captureRoute: true,
    captureDeviceInfo: true,
    captureConsoleLogs: true,
    captureScreenshot: true,
    logBufferSize: 200,
  ),
  // ...
)
```

### Theming the report sheet

Both surfaces inherit your app's `Theme` by default — the sheet recolors itself from the ambient `colorScheme` with no extra work. When you need to override specific colors without supplying a whole `ThemeData`, pass a `ReportTheme` to `DeveloperConfig.theme` and/or `ProductionConfig.theme`:

```dart
ShakeContext(
  productionConfig: const ProductionConfig(
    theme: ReportTheme(
      primaryColor: Color(0xFF6750A4),        // header chip, section icons, focused field border
      submitButtonColor: Color(0xFF6750A4),   // Send button background
      submitButtonTextColor: Colors.white,    // Send button label
      // backgroundColor, cardColor, borderColor, textColor, subtitleColor,
      // onPrimaryColor, cancelButtonColor are all available too.
    ),
  ),
  // ...
)
```

Every `ReportTheme` field is nullable — anything left `null` falls back to the matching token on the inherited `Theme`'s `colorScheme`, so you can recolor just the one or two things you care about.

### Capturing network traffic

In **developer mode** the overlay can show a Network panel listing every HTTP request/response/error the app made — method, URL, status, duration, and (redacted) headers + bodies. Wire it up at your HTTP client's configuration site; nothing is captured until you do.

**Dio** — add the interceptor (import the `dio.dart` entry point so dio is tree-shaken when you don't use it):

```dart
import 'package:shake_context/dio.dart';

final dio = Dio()..interceptors.add(ShakeDioInterceptor());
```

**`http` package** — wrap your client (import the `http.dart` entry point):

```dart
import 'package:http/http.dart' as http;
import 'package:shake_context/http.dart';

final client = ShakeHttpClient(http.Client());
await client.get(Uri.parse('https://api.example.com/items'));
```

**Any other client** — hand-build a `NetworkLog` and push it yourself:

```dart
ShakeContext.recordNetwork(NetworkLog(
  method: 'GET',
  url: 'https://api.example.com/items',
  statusCode: 200,
  durationMs: 142,
));
```

Captured entries feed the developer overlay's Network panel (filterable by failed-only) and, with `persistLogs: true`, the "Previous session — network" panel after a crash. They are part of `ReportMetadata` and serialize through `toJson()`.

> Network capture is a **developer-mode diagnostic**. Don't add the interceptor in production-mode builds unless you intend to ship request/response bodies in your reports.

#### Redaction & size guardrails

Captured headers and bodies are run through a `RedactionConfig` **before** they're stored, so secrets never reach the buffer. The defaults are conservative:

| Knob                 | Default                                                                                          |
| :------------------- | :----------------------------------------------------------------------------------------------- |
| `redactedHeaderKeys` | `authorization`, `cookie`, `set-cookie`, `proxy-authorization`, `x-api-key`, `x-auth-token`      |
| `redactedBodyKeys`   | `password`, `pass`, `pwd`, `token`, `access_token`, `refresh_token`, `api_key`, `apikey`, `secret`, `authorization` |
| `maxBodyChars`       | `2048` (request/response bodies truncated past this)                                             |
| `maxLogChars`        | `8192` (any single log message truncated past this)                                              |
| `maskText`           | `«redacted»`                                                                                     |

Header matching is case-insensitive and exact; body matching is a heuristic regex over the serialized body (catches common JSON shapes — not a full parser). To widen or tighten the policy, pass a custom `RedactionConfig` to the interceptor or client:

```dart
ShakeDioInterceptor(
  redaction: const RedactionConfig(
    redactedBodyKeys: {'password', 'ssn', 'creditCard'},
    maxBodyChars: 4096,
  ),
  captureRequestBody: true,   // set false to omit request bodies entirely
  captureResponseBody: true,
  captureHeaders: true,
);
```

`ShakeHttpClient` takes the same `redaction` / `capture*` parameters.

### Localization

Every visible string in the production sheet — header, hint, button labels, privacy line, tooltips, the "Sent with your report" disclosure, the SnackBar shown on submission failure — is overridable via `ProductionStrings`. The defaults are English; pipe your app's per-locale copy through whatever localization layer you already use.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shake_context/shake_context.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        // `context` here sees the AppLocalizations inherited from MaterialApp.
        final l10n = AppLocalizations.of(context)!;
        return ShakeContext(
          mode: InspectMode.resolve(),
          productionConfig: ProductionConfig(
            strings: ProductionStrings(
              title: l10n.bugReportTitle,
              hintText: l10n.bugReportHint,
              submitLabel: l10n.bugReportSubmit,
              cancelLabel: l10n.bugReportCancel,
              privacyNote: l10n.bugReportPrivacyNote,
              headerSubtitle: l10n.bugReportSubtitle,
              descriptionPrompt: l10n.bugReportDescriptionPrompt,
              attachmentsLabel: l10n.bugReportAttachments,
              addImage: l10n.bugReportAddImage,
              limitReached: l10n.bugReportLimitReached,
              noAttachments: l10n.bugReportNoAttachments,
              addAttachmentHint: l10n.bugReportAddAttachmentHint,
              sentWithReport: l10n.bugReportSentWith,
              timeLabel: l10n.bugReportTime,
              deviceLabel: l10n.bugReportDevice,
              resolvingDeviceInfo: l10n.bugReportResolvingDevice,
              showDetails: l10n.bugReportShowDetails,
              hideDetails: l10n.bugReportHideDetails,
              dismissTooltip: l10n.bugReportDismiss,
              removeImageTooltip: l10n.bugReportRemoveImage,
              annotateTooltip: l10n.bugReportAnnotate,
              tapToView: l10n.bugReportTapToView,
              autoBadge: l10n.bugReportAutoBadge,
              submissionFailedMessage: l10n.bugReportSubmissionFailed,
            ),
          ),
          onReportSubmitted: sendReport,
          child: child ?? const SizedBox.shrink(),
        );
      },
      // ...
    );
  }
}
```

Override only the fields that matter for your locale — anything left out falls back to the English default. The legacy top-level `title` / `hintText` / `submitLabel` / `privacyNote` parameters on `ProductionConfig` still work for source compatibility, but they're soft-deprecated in favor of `strings`.

`DeveloperView` copy is currently English-only. The developer overlay is an engineer-facing surface and rarely ships to end users; if you have a use case for localizing it, open an issue.

## Privacy

Developer mode auto-captures a screenshot, current route, device snapshot, and the rolling `debugPrint` log buffer the moment a shake fires. It is intended for **internal builds** (debug, profile, beta channels) and should not ship to end users.

Production mode never captures telemetry on its own — `ReportPayload.metadata` is empty unless you explicitly populate it. Only the user-typed text and user-approved image attachments are returned.

## What's in the payload?

```dart
class ReportPayload {
  final InspectMode mode;              // developer or production
  final String userDescription;        // user-typed text
  final List<Uint8List> images;        // screenshot + any user-picked images
  final ReportMetadata metadata;       // route, deviceInfo, logs, networkLogs, timestamp
  final Map<String, Object?> extras;   // host-provided context (see above)
}
```

`metadata.deviceInfo` includes platform / model / OS *and* `appVersion`, `appBuildNumber`, `appName`, `appPackageName` — the version is the field every bug tracker asks for first.

`metadata` is populated in developer mode and empty in production mode. The package never writes anything to disk¹ and never uploads anywhere — `onReportSubmitted` hands you the bytes; transport is your call.

¹ Except the opt-in [crash-recovery log buffer](#crash-recovery), which is JSON only — no images.

### JSON serialization

Both `ReportPayload` and `ReportMetadata` expose `toJson()`. Images are excluded by default (a `imageCount` field is emitted instead) so you can ship them out-of-band as multipart — smaller wire, what most backends expect:

```dart
final body = jsonEncode(payload.toJson());
// payload.images is a List<Uint8List> you upload separately
```

Pass `includeImages: true` when you need a single self-contained JSON blob (e.g. a webhook that can't accept multipart). Each image is base64-encoded inline:

```dart
final body = jsonEncode(payload.toJson(includeImages: true));
```

Heads-up: base64 inflates by ~33%, and the encoding runs on the main isolate — for multi-MB screenshots, prefer the multipart path.

## Sending the report

shake_context is transport-agnostic by design — it never uploads anything
itself. `onReportSubmitted` hands you a [`ReportPayload`](#whats-in-the-payload)
and you POST it wherever you like. The recipes below are copy-paste ready.

### Routing to different endpoints (dev vs. production)

Both modes flow through the same callback; branch on `payload.mode` to send
diagnostic reports to engineering and consumer feedback to your support desk.
The base URL itself can switch per build with a `--dart-define` so debug builds
hit your staging server and release builds hit production:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shake_context/shake_context.dart';

// Pass at build time:
//   flutter run   --dart-define=API_BASE=https://staging.example.com
//   flutter build --dart-define=API_BASE=https://api.example.com
const _apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://api.example.com',
);

// Different sinks per mode (see InspectMode.resolve()):
//   developer → QA/engineering diagnostics      production → support desk
const _devEndpoint = '$_apiBase/diagnostics';
const _prodEndpoint = '$_apiBase/feedback';

Future<void> sendReport(ReportPayload payload) async {
  final endpoint = payload.mode == InspectMode.developer
      ? _devEndpoint
      : _prodEndpoint;

  final req = http.MultipartRequest('POST', Uri.parse(endpoint))
    ..fields['payload'] = jsonEncode(payload.toJson())
    ..files.addAll([
      for (var i = 0; i < payload.images.length; i++)
        http.MultipartFile.fromBytes(
          'image_$i',
          payload.images[i],
          filename: 'attachment_$i.png',
        ),
    ]);

  final resp = await req.send();
  // Throwing here keeps the sheet open and shows the user a SnackBar — and, if
  // you enabled it, hands the payload to the retry queue. See "Handling
  // submission failures".
  if (resp.statusCode >= 400) {
    throw Exception('Upload failed: HTTP ${resp.statusCode}');
  }
}

// Wire it in:
//   ShakeContext(onReportSubmitted: sendReport, ...)
```

### Backend contract — what your server must accept

Your endpoint just needs to accept a `POST` and read the payload. Pick one of
two wire formats:

**A. Multipart (recommended for real backends)** — a `payload` form field
holding `jsonEncode(payload.toJson())`, plus one file part per image
(`image_0`, `image_1`, …, PNG bytes). Smaller on the wire; images stream as
files. This is the request the snippet above sends.

**B. JSON-only (simplest — one `jsonDecode` on the server)** — `Content-Type:
application/json`, body = `jsonEncode(payload.toJson(includeImages: true))`.
Images are base64-encoded inline (~33% larger). Good for webhooks or a quick
test server:

```dart
await http.post(
  Uri.parse(endpoint),
  headers: const {'Content-Type': 'application/json'},
  body: jsonEncode(payload.toJson(includeImages: true)),
);
```

Either way the JSON your server receives looks like this (fields are omitted
when empty — code defensively):

```jsonc
{
  "mode": "developer",              // or "production" — route on this
  "userDescription": "Login button does nothing on the checkout page",
  "imageCount": 1,
  "images": ["<base64 PNG>"],       // only with toJson(includeImages: true)
  "extras": {                        // only if you passed ShakeContext(extras:)
    "userId": "u_123",
    "releaseChannel": "beta"
  },
  "metadata": {                      // rich in developer mode, near-empty in production
    "timestamp": "2026-06-02T20:04:42.570Z",
    "currentRoute": "/checkout",
    "deviceInfo": {
      "platform": "ios",
      "model": "iPhone15,2",
      "osVersion": "18.5",
      "appName": "MyApp",
      "appPackageName": "com.example.myapp",
      "appVersion": "1.4.0",
      "appBuildNumber": "142"
    },
    "logs": [
      { "message": "tapped checkout", "level": "info", "source": "ui", "timestamp": "2026-06-02T20:04:40.110Z" }
    ],
    "networkLogs": [
      { "method": "POST", "url": "https://api.example.com/checkout", "statusCode": 500, "durationMs": 812, "timestamp": "2026-06-02T20:04:41.900Z" }
    ]
  }
}
```

Minimum server requirements: accept `POST`, return **2xx on success** (any
`>= 400` makes the app keep the sheet open / queue for retry), and a body limit
large enough for base64 screenshots if you use format **B** (a 3.0x screenshot
can be several MB — see [Screenshot size](#screenshot-size)). No auth scheme is
imposed; add your own header in the request if your endpoint needs one.

> **Want to try it locally first?** The repo ships a zero-dependency receiver
> with a live dashboard under [`test_backend/`](./test_backend) — `dart run
> test_backend/server.dart`, then submit a report from the example app. See
> [test_backend/README.md](./test_backend/README.md), including the
> physical-device gotchas (LAN IP, iOS cleartext/local-network permissions).

### 1. Multipart POST to your own endpoint (recommended)

```dart
import 'package:http/http.dart' as http;

Future<void> sendReport(ReportPayload payload) async {
  final req = http.MultipartRequest(
    'POST',
    Uri.parse('https://api.example.com/bug-reports'),
  )
    ..fields['payload'] = jsonEncode(payload.toJson())
    ..files.addAll([
      for (var i = 0; i < payload.images.length; i++)
        http.MultipartFile.fromBytes(
          'image_$i',
          payload.images[i],
          filename: 'attachment_$i.png',
          contentType: MediaType('image', 'png'),
        ),
    ]);
  final resp = await req.send();
  if (resp.statusCode >= 400) {
    throw Exception('Upload failed: ${resp.statusCode}');
  }
}
```

### 2. JSON-only webhook (Slack, Discord, generic)

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;

Future<void> sendToSlack(ReportPayload payload) async {
  // Slack webhooks don't accept file uploads — upload images to S3/GCS
  // first and embed the URLs, or skip images entirely.
  await http.post(
    Uri.parse('https://hooks.slack.com/services/...'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'text': '🐛 ${payload.userDescription.isEmpty ? "(no note)" : payload.userDescription}',
      'attachments': [
        {
          'fields': [
            {'title': 'Route', 'value': payload.metadata.currentRoute ?? '(unknown)'},
            {'title': 'Device', 'value': payload.metadata.deviceInfo.toString()},
            {'title': 'Images', 'value': '${payload.images.length}'},
          ],
        },
      ],
    }),
  );
}
```

### 3. Email via share_plus (no backend required)

```dart
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

Future<void> emailReport(ReportPayload payload) async {
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (var i = 0; i < payload.images.length; i++) {
    final path = '${dir.path}/report_$i.png';
    await File(path).writeAsBytes(payload.images[i]);
    files.add(XFile(path));
  }
  await Share.shareXFiles(
    files,
    subject: 'Bug report',
    text: '${payload.userDescription}\n\n'
        '${const JsonEncoder.withIndent("  ").convert(payload.metadata.toJson())}',
  );
}
```

### 4. Sentry user feedback

```dart
import 'package:sentry_flutter/sentry_flutter.dart';

Future<void> sendToSentry(ReportPayload payload) async {
  final id = await Sentry.captureMessage(
    'User bug report',
    withScope: (scope) {
      for (var i = 0; i < payload.images.length; i++) {
        scope.addAttachment(
          SentryAttachment.fromUint8List(
            payload.images[i],
            'attachment_$i.png',
            contentType: 'image/png',
          ),
        );
      }
    },
  );
  await Sentry.captureUserFeedback(SentryUserFeedback(
    eventId: id,
    comments: payload.userDescription,
  ));
}
```

### Handling submission failures

shake_context calls `onReportSubmitted` and awaits it. If it throws, the sheet stays open and the user sees the SnackBar — but unless the queue is enabled, the payload is lost the moment they dismiss the sheet.

#### Built-in retry queue (recommended)

Opt in by passing `enableRetryQueue: true` to `ShakeContext.guard`:

```dart
void main() {
  ShakeContext.guard(
    () => runApp(const MyApp()),
    enableRetryQueue: true,
    // Defaults shown — tune for your tolerance.
    retryQueueMaxAge: const Duration(days: 7),
    retryQueueMaxEntries: 20,
  );
}
```

When `onReportSubmitted` throws, the payload (description, attachments, metadata, extras — everything `toJson(includeImages: true)` serialises) is written to `<applicationSupportDirectory>/shake_context/queue/<id>.json` *before* the failure propagates back to the view. Five seconds after the next app launch the queue is drained: each entry is re-handed to your `onReportSubmitted`. Successful deliveries delete the file; failures stay queued for the launch after that.

Caps prevent runaway growth: `retryQueueMaxEntries` is a FIFO ceiling (oldest evicted on overflow); `retryQueueMaxAge` drops anything older than the cap on each replay pass without re-trying it. The default 20 entries × ~6 MB high-DPI screenshots is ~120 MB worst case — turn `screenshotPixelRatio` down or `maxEntries` down if your users have small storage budgets.

Three static methods drive a "Pending reports" UI from a settings screen:

```dart
final pending = await ShakeContext.queuedReportCount();
final delivered = await ShakeContext.replayQueuedReports();  // "Retry now"
await ShakeContext.clearQueuedReports();                     // logout hook
```

`replayQueuedReports()` is reentrant — calling it while the auto-replay is already in flight collapses onto the same future, so no payload is ever double-sent.

#### Privacy footprint

Queued reports sit on disk under `applicationSupportDirectory` until they replay successfully or eviction drops them. They include the user's typed text and any attached images. The directory follows the app's install lifecycle (gone on uninstall). For an explicit "discard everything" hook (e.g. after logout), call `clearQueuedReports()`.

#### Manual queueing (if you'd rather own it)

```dart
Future<void> sendReport(ReportPayload payload) async {
  try {
    await _upload(payload);
  } catch (_) {
    final queue = await _openQueueFile();
    await queue.writeAsString(jsonEncode(payload.toJson(includeImages: true)) + '\n', mode: FileMode.append);
  }
}
```

## Screenshot size

The auto-captured screenshot is rasterised at `screenshotPixelRatio: 3.0` by default — visually crisp on every modern display, but on a 1080p phone a single PNG can land in the 5–8 MB range. For a 4-attachment report on a high-DPI tablet, that adds up fast.

Two knobs to manage size:

```dart
ShakeContext(
  developerConfig: const DeveloperConfig(screenshotPixelRatio: 2.0),
  productionConfig: const ProductionConfig(
    screenshotPixelRatio: 1.5,  // production users have less bandwidth
    maxImages: 2,                // and tighter expectations on report size
  ),
  // ...
)
```

For multi-MB screenshots you intend to upload, also consider recompressing before transport with [`package:image`](https://pub.dev/packages/image):

```dart
import 'package:image/image.dart' as img;

Uint8List compress(Uint8List png, {int quality = 80}) {
  final decoded = img.decodePng(png)!;
  return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
}
```

## Crash recovery

Opt in via `ShakeContext.guard(persistLogs: true)`. The previous session's log + network buffers are persisted to `<applicationSupportDirectory>/shake_context/session.json` and surfaced in the **next** session's developer overlay under "Previous session — logs" / "Previous session — network". Useful for catching crashes that happened *before* the user could shake.

```dart
void main() {
  ShakeContext.guard(
    () => runApp(const MyApp()),
    persistLogs: true,
  );
}
```

Persistence is best-effort: a failed write never crashes the host app. Web is not supported (no application-support directory).

## Platform support

### Tier 1 — first-party, verified

| Capability       | Android | iOS | macOS | Web |
| :--------------- | :-----: | :-: | :---: | :-: |
| Shake detection  | ✅      | ✅  | —     | —   |
| `triggerReport`  | ✅      | ✅  | ✅    | ✅  |
| Screenshot       | ✅      | ✅  | ✅    | ✅  |
| Device info      | ✅      | ✅  | ✅    | ✅  |
| App version      | ✅      | ✅  | ✅    | ✅  |
| Network capture  | ✅      | ✅  | ✅    | ✅  |
| Gallery picker   | ✅      | ✅  | ✅†   | ✅  |
| Crash recovery   | ✅      | ✅  | ✅    | —   |
| Retry queue      | ✅      | ✅  | ✅    | —   |

Shake detection depends on `sensors_plus`, which only ships an accelerometer on Android and iOS. On every other platform (macOS, Windows, Linux, web), wire a button to `ShakeContext.triggerReport(context)` instead.

Crash recovery (`persistLogs: true`) and the retry queue (`enableRetryQueue: true`) both use `getApplicationSupportDirectory()` from `path_provider`, which has no web implementation — both opt-ins silently no-op on web rather than throwing.

Web verification was done on Chrome and Safari (covering both the Blink and WebKit engines, plus Chromium derivatives like Brave / Edge); Firefox (Gecko) hasn't been driven through the example end-to-end. † requires a macOS sandbox entitlement — see [Platform setup](#platform-setup).

### Tier 2 — community plugins, untested

Windows and Linux *should* work — every dependency (`sensors_plus`, `device_info_plus`, `image_picker`, `path_provider`, `package_info_plus`) ships a platform implementation — but the maintainer hasn't verified them end-to-end. Please file an issue with platform context if you hit anything.

### Web caveats

- **Gallery picker requires a real user gesture.** `image_picker` on web is backed by `<input type="file">`; some browsers only honor `.click()` calls when the dispatching JS frame is part of the same task as a user gesture. The package wires the picker through a Material `TextButton`, which keeps the call on the gesture's microtask, so the default "Add image" path works in Chrome. If you trigger the report from a non-tap path (e.g. a programmatic timer), the file dialog may be blocked.
- **Screenshot pixel ratio.** `RepaintBoundary.toImage` works in Chrome (Blink) and Safari (WebKit) at the default `screenshotPixelRatio: 3.0`. Firefox (Gecko) hasn't been driven through the example — if you need cross-browser-predictable output, override [`screenshotPixelRatio`](#screenshot-size) explicitly.

## Example

A multi-page demo lives in [example/](./example) — home page, settings page with a runtime toggle, and a second route to exercise route-name capture. Run it with `flutter run` from inside `example/`.

## Contributing

The package is built in small, focused plans under [plans/](./plans/) (Plans 01–06 shipped in 0.1.0, Plans 07–09 in 0.2.0). Each plan ends with a green `flutter analyze` and `flutter test`, so contributions can land plan-by-plan without breaking the tree.

## License

[MIT](./LICENSE).
