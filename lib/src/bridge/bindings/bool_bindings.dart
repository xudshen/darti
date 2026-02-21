/// Registers `bool` host bindings for the CALL_HOST pipeline.
///
/// Covers bool instance methods, getters, and operators.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::bool` host function bindings.
abstract final class BoolBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Instance methods ──

    // bool.toString()
    registry.register('dart:core::bool::toString#0', (args) {
      return (args[0] as bool).toString();
    });

    // ── Instance getters ──

    // bool.hashCode getter
    registry.register('dart:core::bool::hashCode#0', (args) {
      return (args[0] as bool).hashCode;
    });

    // ── Operators ──
    // Needed when receiver is dynamic-typed and INVOKE_DYN is emitted
    // instead of specialized bool opcodes.

    registry.register('dart:core::bool::&#1', (args) {
      return (args[0] as bool) & (args[1] as bool);
    });
    registry.register('dart:core::bool::|#1', (args) {
      return (args[0] as bool) | (args[1] as bool);
    });
    registry.register('dart:core::bool::^#1', (args) {
      return (args[0] as bool) ^ (args[1] as bool);
    });
  }
}
