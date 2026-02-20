/// Registers `int`-specific host registry for the CALL_HOST pipeline.
///
/// Covers int instance methods, getters, and static methods that are
/// declared on `int` (not inherited from `num`). Methods that use
/// specialized opcodes (arithmetic, bitwise, toDouble) are excluded.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::int` host function registry.
abstract final class IntBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Instance methods ──

    // int.toString() — receiver is args[0]
    registry.register('dart:core::int::toString#0', (args) {
      return (args[0] as int).toString();
    });

    // ── Instance getters ──

    // int.isEven getter
    registry.register('dart:core::int::isEven#0', (args) {
      return (args[0] as int).isEven;
    });

    // int.isOdd getter
    registry.register('dart:core::int::isOdd#0', (args) {
      return (args[0] as int).isOdd;
    });

    // int.bitLength getter
    registry.register('dart:core::int::bitLength#0', (args) {
      return (args[0] as int).bitLength;
    });

    // int.sign getter (overrides num.sign, returns int)
    registry.register('dart:core::int::sign#0', (args) {
      return (args[0] as int).sign;
    });

    // ── Instance methods ──

    // int.abs() — int overrides num.abs() returning int
    registry.register('dart:core::int::abs#0', (args) {
      return (args[0] as int).abs();
    });

    // int.toRadixString(int radix) — 1 param
    registry.register('dart:core::int::toRadixString#1', (args) {
      return (args[0] as int).toRadixString(args[1] as int);
    });

    // int.gcd(int other) — 1 param
    registry.register('dart:core::int::gcd#1', (args) {
      return (args[0] as int).gcd(args[1] as int);
    });

    // int.modPow(int exponent, int modulus) — 2 params
    registry.register('dart:core::int::modPow#2', (args) {
      return (args[0] as int).modPow(args[1] as int, args[2] as int);
    });

    // int.modInverse(int modulus) — 1 param
    registry.register('dart:core::int::modInverse#1', (args) {
      return (args[0] as int).modInverse(args[1] as int);
    });

    // int.toSigned(int width) — 1 param
    registry.register('dart:core::int::toSigned#1', (args) {
      return (args[0] as int).toSigned(args[1] as int);
    });

    // int.toUnsigned(int width) — 1 param
    registry.register('dart:core::int::toUnsigned#1', (args) {
      return (args[0] as int).toUnsigned(args[1] as int);
    });

    // int.ceil/floor/round/truncate — int overrides these (identity)
    registry.register('dart:core::int::ceil#0', (args) {
      return (args[0] as int).ceil();
    });
    registry.register('dart:core::int::floor#0', (args) {
      return (args[0] as int).floor();
    });
    registry.register('dart:core::int::round#0', (args) {
      return (args[0] as int).round();
    });
    registry.register('dart:core::int::truncate#0', (args) {
      return (args[0] as int).truncate();
    });

    // int.toInt() — identity
    registry.register('dart:core::int::toInt#0', (args) {
      return (args[0] as int).toInt();
    });

    // int.toDouble()
    registry.register('dart:core::int::toDouble#0', (args) {
      return (args[0] as int).toDouble();
    });

    // int.remainder(num other) — may resolve to int
    registry.register('dart:core::int::remainder#1', (args) {
      return (args[0] as int).remainder(args[1] as num);
    });

    // int.compareTo(num other)
    registry.register('dart:core::int::compareTo#1', (args) {
      return (args[0] as int).compareTo(args[1] as num);
    });

    // int.clamp(num lower, num upper)
    registry.register('dart:core::int::clamp#2', (args) {
      return (args[0] as int).clamp(args[1] as num, args[2] as num);
    });

    // int.toStringAsFixed(int fractionDigits) — 1 param
    registry.register('dart:core::int::toStringAsFixed#1', (args) {
      return (args[0] as int).toStringAsFixed(args[1] as int);
    });

    // int.toStringAsPrecision(int precision) — 1 param
    registry.register('dart:core::int::toStringAsPrecision#1', (args) {
      return (args[0] as int).toStringAsPrecision(args[1] as int);
    });

    // int.toStringAsExponential([int? fractionDigits]) — 1 formal param
    registry.register('dart:core::int::toStringAsExponential#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as int).toStringAsExponential(args[1] as int);
      }
      return (args[0] as int).toStringAsExponential();
    });

    // ── Static methods ──

    // int.parse(String source, {int? radix, int Function(String)? onError})
    // Kernel sees 3 formal params: source, radix, onError
    registry.register('dart:core::int::parse#3', (args) {
      final source = args[0] as String;
      if (args.length > 1 && args[1] != null) {
        return int.parse(source, radix: args[1] as int);
      }
      return int.parse(source);
    });

    // int.tryParse(String source, {int? radix}) — 2 formal params
    registry.register('dart:core::int::tryParse#2', (args) {
      final source = args[0] as String;
      if (args.length > 1 && args[1] != null) {
        return int.tryParse(source, radix: args[1] as int);
      }
      return int.tryParse(source);
    });
  }
}
