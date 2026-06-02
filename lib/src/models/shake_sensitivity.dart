import 'package:flutter/foundation.dart';

/// How aggressively the engine treats motion as a "shake".
///
/// Pass an instance to `ShakeContext.shakeSensitivity` to tune how hard the
/// user has to shake the device before the report sheet opens. Three named
/// presets cover the common cases; the unnamed constructor is a custom
/// escape hatch for projects that need to dial in exact values (e.g. tablet
/// builds, kiosk devices, or app-specific accessibility tuning).
///
/// Semantics:
///
///   * [ShakeSensitivity.low] — harder to trigger. Useful when false
///     positives are costly (the sheet would interrupt a critical flow).
///   * [ShakeSensitivity.medium] — balanced default, matches what most
///     "shake to feedback" apps feel like.
///   * [ShakeSensitivity.high] — fires on lighter motion. Useful for
///     accessibility, or for QA builds where the trigger should be easy.
///
/// The underlying knobs:
///
///   * [threshold] — minimum g-force magnitude for one accelerometer sample
///     to count as a "spike". Lower → easier to trigger.
///   * [minSpikes] — how many spikes must accumulate inside [window] before
///     a shake fires. Lower → easier to trigger.
///   * [window] — rolling window inside which spikes are counted.
///   * [cooldown] — quiet period after a successful trigger before the next
///     can fire, to prevent one vigorous motion stacking multiple sheets.
@immutable
class ShakeSensitivity {
  /// Custom sensitivity profile. Use the named constructors below unless
  /// you have a measured reason to deviate.
  const ShakeSensitivity({
    required this.threshold,
    required this.minSpikes,
    this.window = const Duration(milliseconds: 500),
    this.cooldown = const Duration(milliseconds: 1000),
  })  : assert(threshold > 0, 'threshold must be positive'),
        assert(minSpikes > 0, 'minSpikes must be at least 1');

  /// Harder to trigger — needs a deliberate, vigorous shake. Recommended
  /// when the app is in the user's hand for long stretches and accidental
  /// triggers would interrupt critical flows.
  const ShakeSensitivity.low()
      : threshold = 3.2,
        minSpikes = 4,
        window = const Duration(milliseconds: 500),
        cooldown = const Duration(milliseconds: 1000);

  /// Balanced default — what most apps mean by "shake to send feedback".
  const ShakeSensitivity.medium()
      : threshold = 2.7,
        minSpikes = 3,
        window = const Duration(milliseconds: 500),
        cooldown = const Duration(milliseconds: 1000);

  /// Easier to trigger — fires on lighter motion. May produce occasional
  /// false positives during walking or vehicle travel.
  const ShakeSensitivity.high()
      : threshold = 2.2,
        minSpikes = 2,
        window = const Duration(milliseconds: 500),
        cooldown = const Duration(milliseconds: 1000);

  /// Minimum g-force magnitude for one accelerometer sample to count as a
  /// spike.
  final double threshold;

  /// Number of spikes that must accumulate inside [window] for a shake to
  /// fire.
  final int minSpikes;

  /// Rolling window inside which spikes are counted.
  final Duration window;

  /// Quiet period after a successful trigger before the next can fire.
  final Duration cooldown;

  ShakeSensitivity copyWith({
    double? threshold,
    int? minSpikes,
    Duration? window,
    Duration? cooldown,
  }) {
    return ShakeSensitivity(
      threshold: threshold ?? this.threshold,
      minSpikes: minSpikes ?? this.minSpikes,
      window: window ?? this.window,
      cooldown: cooldown ?? this.cooldown,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShakeSensitivity &&
        other.threshold == threshold &&
        other.minSpikes == minSpikes &&
        other.window == window &&
        other.cooldown == cooldown;
  }

  @override
  int get hashCode => Object.hash(threshold, minSpikes, window, cooldown);
}
