/// Registers Object, Type, Null, and `identical` bindings.
///
/// Supplements the basic Object bindings in [CoreBindings] with
/// additional members: runtimeType, noSuchMethod, and the top-level
/// `identical` function. Also registers Type members.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers Object, Type, Null, and `identical` bindings.
abstract final class ObjectBindings {
  static void register(HostBindings bindings) {
    // ── Object supplemental methods ──

    // Object.runtimeType getter
    // Symbol: dart:core::Object::runtimeType#0, argCount=1 (receiver only)
    bindings.register('dart:core::Object::runtimeType#0', (args) {
      return args[0].runtimeType;
    });

    // Object.noSuchMethod
    // Symbol: dart:core::Object::noSuchMethod#1, argCount=2 (receiver + invocation)
    bindings.register('dart:core::Object::noSuchMethod#1', (args) {
      return (args[0] as Object).noSuchMethod(args[1] as Invocation);
    });

    // ── identical — top-level function ──

    // Symbol: dart:core::::identical#2, argCount=2 (no receiver)
    bindings.register('dart:core::::identical#2', (args) {
      return identical(args[0], args[1]);
    });

    // ── Type members ──

    // Type.toString()
    // Symbol: dart:core::Type::toString#0, argCount=1 (receiver only)
    bindings.register('dart:core::Type::toString#0', (args) {
      return args[0].toString();
    });

    // Type.hashCode
    bindings.register('dart:core::Type::hashCode#0', (args) {
      return args[0].hashCode;
    });

    // Type.== is handled by EQ_GENERIC opcode, not CALL_HOST
    // Null.toString() is handled by Object.toString (returns 'null')
    // Object.== is handled by EQ_GENERIC opcode
  }
}
