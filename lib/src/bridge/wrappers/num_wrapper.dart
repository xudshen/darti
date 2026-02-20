/// Registers `num` host bindings for the CALL_HOST pipeline.
///
/// Covers num instance methods, getters, and static methods declared
/// on the `num` class. These bindings handle calls where Kernel resolves
/// the target to `num` (the declaring class).
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::num` host function bindings.
abstract final class NumBindings {
  static void register(HostBindings bindings) {
    // ── Instance methods ──

    // num.abs()
    bindings.register('dart:core::num::abs#0', (args) {
      return (args[0] as num).abs();
    });

    // num.ceil()
    bindings.register('dart:core::num::ceil#0', (args) {
      return (args[0] as num).ceil();
    });

    // num.floor()
    bindings.register('dart:core::num::floor#0', (args) {
      return (args[0] as num).floor();
    });

    // num.round()
    bindings.register('dart:core::num::round#0', (args) {
      return (args[0] as num).round();
    });

    // num.truncate()
    bindings.register('dart:core::num::truncate#0', (args) {
      return (args[0] as num).truncate();
    });

    // num.toInt()
    bindings.register('dart:core::num::toInt#0', (args) {
      return (args[0] as num).toInt();
    });

    // num.toDouble()
    bindings.register('dart:core::num::toDouble#0', (args) {
      return (args[0] as num).toDouble();
    });

    // ── Instance getters ──

    // num.sign getter
    bindings.register('dart:core::num::sign#0', (args) {
      return (args[0] as num).sign;
    });

    // num.isFinite getter
    bindings.register('dart:core::num::isFinite#0', (args) {
      return (args[0] as num).isFinite;
    });

    // num.isInfinite getter
    bindings.register('dart:core::num::isInfinite#0', (args) {
      return (args[0] as num).isInfinite;
    });

    // num.isNaN getter
    bindings.register('dart:core::num::isNaN#0', (args) {
      return (args[0] as num).isNaN;
    });

    // num.isNegative getter
    bindings.register('dart:core::num::isNegative#0', (args) {
      return (args[0] as num).isNegative;
    });

    // ── Instance methods with parameters ──

    // num.clamp(num lower, num upper) — 2 params
    bindings.register('dart:core::num::clamp#2', (args) {
      return (args[0] as num).clamp(args[1] as num, args[2] as num);
    });

    // num.compareTo(num other) — 1 param
    bindings.register('dart:core::num::compareTo#1', (args) {
      return (args[0] as num).compareTo(args[1] as num);
    });

    // num.remainder(num other) — 1 param
    bindings.register('dart:core::num::remainder#1', (args) {
      return (args[0] as num).remainder(args[1] as num);
    });

    // num.toStringAsFixed(int fractionDigits) — 1 param
    bindings.register('dart:core::num::toStringAsFixed#1', (args) {
      return (args[0] as num).toStringAsFixed(args[1] as int);
    });

    // num.toStringAsPrecision(int precision) — 1 param
    bindings.register('dart:core::num::toStringAsPrecision#1', (args) {
      return (args[0] as num).toStringAsPrecision(args[1] as int);
    });

    // num.toStringAsExponential([int? fractionDigits]) — 1 formal param
    bindings.register('dart:core::num::toStringAsExponential#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as num).toStringAsExponential(args[1] as int);
      }
      return (args[0] as num).toStringAsExponential();
    });

    // num.toString() — override Object.toString for num
    bindings.register('dart:core::num::toString#0', (args) {
      return (args[0] as num).toString();
    });

    // num.hashCode getter
    bindings.register('dart:core::num::hashCode#0', (args) {
      return (args[0] as num).hashCode;
    });

    // ── Static methods ──

    // num.parse(String input, [num onError(String)?]) — 2 formal params
    bindings.register('dart:core::num::parse#2', (args) {
      return num.parse(args[0] as String);
    });

    // num.tryParse(String input) — 1 formal param
    bindings.register('dart:core::num::tryParse#1', (args) {
      return num.tryParse(args[0] as String);
    });
  }
}
