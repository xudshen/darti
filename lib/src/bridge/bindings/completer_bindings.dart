/// Registers `dart:async::Completer` host bindings for the CALL_HOST pipeline.
///
/// Covers Completer constructor, complete/completeError methods, and getters.
///
/// See: docs/design/04-interop.md
library;

import 'dart:async';

import '../host_function_registry.dart';

/// Registers all `dart:async::Completer` host function bindings.
abstract final class CompleterBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Constructor ──

    // Completer<T>() → Completer<T>
    registry.register('dart:async::Completer::#0', (args) {
      return Completer<Object?>();
    });

    // Completer<T>.sync() → Completer<T>
    registry.register('dart:async::Completer::sync#0', (args) {
      return Completer<Object?>.sync();
    });

    // ── Instance methods ──

    // completer.complete([FutureOr<T>? value])
    registry.register('dart:async::Completer::complete#1', (args) {
      final completer = args[0] as Completer;
      final value = args.length > 1 ? args[1] : null;
      completer.complete(value);
      return null;
    });

    // completer.completeError(Object error, [StackTrace? stackTrace])
    registry.register('dart:async::Completer::completeError#2', (args) {
      final completer = args[0] as Completer;
      final error = args[1] as Object;
      final stackTrace = args.length > 2 ? args[2] as StackTrace? : null;
      if (stackTrace != null) {
        completer.completeError(error, stackTrace);
      } else {
        completer.completeError(error);
      }
      return null;
    });

    // ── Getters ──

    // completer.future → Future<T>
    registry.register('dart:async::Completer::future#0', (args) {
      return (args[0] as Completer).future;
    });

    // completer.isCompleted → bool
    registry.register('dart:async::Completer::isCompleted#0', (args) {
      return (args[0] as Completer).isCompleted;
    });
  }
}
