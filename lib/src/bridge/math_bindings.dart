/// Central registration hub for all dart:math host function bindings.
///
/// See: docs/design/04-interop.md
library;

import 'bindings/math_bindings.dart';
import 'host_function_registry.dart';

/// Registers all dart:math host function bindings into [registry].
abstract final class MathBindingsHub {
  static void registerAll(HostFunctionRegistry registry) {
    MathBindings.register(registry);
  }
}
