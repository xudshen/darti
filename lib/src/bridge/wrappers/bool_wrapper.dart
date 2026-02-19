/// Registers `bool` host bindings for the CALL_HOST pipeline.
///
/// Covers bool instance methods and getters. Boolean arithmetic and
/// comparison operators use specialized opcodes and are NOT handled here.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::bool` host function bindings.
abstract final class BoolBindings {
  static void register(HostBindings bindings) {
    // ── Instance methods ──

    // bool.toString()
    bindings.register('dart:core::bool::toString#0', (args) {
      return (args[0] as bool).toString();
    });

    // ── Instance getters ──

    // bool.hashCode getter
    bindings.register('dart:core::bool::hashCode#0', (args) {
      return (args[0] as bool).hashCode;
    });
  }
}
