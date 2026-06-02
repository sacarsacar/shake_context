import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shake_context/src/core/shake_listener.dart';

/// Builds an AccelerometerEvent with the given m/s² magnitude on the x axis.
/// 30 m/s² ≈ 3.06 g, comfortably above the 2.7 g default threshold.
AccelerometerEvent _spike([double x = 30]) =>
    AccelerometerEvent(x, 0, 0, DateTime.now());

AccelerometerEvent _quiet() => AccelerometerEvent(0.5, 0.5, 9.81, DateTime.now());

void main() {
  late StreamController<AccelerometerEvent> stream;
  late DateTime clock;

  setUp(() {
    stream = StreamController<AccelerometerEvent>.broadcast();
    clock = DateTime(2026, 1, 1, 12, 0, 0);
    ShakeListener.streamFactoryOverride = () => stream.stream;
  });

  tearDown(() async {
    ShakeListener.streamFactoryOverride = null;
    if (!stream.isClosed) await stream.close();
  });

  ShakeListener buildListener({
    Duration window = const Duration(milliseconds: 500),
    int minSpikes = 3,
    Duration cooldown = const Duration(milliseconds: 1000),
  }) =>
      ShakeListener(
        timeWindow: window,
        minSpikesInWindow: minSpikes,
        minTimeBetweenShakes: cooldown,
        now: () => clock,
      );

  Future<void> emit(ShakeListener listener, AccelerometerEvent e) async {
    stream.add(e);
    await Future<void>.delayed(Duration.zero);
  }

  test('fires onShake when N spikes accumulate inside the window', () async {
    final listener = buildListener();
    var fired = 0;
    listener.start(onShake: () => fired++);

    for (var i = 0; i < 3; i++) {
      await emit(listener, _spike());
      clock = clock.add(const Duration(milliseconds: 100));
    }

    expect(fired, 1);
    listener.dispose();
  });

  test('ignores sub-threshold motion', () async {
    final listener = buildListener();
    var fired = 0;
    listener.start(onShake: () => fired++);

    for (var i = 0; i < 10; i++) {
      await emit(listener, _quiet());
      clock = clock.add(const Duration(milliseconds: 50));
    }

    expect(fired, 0);
    listener.dispose();
  });

  test('drops spikes that fall outside the rolling window', () async {
    final listener = buildListener();
    var fired = 0;
    listener.start(onShake: () => fired++);

    // Two spikes, then a 1-second gap, then one spike — should NOT fire
    // because the first two spikes have aged out of the 500 ms window.
    await emit(listener, _spike());
    clock = clock.add(const Duration(milliseconds: 100));
    await emit(listener, _spike());
    clock = clock.add(const Duration(seconds: 1));
    await emit(listener, _spike());

    expect(fired, 0);
    listener.dispose();
  });

  test('cool-down suppresses immediate re-fire after a shake', () async {
    final listener = buildListener();
    var fired = 0;
    listener.start(onShake: () => fired++);

    // First burst — fires.
    for (var i = 0; i < 3; i++) {
      await emit(listener, _spike());
      clock = clock.add(const Duration(milliseconds: 50));
    }
    expect(fired, 1);

    // Second burst inside the 1s cool-down — should not fire.
    for (var i = 0; i < 3; i++) {
      await emit(listener, _spike());
      clock = clock.add(const Duration(milliseconds: 50));
    }
    expect(fired, 1);

    // Advance past the cool-down; another burst fires.
    clock = clock.add(const Duration(milliseconds: 1100));
    for (var i = 0; i < 3; i++) {
      await emit(listener, _spike());
      clock = clock.add(const Duration(milliseconds: 50));
    }
    expect(fired, 2);

    listener.dispose();
  });

  test('stop() cancels subscription and clears state', () async {
    final listener = buildListener();
    var fired = 0;
    listener.start(onShake: () => fired++);
    expect(listener.isListening, isTrue);

    await emit(listener, _spike());
    await emit(listener, _spike());
    listener.stop();
    expect(listener.isListening, isFalse);

    // After stop(), further events go nowhere even if we re-add — the
    // subscription is gone.
    await emit(listener, _spike());
    expect(fired, 0);

    // Restarting clears any leftover state.
    listener.start(onShake: () => fired++);
    for (var i = 0; i < 3; i++) {
      await emit(listener, _spike());
      clock = clock.add(const Duration(milliseconds: 50));
    }
    expect(fired, 1);

    listener.dispose();
  });

  test('start() while already listening is a no-op', () async {
    final listener = buildListener();
    var first = 0;
    var second = 0;
    listener.start(onShake: () => first++);
    listener.start(onShake: () => second++);

    for (var i = 0; i < 3; i++) {
      await emit(listener, _spike());
      clock = clock.add(const Duration(milliseconds: 50));
    }

    expect(first, 1);
    expect(second, 0);
    listener.dispose();
  });
}
