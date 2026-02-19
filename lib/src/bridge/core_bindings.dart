/// Registers core dart:core host function bindings for the interpreter.
///
/// Provides `registerAll` to wire up the minimal set of platform bindings
/// needed for the CALL_HOST pipeline: print, int methods, String properties.
///
/// See: docs/design/04-interop.md "基本类型传递"
library;

import 'host_bindings.dart';
import 'wrappers/bool_wrapper.dart';
import 'wrappers/double_wrapper.dart';
import 'wrappers/duration_wrapper.dart';
import 'wrappers/error_wrappers.dart';
import 'wrappers/int_wrapper.dart';
import 'wrappers/iterable_wrapper.dart';
import 'wrappers/list_wrapper.dart';
import 'wrappers/map_wrapper.dart';
import 'wrappers/num_wrapper.dart';
import 'wrappers/object_wrapper.dart';
import 'wrappers/set_wrapper.dart';
import 'wrappers/string_wrapper.dart';

/// Registers all dart:core host function bindings into [bindings].
///
/// [printFn] overrides the default print behavior (useful for testing
/// to capture output instead of writing to stdout).
abstract final class CoreBindings {
  static void registerAll(
    HostBindings bindings, {
    void Function(Object?)? printFn,
  }) {
    _registerPrint(bindings, printFn);
    _registerIntBindings(bindings);
    _registerStringBindings(bindings);
    _registerObjectBindings(bindings);
    ObjectBindings.register(bindings);
    IntBindings.register(bindings);
    DoubleBindings.register(bindings);
    NumBindings.register(bindings);
    BoolBindings.register(bindings);
    StringBindings.register(bindings);
    ListBindings.register(bindings);
    IterableBindings.register(bindings);
    MapBindings.register(bindings);
    SetBindings.register(bindings);
    DurationBindings.register(bindings);
    ErrorBindings.register(bindings);
  }

  // ── print ──

  static void _registerPrint(
    HostBindings bindings,
    void Function(Object?)? printFn,
  ) {
    bindings.register('dart:core::::print#1', (args) {
      (printFn ?? print)(args[0]);
      return null;
    });
  }

  // ── int methods ──

  static void _registerIntBindings(HostBindings bindings) {
    // int.toString() — receiver is args[0]
    bindings.register('dart:core::int::toString#0', (args) {
      return (args[0] as int).toString();
    });
  }

  // ── String properties/methods ──

  static void _registerStringBindings(HostBindings bindings) {
    // String.length getter — receiver is args[0]
    bindings.register('dart:core::String::length#0', (args) {
      return (args[0] as String).length;
    });
  }

  // ── Object methods ──

  static void _registerObjectBindings(HostBindings bindings) {
    // Object.toString() — fallback for any object
    bindings.register('dart:core::Object::toString#0', (args) {
      return args[0].toString();
    });

    // Object.hashCode getter
    bindings.register('dart:core::Object::hashCode#0', (args) {
      return args[0].hashCode;
    });

    // Object() constructor — creates a plain Dart Object
    bindings.register('dart:core::Object::#0', (args) {
      return Object();
    });
  }
}
