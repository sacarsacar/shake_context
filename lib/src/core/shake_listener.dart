import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Filters raw accelerometer samples into deliberate shake gestures.
///
/// Algorithm:
///   1. Convert each sample to a g-force magnitude (`|a| / 9.80665`).
///   2. When the magnitude crosses [shakeThreshold] it counts as a "spike".
///   3. If at least [minSpikesInWindow] spikes occur inside [timeWindow]
///      the listener fires `onShake`.
///   4. After firing, further shakes are suppressed for
///      [minTimeBetweenShakes] to avoid duplicate triggers from a single
///      vigorous motion.
///
/// Spike-counting is a natural directional-change filter — a body in motion
/// stays in motion, so multiple acceleration spikes within ~500 ms imply
/// repeated reversals, which is what distinguishes a shake from walking or a
/// pocket shift.
class ShakeListener {
  ShakeListener({
    this.shakeThreshold = 2.7,
    this.minSpikesInWindow = 3,
    this.timeWindow = const Duration(milliseconds: 500),
    this.minTimeBetweenShakes = const Duration(milliseconds: 1000),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Test seam — when non-null, [start] subscribes to this stream instead of
  /// the real `sensors_plus` accelerometer stream. Production code leaves
  /// this `null`.
  @visibleForTesting
  static Stream<AccelerometerEvent> Function()? streamFactoryOverride;

  static const double _gravity = 9.80665;

  /// Minimum g-force magnitude for a sample to count as a spike.
  final double shakeThreshold;

  /// Number of spikes that must accumulate inside [timeWindow] to fire.
  final int minSpikesInWindow;

  /// Rolling window inside which spikes accumulate.
  final Duration timeWindow;

  /// Cool-down after a successful trigger before the next can fire.
  final Duration minTimeBetweenShakes;

  final DateTime Function() _now;
  // ListQueue gives O(1) `removeFirst` so eviction inside `_onSample` stays
  // cheap when the spike buffer fills up under sustained motion. With the
  // sensor running at gameInterval (~20 Hz × 3 axes) the prior `List.removeAt(0)`
  // was O(n) per aged-out sample — a small but observable battery / CPU cost.
  final ListQueue<DateTime> _recentSpikes = ListQueue<DateTime>();
  DateTime? _lastShakeAt;
  StreamSubscription<AccelerometerEvent>? _subscription;
  VoidCallback? _onShake;

  bool get isListening => _subscription != null;

  /// `sensors_plus` only ships an accelerometer implementation for Android
  /// and iOS. On every other host (macOS, Windows, Linux, web) the platform
  /// channel call would surface a `MissingPluginException` that propagates
  /// to the zone error handler installed by `ShakeContext.guard` — i.e. it
  /// would land in every host's error tracker as noise on every boot.
  static bool get _platformHasAccelerometer {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Begin sampling the accelerometer. Calling [start] while already
  /// listening is a no-op — the existing subscription and callback are kept.
  ///
  /// On platforms without an accelerometer ([sensors_plus] only implements
  /// Android and iOS), this is a silent no-op — hosts on those platforms
  /// should call `ShakeContext.triggerReport` from a button instead.
  void start({required VoidCallback onShake}) {
    if (_subscription != null) return;
    if (streamFactoryOverride == null && !_platformHasAccelerometer) return;
    _onShake = onShake;
    _recentSpikes.clear();
    _lastShakeAt = null;
    final stream = streamFactoryOverride?.call() ??
        accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval);
    _subscription = stream.listen(
      _onSample,
      onError: (Object error, StackTrace stack) {
        if (kDebugMode) {
          debugPrint('[shake_context] accelerometer stream error: $error');
        }
      },
      cancelOnError: true,
    );
  }

  /// Cancel the subscription and discard accumulated state.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _onShake = null;
    _recentSpikes.clear();
    _lastShakeAt = null;
  }

  void dispose() => stop();

  void _onSample(AccelerometerEvent event) {
    final gx = event.x / _gravity;
    final gy = event.y / _gravity;
    final gz = event.z / _gravity;
    final gForce = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (gForce <= shakeThreshold) return;

    final now = _now();
    _recentSpikes.add(now);

    final cutoff = now.subtract(timeWindow);
    while (_recentSpikes.isNotEmpty && _recentSpikes.first.isBefore(cutoff)) {
      _recentSpikes.removeFirst();
    }

    if (_recentSpikes.length < minSpikesInWindow) return;

    if (_lastShakeAt != null &&
        now.difference(_lastShakeAt!) < minTimeBetweenShakes) {
      return;
    }
    _lastShakeAt = now;
    _recentSpikes.clear();
    _onShake?.call();
  }
}
