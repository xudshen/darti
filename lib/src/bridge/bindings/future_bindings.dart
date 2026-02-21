/// Registers `dart:async::Future` host bindings for the CALL_HOST pipeline.
///
/// Covers Future factory constructors, static methods, and instance methods.
/// Callback parameters arrive as Dart Function objects (the interpreter
/// handles DarticClosure→Function conversion via CALL_HOST dispatch).
///
/// See: docs/design/04-interop.md
library;

import 'dart:async';

import '../host_function_registry.dart';

/// Registers all `dart:async::Future` host function bindings.
abstract final class FutureBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Factory constructors ──

    // Future(FutureOr<T> Function() computation) — the primary constructor
    registry.register('dart:async::Future::#1', (args) {
      final computation = args[0] as Function;
      return Future(() => computation());
    });

    // Future.value([value]) → Future<T>
    registry.register('dart:async::Future::value#1', (args) {
      return Future.value(args[0]);
    });

    // Future.error(Object error, [StackTrace? stackTrace]) → Future<T>
    registry.register('dart:async::Future::error#2', (args) {
      final error = args[0] as Object;
      final stackTrace = args.length > 1 ? args[1] as StackTrace? : null;
      if (stackTrace != null) {
        return Future.error(error, stackTrace);
      }
      return Future.error(error);
    });

    // Future.delayed(Duration duration, [FutureOr<T> Function()? computation])
    registry.register('dart:async::Future::delayed#2', (args) {
      final duration = args[0] as Duration;
      final computation = args.length > 1 ? args[1] as Function? : null;
      if (computation != null) {
        return Future.delayed(duration, () => computation());
      }
      return Future.delayed(duration);
    });

    // Future.microtask(FutureOr<T> Function() computation)
    registry.register('dart:async::Future::microtask#1', (args) {
      final computation = args[0] as Function;
      return Future.microtask(() => computation());
    });

    // Future.sync(FutureOr<T> Function() computation)
    registry.register('dart:async::Future::sync#1', (args) {
      final computation = args[0] as Function;
      return Future.sync(() => computation());
    });

    // ── Static methods ──

    // Future.wait<T>(Iterable<Future<T>> futures, {bool eagerError, void Function(T)? cleanUp})
    registry.register('dart:async::Future::wait#3', (args) {
      final futures = (args[0] as Iterable).cast<Future>();
      final eagerError = args.length > 1 ? args[1] as bool? : null;
      final cleanUp = args.length > 2 ? args[2] as Function? : null;
      return Future.wait(
        futures.toList(),
        eagerError: eagerError ?? false,
        cleanUp: cleanUp != null ? (v) => cleanUp(v) : null,
      );
    });

    // Future.any<T>(Iterable<Future<T>> futures)
    registry.register('dart:async::Future::any#1', (args) {
      final futures = (args[0] as Iterable).cast<Future>();
      return Future.any(futures.toList());
    });

    // Future.doWhile(FutureOr<bool> Function() action)
    registry.register('dart:async::Future::doWhile#1', (args) {
      final action = args[0] as Function;
      return Future.doWhile(() => action() as FutureOr<bool>);
    });

    // Future.forEach<T>(Iterable<T> elements, FutureOr Function(T) action)
    registry.register('dart:async::Future::forEach#2', (args) {
      final elements = args[0] as Iterable;
      final action = args[1] as Function;
      return Future.forEach(elements, (e) => action(e));
    });

    // ── Instance methods ──

    // future.then<R>(FutureOr<R> Function(T) onValue, {Function? onError})
    registry.register('dart:async::Future::then#2', (args) {
      final future = args[0] as Future;
      final onValue = args[1] as Function;
      final onError = args.length > 2 ? args[2] as Function? : null;
      return future.then(
        (v) => onValue(v),
        onError: onError != null ? (e, s) => onError(e, s) : null,
      );
    });

    // future.catchError(Function onError, {bool Function(Object)? test})
    registry.register('dart:async::Future::catchError#2', (args) {
      final future = args[0] as Future;
      final onError = args[1] as Function;
      final test = args.length > 2 ? args[2] as Function? : null;
      // Pass onError directly — catchError natively dispatches to 1-arg
      // (Object) or 2-arg (Object, StackTrace) based on function arity.
      return future.catchError(
        onError,
        test: test != null ? (e) => test(e) as bool : null,
      );
    });

    // future.whenComplete(FutureOr<void> Function() action)
    registry.register('dart:async::Future::whenComplete#1', (args) {
      final future = args[0] as Future;
      final action = args[1] as Function;
      return future.whenComplete(() => action() as FutureOr<void>);
    });

    // future.asStream() → Stream<T>
    registry.register('dart:async::Future::asStream#0', (args) {
      return (args[0] as Future).asStream();
    });

    // future.ignore() → void
    registry.register('dart:async::Future::ignore#0', (args) {
      (args[0] as Future).ignore();
      return null;
    });

    // future.timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout})
    registry.register('dart:async::Future::timeout#2', (args) {
      final future = args[0] as Future;
      final timeLimit = args[1] as Duration;
      final onTimeout = args.length > 2 ? args[2] as Function? : null;
      if (onTimeout != null) {
        return future.timeout(timeLimit, onTimeout: () => onTimeout());
      }
      return future.timeout(timeLimit);
    });
  }
}
