/// Registers `double` host bindings for the CALL_HOST pipeline.
///
/// Covers instance methods, getters, static methods, and constants
/// declared on `double`. Basic arithmetic (+, -, *, /, %, <, >, ==,
/// unary-) uses specialized opcodes and is NOT handled here.
///
/// Methods inherited from `num` that Kernel resolves to `num` are
/// registered separately in [NumBindings].
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::double` host function bindings.
abstract final class DoubleBindings {
  static void register(HostBindings bindings) {
    // ── Instance methods ──

    // double.toString()
    bindings.register('dart:core::double::toString#0', (args) {
      return (args[0] as double).toString();
    });

    // double.ceil()
    bindings.register('dart:core::double::ceil#0', (args) {
      return (args[0] as double).ceil();
    });

    // double.floor()
    bindings.register('dart:core::double::floor#0', (args) {
      return (args[0] as double).floor();
    });

    // double.round()
    bindings.register('dart:core::double::round#0', (args) {
      return (args[0] as double).round();
    });

    // double.truncate()
    bindings.register('dart:core::double::truncate#0', (args) {
      return (args[0] as double).truncate();
    });

    // double.toInt()
    bindings.register('dart:core::double::toInt#0', (args) {
      return (args[0] as double).toInt();
    });

    // double.toDouble()
    bindings.register('dart:core::double::toDouble#0', (args) {
      return (args[0] as double).toDouble();
    });

    // double.abs()
    bindings.register('dart:core::double::abs#0', (args) {
      return (args[0] as double).abs();
    });

    // ── Instance getters ──

    // double.sign getter
    bindings.register('dart:core::double::sign#0', (args) {
      return (args[0] as double).sign;
    });

    // double.isFinite getter
    bindings.register('dart:core::double::isFinite#0', (args) {
      return (args[0] as double).isFinite;
    });

    // double.isInfinite getter
    bindings.register('dart:core::double::isInfinite#0', (args) {
      return (args[0] as double).isInfinite;
    });

    // double.isNaN getter
    bindings.register('dart:core::double::isNaN#0', (args) {
      return (args[0] as double).isNaN;
    });

    // double.isNegative getter
    bindings.register('dart:core::double::isNegative#0', (args) {
      return (args[0] as double).isNegative;
    });

    // ── Instance methods with parameters ──

    // double.clamp(num lower, num upper) — 2 params
    bindings.register('dart:core::double::clamp#2', (args) {
      return (args[0] as double).clamp(args[1] as num, args[2] as num);
    });

    // double.compareTo(num other) — 1 param
    bindings.register('dart:core::double::compareTo#1', (args) {
      return (args[0] as double).compareTo(args[1] as num);
    });

    // double.remainder(num other) — 1 param
    bindings.register('dart:core::double::remainder#1', (args) {
      return (args[0] as double).remainder(args[1] as num);
    });

    // double.ceilToDouble()
    bindings.register('dart:core::double::ceilToDouble#0', (args) {
      return (args[0] as double).ceilToDouble();
    });

    // double.floorToDouble()
    bindings.register('dart:core::double::floorToDouble#0', (args) {
      return (args[0] as double).floorToDouble();
    });

    // double.roundToDouble()
    bindings.register('dart:core::double::roundToDouble#0', (args) {
      return (args[0] as double).roundToDouble();
    });

    // double.truncateToDouble()
    bindings.register('dart:core::double::truncateToDouble#0', (args) {
      return (args[0] as double).truncateToDouble();
    });

    // double.hashCode getter
    bindings.register('dart:core::double::hashCode#0', (args) {
      return (args[0] as double).hashCode;
    });

    // double.toStringAsFixed(int fractionDigits) — 1 param
    bindings.register('dart:core::double::toStringAsFixed#1', (args) {
      return (args[0] as double).toStringAsFixed(args[1] as int);
    });

    // double.toStringAsPrecision(int precision) — 1 param
    bindings.register('dart:core::double::toStringAsPrecision#1', (args) {
      return (args[0] as double).toStringAsPrecision(args[1] as int);
    });

    // double.toStringAsExponential([int? fractionDigits]) — 1 formal param
    bindings.register('dart:core::double::toStringAsExponential#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as double).toStringAsExponential(args[1] as int);
      }
      return (args[0] as double).toStringAsExponential();
    });

    // ── Static methods ──

    // double.parse(String source) — 1 formal param
    bindings.register('dart:core::double::parse#1', (args) {
      return double.parse(args[0] as String);
    });

    // double.tryParse(String source) — 1 formal param
    bindings.register('dart:core::double::tryParse#1', (args) {
      return double.tryParse(args[0] as String);
    });

    // ── Static constants ──
    // These may be compiled as constant expressions rather than CALL_HOST.
    // Registered as a fallback in case the compiler routes them here.

    bindings.register('dart:core::double::infinity#0', (args) {
      return double.infinity;
    });

    bindings.register('dart:core::double::nan#0', (args) {
      return double.nan;
    });

    bindings.register('dart:core::double::negativeInfinity#0', (args) {
      return double.negativeInfinity;
    });

    bindings.register('dart:core::double::maxFinite#0', (args) {
      return double.maxFinite;
    });

    bindings.register('dart:core::double::minPositive#0', (args) {
      return double.minPositive;
    });
  }
}
