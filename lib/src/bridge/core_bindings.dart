/// Central registration hub for all dart:core host function registry.
///
/// Provides `registerAll` to wire up platform registry needed for the
/// CALL_HOST pipeline. Each type's registry are delegated to its dedicated
/// registration class in `registry/`.
///
/// See: docs/design/04-interop.md "基本类型传递"
library;

import 'host_function_registry.dart';
import 'bindings/bool_bindings.dart';
import 'bindings/double_bindings.dart';
import 'bindings/duration_bindings.dart';
import 'bindings/error_bindings.dart';
import 'bindings/int_bindings.dart';
import 'bindings/invocation_bindings.dart';
import 'bindings/iterable_bindings.dart';
import 'bindings/list_bindings.dart';
import 'bindings/map_bindings.dart';
import 'bindings/num_bindings.dart';
import 'bindings/object_bindings.dart';
import 'bindings/set_bindings.dart';
import 'bindings/string_bindings.dart';

/// Registers all dart:core host function registry into [registry].
///
/// [printFn] overrides the default print behavior (useful for testing
/// to capture output instead of writing to stdout).
abstract final class CoreBindings {
  static void registerAll(
    HostFunctionRegistry registry, {
    void Function(Object?)? printFn,
  }) {
    _registerPrint(registry, printFn);
    ObjectBindings.register(registry);
    IntBindings.register(registry);
    DoubleBindings.register(registry);
    NumBindings.register(registry);
    BoolBindings.register(registry);
    StringBindings.register(registry);
    ListBindings.register(registry);
    IterableBindings.register(registry);
    MapBindings.register(registry);
    SetBindings.register(registry);
    DurationBindings.register(registry);
    ErrorBindings.register(registry);
    InvocationBindings.register(registry);
  }

  // ── print ──
  // print stays here because it depends on the [printFn] override parameter.

  static void _registerPrint(
    HostFunctionRegistry registry,
    void Function(Object?)? printFn,
  ) {
    registry.register('dart:core::::print#1', (args) {
      (printFn ?? print)(args[0]);
      return null;
    });
  }
}
