/// Registers `bool` host registry for the CALL_HOST pipeline.
///
/// Covers bool instance methods and getters. Boolean arithmetic and
/// comparison operators use specialized opcodes and are NOT handled here.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::bool` host function registry.
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
  }
}
