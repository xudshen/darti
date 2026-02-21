/// Central registration hub for all dart:collection host function bindings.
///
/// See: docs/design/04-interop.md
library;

import 'bindings/collection_bindings.dart';
import 'host_function_registry.dart';

/// Registers all dart:collection host function bindings into [registry].
abstract final class CollectionBindingsHub {
  static void registerAll(HostFunctionRegistry registry) {
    CollectionBindings.register(registry);
  }
}
