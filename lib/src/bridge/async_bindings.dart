/// Central registration hub for all dart:async host function bindings.
///
/// Provides `registerAll` to wire up async platform bindings needed for the
/// CALL_HOST pipeline. Each type's bindings are delegated to its dedicated
/// registration class in `bindings/`.
///
/// See: docs/design/04-interop.md
library;

import 'bindings/completer_bindings.dart';
import 'bindings/future_bindings.dart';
import 'bindings/stream_bindings.dart';
import 'bindings/timer_bindings.dart';
import 'bindings/zone_bindings.dart';
import 'host_function_registry.dart';

/// Registers all dart:async host function bindings into [registry].
abstract final class AsyncBindings {
  static void registerAll(HostFunctionRegistry registry) {
    FutureBindings.register(registry);
    CompleterBindings.register(registry);
    StreamBindings.register(registry);
    TimerBindings.register(registry);
    ZoneBindings.register(registry);
  }
}
