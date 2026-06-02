import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'core/context_capturer.dart';
import 'core/log_capture.dart';
import 'core/persistence_store.dart';
import 'core/retry_queue.dart';
import 'core/retry_queue_store.dart';
import 'core/shake_listener.dart';
import 'models/config_options.dart';
import 'models/inspect_mode.dart';
import 'models/log_entry.dart';
import 'models/network_log.dart';
import 'models/report_payload.dart';
import 'models/shake_sensitivity.dart';
import 'presentation/unified_overlay.dart';

/// Root widget for the shake_context engine.
///
/// Place this near the top of your widget tree — typically wrapping
/// `MaterialApp` — and pass it an [onReportSubmitted] callback. The widget
/// listens for shake gestures, shows the matching UI for the active [mode],
/// and emits a [ReportPayload] back to you.
///
/// Because the overlay must run on a `Navigator`, ensure one of the
/// following placements:
///
/// * Place `ShakeContext` inside `MaterialApp` (typically as `home:` or
///   wrapping the screen tree inside `home`), so a `Navigator` exists above
///   it; or
/// * Place `ShakeContext` *above* `MaterialApp` and pass [navigatorKey],
///   using the same key on `MaterialApp.navigatorKey`.
class ShakeContext extends StatefulWidget {
  const ShakeContext({
    super.key,
    required this.mode,
    required this.onReportSubmitted,
    required this.child,
    this.isShakeEnabled = true,
    this.shakeSensitivity = const ShakeSensitivity.medium(),
    this.productionConfig = const ProductionConfig(),
    this.developerConfig = const DeveloperConfig(),
    this.navigatorKey,
    this.onShakeDetected,
    this.extras = const <String, Object?>{},
    @visibleForTesting this.capturerOverride,
  });

  /// Wraps your app entry point in a `Zone` whose `print` redirects into
  /// the package's rolling log buffer, and installs the global error
  /// handlers (`FlutterError.onError`, `PlatformDispatcher.instance.onError`).
  ///
  /// Without this, only `debugPrint` output and host-app calls to
  /// [ShakeContext.log] are captured — `print(...)`, third-party loggers
  /// that route to `print`, and uncaught async errors are missed.
  ///
  /// Usage in `main`:
  ///
  /// ```dart
  /// void main() => ShakeContext.guard(() => runApp(const MyApp()));
  /// ```
  ///
  /// `dart:developer`'s `log(...)` cannot be intercepted from Dart code —
  /// use [ShakeContext.log] in its place to keep those entries in the
  /// report.
  static void guard(
    void Function() body, {
    bool captureUncaughtErrors = true,
    bool persistLogs = false,
    PersistenceStore? persistenceStoreOverride,
    bool enableRetryQueue = false,
    Duration retryQueueMaxAge = const Duration(days: 7),
    int retryQueueMaxEntries = 20,
    @visibleForTesting RetryQueueStore? retryQueueStoreOverride,
  }) {
    LogCapture.instance.hookDebugPrint();

    if (captureUncaughtErrors) {
      _installGlobalErrorHandlers();
    }

    runWithLogCapture(() {
      // Initialize bindings inside the same zone as `runApp` so Flutter
      // doesn't flag a zone mismatch on boot.
      WidgetsFlutterBinding.ensureInitialized();

      if (persistLogs) {
        // Fire-and-forget — opening the store is best-effort and must not
        // delay app startup. Any failure leaves `recoveredSession` null and
        // disables further persistence for this run.
        () async {
          final store =
              persistenceStoreOverride ?? await FilePersistenceStore.open();
          await LogCapture.instance.enablePersistence(store);
        }();
      }

      if (enableRetryQueue) {
        // Same fire-and-forget shape as the persistence store. We install
        // the queue handle as soon as the directory resolves; the widget
        // registers its callback on mount and the 5s post-boot timer
        // fires the first replay pass.
        () async {
          final store =
              retryQueueStoreOverride ?? await RetryQueueStore.open();
          if (store == null) return;
          RetryQueue.debugSetInstance(RetryQueue(
            store: store,
            maxAge: retryQueueMaxAge,
            maxEntries: retryQueueMaxEntries,
          ));
          // 5-second delay avoids competing with app boot for network/CPU.
          // Scheduling here (rather than in the widget's initState) keeps
          // widget tests that install a queue directly free of a pending
          // post-boot timer — pumpAndSettle would otherwise need to tick
          // through it.
          Future.delayed(const Duration(seconds: 5), () {
            RetryQueue.instance?.replayWithRegisteredCallback();
          });
        }();
      }

      body();
    }, captureUncaught: captureUncaughtErrors);
  }

  static bool _errorHandlersInstalled = false;

  /// Install `FlutterError.onError` and `PlatformDispatcher.onError`
  /// exactly once. Subsequent calls (hot reload, test reruns, accidental
  /// double-`guard`) are no-ops — without this guard the chained closures
  /// would stack and each error would be recorded N times.
  static void _installGlobalErrorHandlers() {
    if (_errorHandlersInstalled) return;
    _errorHandlersInstalled = true;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      LogCapture.instance.recordFlutterError(details);
      (previousFlutterError ?? FlutterError.presentError)(details);
    };

    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      LogCapture.instance.recordUncaughtError(
        error,
        stack,
        source: 'PlatformDispatcher',
      );
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }

  /// Test-only seam to reset the install latch so a subsequent `guard`
  /// call re-runs installation.
  @visibleForTesting
  static void debugResetGlobalErrorHandlers() {
    _errorHandlersInstalled = false;
  }

  /// Append a structured entry to the rolling log buffer. Use this as the
  /// replacement for `developer.log(...)`, which `ShakeContext.guard`
  /// cannot intercept.
  static void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? source,
    StackTrace? stackTrace,
  }) =>
      LogCapture.instance.log(
        message,
        level: level,
        source: source,
        stackTrace: stackTrace,
      );

  /// Append a [NetworkLog] to the rolling network buffer. Called by
  /// `ShakeDioInterceptor` and any host-provided HTTP adapter.
  static void recordNetwork(NetworkLog entry) =>
      LogCapture.instance.recordNetwork(entry);

  /// Number of queued reports awaiting replay. Use this to drive a
  /// "Pending reports: N" badge in a settings screen. Returns `0` when
  /// the retry queue is disabled or not yet initialised.
  ///
  /// Requires `ShakeContext.guard(enableRetryQueue: true)` at app start.
  static Future<int> queuedReportCount() async {
    final q = RetryQueue.instance;
    if (q == null) return 0;
    return q.count();
  }

  /// Manually trigger a replay pass. Use for a "Retry now" button.
  /// Returns the number of successfully delivered reports — `0` when the
  /// queue is disabled, no callback has been registered yet, or every
  /// pending payload failed again.
  ///
  /// Concurrent calls (e.g. tapping the button while the post-boot auto
  /// replay is in flight) collapse onto the same in-flight future, so no
  /// payload is double-sent.
  static Future<int> replayQueuedReports() async {
    final q = RetryQueue.instance;
    if (q == null) return 0;
    return q.replayWithRegisteredCallback();
  }

  /// Emergency drain — delete every queued report without trying to send.
  /// Useful as a logout hook (the queue can contain identifying user
  /// content) or in settings as a "Discard pending reports" action.
  static Future<void> clearQueuedReports() async {
    final q = RetryQueue.instance;
    if (q == null) return;
    await q.clear();
  }

  /// Programmatically open the report overlay from a [BuildContext] below
  /// a `ShakeContext` ancestor. Useful for "Report a bug" buttons in a
  /// Settings page, or on platforms (web, desktop) where the accelerometer
  /// is unreliable.
  ///
  /// Returns `false` if no `ShakeContext` is found above [context] or if
  /// a sheet is already open; `true` if the overlay was scheduled.
  static bool triggerReport(BuildContext context) {
    final state = context
        .dependOnInheritedWidgetOfExactType<_ShakeContextScope>()
        ?.stateOf;
    if (state == null) return false;
    return state._tryOpenOverlay();
  }

  /// Which mode the engine operates in. Typically:
  ///
  /// ```dart
  /// mode: kReleaseMode ? InspectMode.production : InspectMode.developer,
  /// ```
  final InspectMode mode;

  /// Single callback both modes flow through. Inspect [ReportPayload.mode] to
  /// dispatch to the right backend (DevOps vs. customer support).
  final ReportSubmittedCallback onReportSubmitted;

  /// Master toggle. Bind this to a `Switch` on a settings screen so users
  /// can turn the feedback channel off entirely in production.
  final bool isShakeEnabled;

  /// How vigorously the user has to shake the device before the report
  /// sheet opens. Use one of the named constructors on [ShakeSensitivity]
  /// (`.low()`, `.medium()`, `.high()`) for the common cases, or the
  /// unnamed constructor to tune the underlying knobs directly.
  ///
  /// Changes take effect immediately — the engine restarts the listener
  /// with the new profile without rebuilding the rest of the app.
  final ShakeSensitivity shakeSensitivity;

  /// Copy and behavior knobs used when [mode] is [InspectMode.production].
  final ProductionConfig productionConfig;

  /// Diagnostic capture toggles used when [mode] is [InspectMode.developer].
  final DeveloperConfig developerConfig;

  /// Optional `GlobalKey<NavigatorState>` shared with your `MaterialApp`.
  /// Required when `ShakeContext` is placed *above* `MaterialApp` so the
  /// overlay can still find a `Navigator`.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Optional hook fired the instant a shake is detected, before any UI is
  /// shown. Mainly exists so the host app and tests can observe the raw
  /// trigger.
  final VoidCallback? onShakeDetected;

  /// Host-provided context attached to every emitted [ReportPayload.extras].
  ///
  /// Use it for identifiers and stage info the package can't know on its
  /// own: `installationId`, `userId`, `releaseChannel`, `flavor`,
  /// feature-flag state, etc. Values must be JSON-encodable for
  /// [ReportPayload.toJson] to round-trip. Defaults to an empty map.
  ///
  /// The map is captured by reference at construction time but copied into
  /// each payload, so mutating the original map after `ShakeContext` mounts
  /// is undefined — pass a fresh map and rebuild the widget when the
  /// context changes.
  final Map<String, Object?> extras;

  /// The application tree this widget guards.
  final Widget child;

  /// Test seam — substitutes a hand-rolled capturer (e.g. with fake plugins).
  /// Production code leaves this `null`.
  @visibleForTesting
  final ContextCapturer? capturerOverride;

  @override
  State<ShakeContext> createState() => _ShakeContextState();
}

class _ShakeContextState extends State<ShakeContext> {
  late ShakeListener _listener = _buildListener(widget.shakeSensitivity);
  final GlobalKey _boundaryKey = GlobalKey(debugLabel: 'ShakeContextBoundary');


  static ShakeListener _buildListener(ShakeSensitivity sensitivity) =>
      ShakeListener(
        shakeThreshold: sensitivity.threshold,
        minSpikesInWindow: sensitivity.minSpikes,
        timeWindow: sensitivity.window,
        minTimeBetweenShakes: sensitivity.cooldown,
      );
  late final ContextCapturer _capturer = widget.capturerOverride ??
      ContextCapturer(
        boundaryKey: _boundaryKey,
        logBufferSize: widget.developerConfig.logBufferSize,
        networkBufferSize: widget.developerConfig.networkBufferSize,
      );

  /// True while a report sheet is on screen. The listener is paused for the
  /// duration so a second shake can't stack another overlay on top of an
  /// open one.
  bool _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == InspectMode.developer &&
        widget.developerConfig.captureConsoleLogs) {
      _capturer.installLogInterceptor();
    }
    _syncListenerState();
    _wireRetryQueue();
  }

  /// Hand the host's submit callback to the retry queue so the post-boot
  /// timer (and any manual `replayQueuedReports()` call) has something to
  /// invoke. No-op when the queue is disabled. The 5-second post-boot
  /// replay is scheduled inside `ShakeContext.guard` rather than here, so
  /// widget tests that install a queue without going through `guard` don't
  /// have a pending timer to tick through.
  void _wireRetryQueue() {
    final queue = RetryQueue.instance;
    if (queue == null) return;
    queue.registerCallback(widget.onReportSubmitted);
  }

  @override
  void didUpdateWidget(covariant ShakeContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onReportSubmitted != widget.onReportSubmitted) {
      RetryQueue.instance?.registerCallback(widget.onReportSubmitted);
    }
    if (oldWidget.shakeSensitivity != widget.shakeSensitivity) {
      // Tear down the old detector and replace it with one tuned to the
      // new profile. The old subscription is cancelled in `stop()` so we
      // don't leak the sensors_plus stream.
      _listener.stop();
      _listener.dispose();
      _listener = _buildListener(widget.shakeSensitivity);
      _syncListenerState();
    } else if (oldWidget.isShakeEnabled != widget.isShakeEnabled) {
      _syncListenerState();
    }
  }

  void _syncListenerState() {
    if (widget.isShakeEnabled && !_sheetOpen) {
      if (!_listener.isListening) {
        _listener.start(onShake: _handleShake);
      }
    } else {
      _listener.stop();
    }
  }

  ({BuildContext context, NavigatorState navigator})? _resolveOverlayTarget() {
    final keyState = widget.navigatorKey?.currentState;
    if (keyState != null && keyState.mounted) {
      return (context: keyState.context, navigator: keyState);
    }
    final inherited = Navigator.maybeOf(context);
    if (inherited != null) {
      return (context: context, navigator: inherited);
    }
    return null;
  }

  void _handleShake() {
    widget.onShakeDetected?.call();
    _tryOpenOverlay();
  }

  /// Common open path used by both the shake listener and the
  /// `ShakeContext.triggerReport` programmatic entry point. Returns true
  /// when an overlay was scheduled, false when it was suppressed (no
  /// navigator, sheet already open, or widget unmounted).
  bool _tryOpenOverlay() {
    if (!mounted) return false;
    if (_sheetOpen) return false;

    final target = _resolveOverlayTarget();
    if (target == null) {
      if (kDebugMode) {
        debugPrint(
          '[shake_context] No Navigator found above ShakeContext. '
          'Place ShakeContext inside MaterialApp (e.g. as `home:`) or pass a navigatorKey.',
        );
      }
      return false;
    }

    // Snapshot the synchronous bits now and kick off the async captures
    // without awaiting them — the overlay opens immediately and the views
    // reconcile the async results via internal state.
    final captures = _kickOffCaptures(target.navigator);

    _sheetOpen = true;
    _syncListenerState();

    UnifiedOverlay.show(
      context: target.context,
      mode: widget.mode,
      productionConfig: widget.productionConfig,
      developerConfig: widget.developerConfig,
      onSubmit: widget.onReportSubmitted,
      metadata: captures.initialMetadata,
      screenshotFuture: captures.screenshotFuture,
      deviceInfoFuture: captures.deviceInfoFuture,
      onPickImage: captures.onPickImage,
      extras: widget.extras,
    ).whenComplete(() {
      if (!mounted) return;
      _sheetOpen = false;
      _syncListenerState();
    });
    return true;
  }

  _PendingCaptures _kickOffCaptures(NavigatorState nav) {
    switch (widget.mode) {
      case InspectMode.developer:
        final cfg = widget.developerConfig;
        final route = cfg.captureRoute ? _capturer.currentRoute(nav) : null;
        final logs =
            cfg.captureConsoleLogs ? _capturer.drainConsoleLogs() : null;
        final network =
            cfg.captureNetworkLogs ? _capturer.drainNetworkLogs() : null;
        final recovered = LogCapture.instance.recoveredSession;
        // Surface recovered data exactly once — drop the reference so a
        // second shake in the same session doesn't replay it.
        if (recovered != null) {
          LogCapture.instance.recoveredSession = null;
        }
        return _PendingCaptures(
          initialMetadata: ReportMetadata(
            currentRoute: route,
            logs: logs,
            networkLogs: network,
            previousSessionLogs: recovered?.logs,
            previousSessionNetwork: recovered?.network,
            previousSessionStartedAt: recovered?.startedAt,
          ),
          screenshotFuture: cfg.captureScreenshot
              ? _capturer.captureScreenshot(
                  pixelRatio: cfg.screenshotPixelRatio)
              : null,
          deviceInfoFuture:
              cfg.captureDeviceInfo ? _capturer.captureDeviceInfo() : null,
          onPickImage: null,
        );
      case InspectMode.production:
        final cfg = widget.productionConfig;
        return _PendingCaptures(
          // Stamp the trigger time so support can route by recency. The
          // route, logs, and network buffers are deliberately left empty —
          // production mode never captures those.
          initialMetadata: ReportMetadata(),
          screenshotFuture: cfg.allowScreenshotAttachment
              ? _capturer.captureScreenshot(
                  pixelRatio: cfg.screenshotPixelRatio)
              : null,
          deviceInfoFuture:
              cfg.captureDeviceInfo ? _capturer.captureDeviceInfo() : null,
          onPickImage:
              cfg.allowGalleryUpload ? _capturer.pickImageFromGallery : null,
        );
    }
  }

  @override
  void dispose() {
    _capturer.restoreLogInterceptor();
    _listener.dispose();
    RetryQueue.instance?.registerCallback(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ShakeContextScope(
        stateOf: this,
        child: RepaintBoundary(key: _boundaryKey, child: widget.child),
      );
}

/// Inherited handle so `ShakeContext.triggerReport(context)` can reach the
/// nearest state instance without exposing it directly.
class _ShakeContextScope extends InheritedWidget {
  const _ShakeContextScope({
    required this.stateOf,
    required super.child,
  });

  final _ShakeContextState stateOf;

  @override
  bool updateShouldNotify(_ShakeContextScope oldWidget) =>
      stateOf != oldWidget.stateOf;
}

class _PendingCaptures {
  _PendingCaptures({
    required this.initialMetadata,
    required this.screenshotFuture,
    required this.deviceInfoFuture,
    required this.onPickImage,
  });

  final ReportMetadata initialMetadata;
  final Future<Uint8List?>? screenshotFuture;
  final Future<Map<String, Object?>>? deviceInfoFuture;
  final Future<Uint8List?> Function()? onPickImage;
}
