/// Central registration hub for all dart:core host function bindings.
///
/// Provides `registerAll` to wire up platform bindings needed for the
/// CALL_HOST pipeline. Each type's bindings are delegated to its dedicated
/// wrapper class in `wrappers/`.
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
