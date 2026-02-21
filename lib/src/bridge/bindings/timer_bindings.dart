/// Registers `dart:async::Timer` host bindings for the CALL_HOST pipeline.
///
/// Covers Timer constructors, run, periodic, cancel, and getters.
///
/// See: docs/design/04-interop.md
library;

import 'dart:async';

import '../host_function_registry.dart';

/// Registers all `dart:async::Timer` host function bindings.
abstract final class TimerBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Constructors ──

    // Timer(Duration duration, void Function() callback)
    registry.register('dart:async::Timer::#2', (args) {
      final duration = args[0] as Duration;
      final callback = args[1] as Function;
      return Timer(duration, () => callback());
    });

    // Timer.periodic(Duration duration, void Function(Timer) callback)
    registry.register('dart:async::Timer::periodic#2', (args) {
      final duration = args[0] as Duration;
      final callback = args[1] as Function;
      return Timer.periodic(duration, (t) => callback(t));
    });

    // ── Static methods ──

    // Timer.run(void Function() callback)
    registry.register('dart:async::Timer::run#1', (args) {
      final callback = args[0] as Function;
      Timer.run(() => callback());
      return null;
    });

    // ── Instance methods ──

    // timer.cancel()
    registry.register('dart:async::Timer::cancel#0', (args) {
      (args[0] as Timer).cancel();
      return null;
    });

    // ── Getters ──

    // timer.isActive → bool
    registry.register('dart:async::Timer::isActive#0', (args) {
      return (args[0] as Timer).isActive;
    });

    // timer.tick → int
    registry.register('dart:async::Timer::tick#0', (args) {
      return (args[0] as Timer).tick;
    });
  }
}
