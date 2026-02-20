/// Central registration hub for all dart:core host function bindings.
///
/// Provides `registerAll` to wire up platform bindings needed for the
/// CALL_HOST pipeline. Each type's bindings are delegated to its dedicated
/// registration class in `bindings/`.
///
/// See: docs/design/04-interop.md "基本类型传递"
library;

import 'host_bindings.dart';
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
    InvocationBindings.register(bindings);
  }

  // ── print ──
  // print stays here because it depends on the [printFn] override parameter.

  static void _registerPrint(
    HostBindings bindings,
    void Function(Object?)? printFn,
  ) {
    bindings.register('dart:core::::print#1', (args) {
      (printFn ?? print)(args[0]);
      return null;
    });
  }
}
