# Changelog

## 0.2.0 — 2026-05-25

- **Network capture for the developer overlay.** New `ShakeDioInterceptor` (`package:shake_context/dio.dart`) and `ShakeHttpClient` (`package:shake_context/http.dart`) record every HTTP request/response/error as a `NetworkLog` that surfaces in the developer overlay's Network panel (filterable by failed-only) and in `ReportMetadata.networkLogs`. Both entry points are separate library imports so `dio` / `http` are tree-shaken when unused. Hosts on other clients can push entries directly via `ShakeContext.recordNetwork(NetworkLog(...))`.
- **`RedactionConfig` — privacy guardrails for captured network/log data.** Headers and bodies are masked and truncated *before* being stored: conservative defaults redact common auth/session header keys (`authorization`, `cookie`, `x-api-key`, …) and body keys (`password`, `token`, `secret`, …), truncate bodies to 2 KB and log messages to 8 KB. Override per-interceptor via the `redaction:` parameter. See README → "Capturing network traffic".
- **`ShakeSensitivity` — tunable shake trigger.** `ShakeContext(shakeSensitivity: …)` accepts `low()` / `medium()` (default) / `high()` presets or a fully custom `threshold` / `minSpikes` / `window` / `cooldown` profile. Changeable at runtime.
- **`ReportTheme` — per-surface color overrides.** Pass to `DeveloperConfig.theme` / `ProductionConfig.theme` to recolor the report sheet without supplying a full `ThemeData`; every field is nullable and falls back to the inherited `colorScheme`.
- **macOS gallery picker now works in the example app.** Adds `com.apple.security.files.user-selected.read-only` to both `DebugProfile.entitlements` and `Release.entitlements`. Without it the sandbox silently blocks `image_picker_macos`'s `NSOpenPanel` — the "Add image" button in the production sheet appeared to do nothing. README's "Platform setup" section now documents the requirement for downstream apps.
- **Platform support audit + README rewrite.** The "Platform support" table is now split into Tier 1 (first-party, verified) and Tier 2 (community plugins, untested) so users can tell what the maintainer has actually run end-to-end from what the dependencies merely advertise. Tier 1 (Android, iOS, macOS, Chrome, Safari) has been walked through the example app: shake / `triggerReport` / screenshot capture / device info / `package_info_plus` app version / gallery picker / submit / retry-queue no-op on web. Web verification covers both the Blink (Chrome, Brave, Edge) and WebKit (Safari) engines via `flutter run -d web-server`. Firefox (Gecko) hasn't been driven through the example — flagged in the "Web caveats" subsection. Windows and Linux are explicitly framed as "untested but expected to work."
- **Persistent retry queue for failed submissions.** Opt in via `ShakeContext.guard(enableRetryQueue: true, retryQueueMaxAge: …, retryQueueMaxEntries: …)`. When `onReportSubmitted` throws, the payload is serialised (including images) to `<applicationSupportDirectory>/shake_context/queue/` *before* the SnackBar fires, then replayed 5 s after the next app launch. Successful replays delete the file; failures stay queued for the launch after that, with FIFO eviction beyond `maxEntries` and age-based eviction beyond `maxAge` (default 20 entries / 7 days). New static API: `ShakeContext.queuedReportCount()`, `ShakeContext.replayQueuedReports()`, `ShakeContext.clearQueuedReports()` for "Pending reports" badges, manual retry, and logout hooks. Concurrent `replayQueuedReports()` calls collapse onto the same in-flight future — no double-sends.
- **`ReportPayload.fromJson` (+ `ReportMetadata.fromJson`, `LogEntry.fromJson`, `NetworkLog.fromJson`).** Round-trips cleanly with `toJson(includeImages: true)`. Defensive parsing — missing or wrong-typed fields fall back to safe defaults (unknown `mode` → `production`); individually broken nested entries are skipped rather than throwing the whole payload out.
- **`ProductionStrings` — localizable copy for the production sheet.** Every user-facing string in `ProductionView` (header, hint, button labels, privacy line, tooltips, "Sent with your report" disclosure, submission-failure SnackBar — ~25 strings in total) is now overridable via a single `ProductionStrings` value object passed through `ProductionConfig(strings: …)`. Wire your `AppLocalizations` (or any localization layer) into it per locale. The legacy top-level `title` / `hintText` / `submitLabel` / `privacyNote` parameters on `ProductionConfig` still work for source compatibility but are soft-deprecated. See README → "Localization" for a worked example.
- `InspectMode.resolve({String? flavor, Set<String> productionFlavors, bool? isReleaseBuild})` — ergonomic helper for picking the right mode at startup. Works without flavors (falls back to `kReleaseMode ? production : developer`) and with flavors (returns `production` only when the flavor is in `productionFlavors` **and** the build is release-signed). Fixes the common TestFlight pitfall where `kReleaseMode` alone would hide the diagnostic overlay from QA on internal builds.
- `DeveloperConfig.screenshotPixelRatio` and `ProductionConfig.screenshotPixelRatio` (both default `3.0`) — lets hosts dial down screenshot resolution when upload size matters. A 3.0x screenshot on a 1080p phone is 5–8 MB; 1.5–2.0 cuts that significantly.
- **App version auto-captured.** Adds `package_info_plus` dep. Every report's `metadata.deviceInfo` now includes `appName`, `appPackageName`, `appVersion`, and `appBuildNumber` — the version is the field every bug tracker asks for first, and you no longer need to plumb it in by hand.
- **`ReportPayload.extras` + `ShakeContext(extras: …)`** — host-provided context attached to every payload. Use it for `installationId`, `userId`, `releaseChannel`, feature-flag state, etc. Included in `toJson()` only when non-empty, participates in equality.
- **Submission failures now surface to the user.** When `onReportSubmitted` throws, the sheet stays open, the typed description and attachments are preserved, and a SnackBar tells the user the report couldn't be sent. Developer mode shows the raw error string for diagnosis; production mode shows a friendly generic message. Previously the spinner just cleared and the user got no signal.
- `ShakeListener` spike buffer switched from `List<DateTime>` to `ListQueue<DateTime>` so the per-sample eviction inside `_onSample` is O(1) instead of O(n). Imperceptible per sample, but the sensor runs at ~20 Hz × 3 axes — small savings add up.
- README:
  - "Picking the mode" + "Using with flavors" guide: full mode matrix, `main_dev.dart` / `main_prod.dart` bootstrap pattern, build commands, gotchas (TestFlight, bundle-ID inference, symbol obfuscation).
  - "Host context" section showing the `extras` pattern (installation ID, user ID, release channel).
  - "Sending the report" section: four concrete transport recipes (multipart, JSON webhook, email via share_plus, Sentry user feedback) + a documented retry-queue pattern for offline-friendly submission.
  - "Screenshot size" section with the `screenshotPixelRatio` knob and a `package:image` recompression recipe.
  - "Crash recovery" section explaining the `persistLogs: true` flow.
  - "Platform setup" section calling out the iOS `NSPhotoLibraryUsageDescription` requirement when `allowGalleryUpload` is on.
  - "Capturing network traffic" section documenting `ShakeDioInterceptor` / `ShakeHttpClient` / `ShakeContext.recordNetwork`, plus the `RedactionConfig` defaults and how to override them.
  - "Shake sensitivity" and "Theming the report sheet" sections for the new `ShakeSensitivity` and `ReportTheme` APIs.
  - "Sending the report" expanded with a copy-paste **dev-vs-production endpoint routing** snippet (`--dart-define` base URL, dispatch on `payload.mode`) and a **backend contract** describing both wire formats (multipart and JSON-with-inline-images), the JSON shape the server receives, and the minimum server requirements.
  - Primary `Usage` example now wraps `runApp` in `ShakeContext.guard(...)` to match the 99% case (full log + uncaught-error capture).
- Example app updated to use `InspectMode.resolve()` instead of the manual `kReleaseMode` conditional, and now **POSTs each report to a bundled local receiver** (`test_backend/`, a zero-dependency Dart server with a live web dashboard) so the full capture → serialize → transport → render path can be verified end-to-end. The example's macOS network-client entitlement and iOS local-network / cleartext-HTTP allowances were added for that upload path.

## 0.1.0 — First public release

- Telemetry & media pipeline (`ContextCapturer`):
  - Real screenshot capture via a `RepaintBoundary` wrapped around the app tree.
  - `device_info_plus`-backed device snapshot, curated per platform (Android / iOS / macOS / Windows / Linux / Web).
  - Best-effort current-route detection (non-destructive `popUntil` inspection).
  - Rolling `debugPrint` log buffer with eviction (`DeveloperConfig.logBufferSize`), installed in `ShakeContext.initState` and restored on `dispose`.
  - `image_picker`-backed gallery picker for the production sheet's `+` button.
- `ShakeContext` now wraps `child` in a `RepaintBoundary` and feeds captured data into the overlay views asynchronously — the modal opens instantly and rebuilds as each capture resolves.
- `DeveloperView` and `ProductionView` accept optional `screenshotFuture` / `deviceInfoFuture` / `initialScreenshotFuture` parameters and reconcile bytes via `setState`.
- Multi-page example app (home / settings / nested `/checkout` route) demonstrates the master toggle and route capture.
- MIT license, pub.dev-ready `README`, dartdoc on every public symbol.

## 0.0.4 — Dual-mode presentation factory

- `ProductionView` — Material bottom-sheet form with description field, removable image row, optional gallery picker callback, privacy reassurance line, and submit/loading states.
- `DeveloperView` — diagnostic dashboard with route, device info, log tail, screenshot preview, optional note, cancel/send actions. Honors all `DeveloperConfig` capture toggles.
- `UnifiedOverlay.show()` — picks the correct view based on `InspectMode`, mounts it via `showModalBottomSheet`, and pops itself after successful submission.
- `ShakeContext` now launches the overlay on shake. Added `navigatorKey` parameter so the widget can sit above `MaterialApp` and still resolve a `Navigator`.
- Tests cover each view in isolation, the overlay router, and a full shake → overlay-opens integration path for both modes plus the navigatorKey-above-MaterialApp placement.

## 0.0.3 — Shake detection engine

- Added `sensors_plus: ^6.0.0` dependency.
- `ShakeListener` (`lib/src/core/shake_listener.dart`) — g-force spike detector with rolling time window, debounce cool-down, and injectable clock + stream for tests.
- `ShakeContext` now starts/stops a `ShakeListener` based on `isShakeEnabled`, reacts to runtime flips in `didUpdateWidget`, and tears down cleanly in `dispose`.
- New optional `onShakeDetected` hook exposes the raw trigger before the UI lands in Plan 04.
- Test coverage extended to spike-count, sub-threshold rejection, window aging, cool-down, restart, and idempotent `start()`.

## 0.0.2 — Core models & public API surface

- `InspectMode` enum (`developer`, `production`).
- `ProductionConfig` and `DeveloperConfig` value classes with `copyWith` and value equality.
- `ReportPayload` + `ReportMetadata` unified output models with immutable collections.
- `ShakeContext` widget shell — constructor takes `mode`, `isShakeEnabled`, `productionConfig`, `developerConfig`, `onReportSubmitted`, `child`. Renders the child; sensor and presentation layers land in upcoming plans.
- Public barrel now exports the full Plan 02 surface.

## 0.0.1 — Scaffolding

- Initial project skeleton.
- `lib/src/` folder layout established for `models/`, `core/`, and `presentation/`.
- Public barrel `lib/shake_context.dart` ready for milestone exports.
- Execution plan broken down under `plans/`.
