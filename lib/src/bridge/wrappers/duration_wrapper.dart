/// Registers `Duration` host bindings for the CALL_HOST pipeline.
///
/// Covers Duration instance methods, getters, operators, and static constants.
/// The Duration constructor with 7 named params is a known challenge —
/// const Duration() is constant-folded by Kernel and bypasses CALL_HOST.
/// Non-const Duration() goes through CALL_HOST but named param ordering
/// is compiler-dependent.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::Duration` host function bindings.
abstract final class DurationBindings {
  static void register(HostBindings bindings) {
    // ── Getters ──
    bindings.register('dart:core::Duration::inDays#0', (args) {
      return (args[0] as Duration).inDays;
    });
    bindings.register('dart:core::Duration::inHours#0', (args) {
      return (args[0] as Duration).inHours;
    });
    bindings.register('dart:core::Duration::inMinutes#0', (args) {
      return (args[0] as Duration).inMinutes;
    });
    bindings.register('dart:core::Duration::inSeconds#0', (args) {
      return (args[0] as Duration).inSeconds;
    });
    bindings.register('dart:core::Duration::inMilliseconds#0', (args) {
      return (args[0] as Duration).inMilliseconds;
    });
    bindings.register('dart:core::Duration::inMicroseconds#0', (args) {
      return (args[0] as Duration).inMicroseconds;
    });
    bindings.register('dart:core::Duration::isNegative#0', (args) {
      return (args[0] as Duration).isNegative;
    });
    bindings.register('dart:core::Duration::hashCode#0', (args) {
      return (args[0] as Duration).hashCode;
    });

    // ── Methods ──
    bindings.register('dart:core::Duration::abs#0', (args) {
      return (args[0] as Duration).abs();
    });
    bindings.register('dart:core::Duration::compareTo#1', (args) {
      return (args[0] as Duration).compareTo(args[1] as Duration);
    });
    bindings.register('dart:core::Duration::toString#0', (args) {
      return (args[0] as Duration).toString();
    });

    // ── Operators ──
    bindings.register('dart:core::Duration::+#1', (args) {
      return (args[0] as Duration) + (args[1] as Duration);
    });
    bindings.register('dart:core::Duration::-#1', (args) {
      return (args[0] as Duration) - (args[1] as Duration);
    });
    bindings.register('dart:core::Duration::*#1', (args) {
      return (args[0] as Duration) * (args[1] as num);
    });
    bindings.register('dart:core::Duration::~/#1', (args) {
      return (args[0] as Duration) ~/ (args[1] as int);
    });
    bindings.register('dart:core::Duration::<#1', (args) {
      return (args[0] as Duration) < (args[1] as Duration);
    });
    bindings.register('dart:core::Duration::>#1', (args) {
      return (args[0] as Duration) > (args[1] as Duration);
    });
    bindings.register('dart:core::Duration::<=#1', (args) {
      return (args[0] as Duration) <= (args[1] as Duration);
    });
    bindings.register('dart:core::Duration::>=#1', (args) {
      return (args[0] as Duration) >= (args[1] as Duration);
    });
    bindings.register('dart:core::Duration::unary-#0', (args) {
      return -(args[0] as Duration);
    });

    // ── Constructor ──
    // Duration({days, hours, minutes, seconds, milliseconds, microseconds})
    // 6 named params → symbol: dart:core::Duration::#6
    // Named args are passed in declaration order by the compiler.
    // const Duration() is constant-folded by Kernel; only non-const goes here.
    bindings.register('dart:core::Duration::#6', (args) {
      if (args.isEmpty) return Duration.zero;
      return Duration(
        days: args[0] as int? ?? 0,
        hours: args.length > 1 ? (args[1] as int? ?? 0) : 0,
        minutes: args.length > 2 ? (args[2] as int? ?? 0) : 0,
        seconds: args.length > 3 ? (args[3] as int? ?? 0) : 0,
        milliseconds: args.length > 4 ? (args[4] as int? ?? 0) : 0,
        microseconds: args.length > 5 ? (args[5] as int? ?? 0) : 0,
      );
    });

    // ── Static getters / constants ──
    bindings.register('dart:core::Duration::zero#0', (args) {
      return Duration.zero;
    });
    bindings.register('dart:core::Duration::microsecondsPerMillisecond#0',
        (args) {
      return Duration.microsecondsPerMillisecond;
    });
    bindings.register('dart:core::Duration::millisecondsPerSecond#0', (args) {
      return Duration.millisecondsPerSecond;
    });
    bindings.register('dart:core::Duration::secondsPerMinute#0', (args) {
      return Duration.secondsPerMinute;
    });
    bindings.register('dart:core::Duration::minutesPerHour#0', (args) {
      return Duration.minutesPerHour;
    });
    bindings.register('dart:core::Duration::hoursPerDay#0', (args) {
      return Duration.hoursPerDay;
    });
  }
}
