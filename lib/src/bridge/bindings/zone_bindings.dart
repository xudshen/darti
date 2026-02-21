/// Registers `dart:async::Zone` and top-level dart:async function bindings
/// for the CALL_HOST pipeline.
///
/// Covers Zone.current static getter and scheduleMicrotask top-level function.
///
/// See: docs/design/04-interop.md
library;

import 'dart:async';

import '../host_function_registry.dart';

/// Registers Zone and top-level dart:async function bindings.
abstract final class ZoneBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Zone static getters ──

    // Zone.current → Zone
    registry.register('dart:async::Zone::current#0', (args) {
      return Zone.current;
    });

    // Zone.root → Zone
    registry.register('dart:async::Zone::root#0', (args) {
      return Zone.root;
    });

    // ── Zone instance methods ──

    // zone.run<R>(R Function() body) → R
    registry.register('dart:async::Zone::run#1', (args) {
      final zone = args[0] as Zone;
      final body = args[1] as Function;
      return zone.run(() => body());
    });

    // zone.runGuarded(void Function() body)
    registry.register('dart:async::Zone::runGuarded#1', (args) {
      final zone = args[0] as Zone;
      final body = args[1] as Function;
      zone.runGuarded(() => body());
      return null;
    });

    // zone.runUnary<R, T>(R Function(T) body, T argument) → R
    registry.register('dart:async::Zone::runUnary#2', (args) {
      final zone = args[0] as Zone;
      final body = args[1] as Function;
      return zone.runUnary((a) => body(a), args[2]);
    });

    // zone.runBinary<R, T1, T2>(R Function(T1, T2) body, T1 a1, T2 a2) → R
    registry.register('dart:async::Zone::runBinary#3', (args) {
      final zone = args[0] as Zone;
      final body = args[1] as Function;
      return zone.runBinary((a, b) => body(a, b), args[2], args[3]);
    });

    // zone.bindCallback<R>(R Function() body) → ZoneCallback<R>
    registry.register('dart:async::Zone::bindCallback#1', (args) {
      final zone = args[0] as Zone;
      final body = args[1] as Function;
      return zone.bindCallback(() => body());
    });

    // zone.bindUnaryCallback<R, T>(R Function(T) body) → ZoneUnaryCallback<R, T>
    registry.register('dart:async::Zone::bindUnaryCallback#1', (args) {
      final zone = args[0] as Zone;
      final body = args[1] as Function;
      return zone.bindUnaryCallback((a) => body(a));
    });

    // zone.bindBinaryCallback<R, T1, T2>(R Function(T1, T2) body) → ZoneBinaryCallback<R, T1, T2>
    registry.register('dart:async::Zone::bindBinaryCallback#1', (args) {
      final zone = args[0] as Zone;
      final body = args[1] as Function;
      return zone.bindBinaryCallback((a, b) => body(a, b));
    });

    // zone.handleUncaughtError(Object error, StackTrace stackTrace)
    registry.register('dart:async::Zone::handleUncaughtError#2', (args) {
      final zone = args[0] as Zone;
      zone.handleUncaughtError(args[1] as Object, args[2] as StackTrace);
      return null;
    });

    // zone.fork({ZoneSpecification? specification, Map? zoneValues}) → Zone
    registry.register('dart:async::Zone::fork#2', (args) {
      final zone = args[0] as Zone;
      final spec = args.length > 1 ? args[1] as ZoneSpecification? : null;
      final zoneValues = args.length > 2 ? args[2] as Map? : null;
      return zone.fork(
        specification: spec,
        zoneValues: zoneValues != null
            ? Map<Object?, Object?>.from(zoneValues)
            : null,
      );
    });

    // zone[key] → value (zone values accessor)
    registry.register('dart:async::Zone::[]#1', (args) {
      final zone = args[0] as Zone;
      return zone[args[1]];
    });

    // ── ZoneSpecification constructor ──
    // ZoneSpecification({handleUncaughtError, forceHandleUncaughtError,
    //   run, runUnary, runBinary, registerCallback, registerUnaryCallback,
    //   registerBinaryCallback, errorCallback, scheduleMicrotask,
    //   createTimer, createPeriodicTimer, print})
    // CFE emits all 13 named params as positional args.
    registry.register('dart:async::ZoneSpecification::#13', (args) {
      final handleUncaughtError = args.isNotEmpty ? args[0] as Function? : null;
      // args[1] = forceHandleUncaughtError (unused)
      // args[2..8] = run, runUnary, runBinary, registerCallback,
      //              registerUnaryCallback, registerBinaryCallback, errorCallback
      // args[9] = scheduleMicrotask
      // args[10] = createTimer
      // args[11] = createPeriodicTimer
      final printFn = args.length > 12 ? args[12] as Function? : null;

      return ZoneSpecification(
        handleUncaughtError: handleUncaughtError != null
            ? (self, parent, zone, error, stackTrace) =>
                handleUncaughtError(self, parent, zone, error, stackTrace)
            : null,
        print: printFn != null
            ? (self, parent, zone, line) => printFn(self, parent, zone, line)
            : null,
      );
    });

    // ── Top-level functions ──

    // scheduleMicrotask(void Function() callback)
    registry.register('dart:async::::scheduleMicrotask#1', (args) {
      final callback = args[0] as Function;
      scheduleMicrotask(() => callback());
      return null;
    });
  }
}
