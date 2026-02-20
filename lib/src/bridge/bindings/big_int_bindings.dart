/// Registers `BigInt` host bindings for the CALL_HOST pipeline.
///
/// Covers BigInt factory constructors, static constants, instance getters,
/// methods, and operators.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::BigInt` host function bindings.
abstract final class BigIntBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Factory constructors ──

    // BigInt.from(num value)
    registry.register('dart:core::BigInt::from#1', (args) {
      return BigInt.from(args[0] as num);
    });

    // BigInt.parse(String source, {int? radix})
    registry.register('dart:core::BigInt::parse#2', (args) {
      if (args.length > 1 && args[1] != null) {
        return BigInt.parse(args[0] as String, radix: args[1] as int);
      }
      return BigInt.parse(args[0] as String);
    });

    // BigInt.tryParse(String source, {int? radix})
    registry.register('dart:core::BigInt::tryParse#2', (args) {
      if (args.length > 1 && args[1] != null) {
        return BigInt.tryParse(args[0] as String, radix: args[1] as int);
      }
      return BigInt.tryParse(args[0] as String);
    });

    // ── Static constants (accessed as getters in Kernel) ──
    registry.register('dart:core::BigInt::zero#0', (args) {
      return BigInt.zero;
    });
    registry.register('dart:core::BigInt::one#0', (args) {
      return BigInt.one;
    });
    registry.register('dart:core::BigInt::two#0', (args) {
      return BigInt.two;
    });

    // ── Getters ──
    registry.register('dart:core::BigInt::isEven#0', (args) {
      return (args[0] as BigInt).isEven;
    });
    registry.register('dart:core::BigInt::isOdd#0', (args) {
      return (args[0] as BigInt).isOdd;
    });
    registry.register('dart:core::BigInt::isNegative#0', (args) {
      return (args[0] as BigInt).isNegative;
    });
    registry.register('dart:core::BigInt::isValidInt#0', (args) {
      return (args[0] as BigInt).isValidInt;
    });
    registry.register('dart:core::BigInt::bitLength#0', (args) {
      return (args[0] as BigInt).bitLength;
    });
    registry.register('dart:core::BigInt::sign#0', (args) {
      return (args[0] as BigInt).sign;
    });
    registry.register('dart:core::BigInt::hashCode#0', (args) {
      return (args[0] as BigInt).hashCode;
    });

    // ── Methods ──
    registry.register('dart:core::BigInt::abs#0', (args) {
      return (args[0] as BigInt).abs();
    });
    registry.register('dart:core::BigInt::compareTo#1', (args) {
      return (args[0] as BigInt).compareTo(args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::gcd#1', (args) {
      return (args[0] as BigInt).gcd(args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::modInverse#1', (args) {
      return (args[0] as BigInt).modInverse(args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::modPow#2', (args) {
      return (args[0] as BigInt).modPow(args[1] as BigInt, args[2] as BigInt);
    });
    registry.register('dart:core::BigInt::pow#1', (args) {
      return (args[0] as BigInt).pow(args[1] as int);
    });
    registry.register('dart:core::BigInt::remainder#1', (args) {
      return (args[0] as BigInt).remainder(args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::toInt#0', (args) {
      return (args[0] as BigInt).toInt();
    });
    registry.register('dart:core::BigInt::toDouble#0', (args) {
      return (args[0] as BigInt).toDouble();
    });
    registry.register('dart:core::BigInt::toRadixString#1', (args) {
      return (args[0] as BigInt).toRadixString(args[1] as int);
    });
    registry.register('dart:core::BigInt::toString#0', (args) {
      return (args[0] as BigInt).toString();
    });
    registry.register('dart:core::BigInt::toSigned#1', (args) {
      return (args[0] as BigInt).toSigned(args[1] as int);
    });
    registry.register('dart:core::BigInt::toUnsigned#1', (args) {
      return (args[0] as BigInt).toUnsigned(args[1] as int);
    });

    // ── Operators ──
    registry.register('dart:core::BigInt::+#1', (args) {
      return (args[0] as BigInt) + (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::-#1', (args) {
      return (args[0] as BigInt) - (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::*#1', (args) {
      return (args[0] as BigInt) * (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::~/#1', (args) {
      return (args[0] as BigInt) ~/ (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::%#1', (args) {
      return (args[0] as BigInt) % (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::<<#1', (args) {
      return (args[0] as BigInt) << (args[1] as int);
    });
    registry.register('dart:core::BigInt::>>#1', (args) {
      return (args[0] as BigInt) >> (args[1] as int);
    });
    registry.register('dart:core::BigInt::&#1', (args) {
      return (args[0] as BigInt) & (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::|#1', (args) {
      return (args[0] as BigInt) | (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::^#1', (args) {
      return (args[0] as BigInt) ^ (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::~#0', (args) {
      return ~(args[0] as BigInt);
    });
    registry.register('dart:core::BigInt::<#1', (args) {
      return (args[0] as BigInt) < (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::<=#1', (args) {
      return (args[0] as BigInt) <= (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::>#1', (args) {
      return (args[0] as BigInt) > (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::>=#1', (args) {
      return (args[0] as BigInt) >= (args[1] as BigInt);
    });
    registry.register('dart:core::BigInt::unary-#0', (args) {
      return -(args[0] as BigInt);
    });
    registry.register('dart:core::BigInt::==#1', (args) {
      return args[0] == args[1];
    });
  }
}
