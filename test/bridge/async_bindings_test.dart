import 'dart:async';

import 'package:dartic/src/bridge/async_bindings.dart';
import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  late HostFunctionRegistry registry;

  setUp(() {
    registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
    AsyncBindings.registerAll(registry);
  });

  // ── Helper to invoke a binding by symbolic name ──
  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  // ══════════════════════════════════════════════════════════════════
  // Future bindings — registration
  // ══════════════════════════════════════════════════════════════════

  group('FutureBindings registration', () {
    test('Future factory constructors are registered', () {
      expect(registry.lookupByName('dart:async::Future::value#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::error#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::delayed#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::microtask#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::sync#1'),
          isNot(equals(-1)));
    });

    test('Future static methods are registered', () {
      expect(registry.lookupByName('dart:async::Future::wait#3'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::any#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::doWhile#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::forEach#2'),
          isNot(equals(-1)));
    });

    test('Future instance methods are registered', () {
      expect(registry.lookupByName('dart:async::Future::then#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::catchError#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::whenComplete#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Future::timeout#2'),
          isNot(equals(-1)));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Future bindings — invoke
  // ══════════════════════════════════════════════════════════════════

  group('FutureBindings invoke', () {
    test('Future.value(42) creates completed Future', () async {
      final f = invoke('dart:async::Future::value#1', [42]) as Future;
      expect(await f, 42);
    });

    test('Future.error creates error Future', () async {
      final f =
          invoke('dart:async::Future::error#2', ['oops', null]) as Future;
      expect(f, throwsA('oops'));
    });

    test('Future.delayed creates delayed Future', () async {
      final f = invoke('dart:async::Future::delayed#2',
          [Duration.zero, () => 99]) as Future;
      expect(await f, 99);
    });

    test('Future.microtask creates microtask Future', () async {
      final f =
          invoke('dart:async::Future::microtask#1', [() => 77]) as Future;
      expect(await f, 77);
    });

    test('Future.sync wraps computation', () async {
      final f =
          invoke('dart:async::Future::sync#1', [() => 42]) as Future;
      expect(await f, 42);
    });

    test('Future.wait waits for all futures', () async {
      final f1 = Future.value(1);
      final f2 = Future.value(2);
      final result = invoke('dart:async::Future::wait#3',
          [[f1, f2], null, null]) as Future;
      expect(await result, [1, 2]);
    });

    test('Future.any returns first completed', () async {
      final f1 = Future.value(42);
      final result =
          invoke('dart:async::Future::any#1', [[f1]]) as Future;
      expect(await result, 42);
    });

    test('Future.doWhile repeats until false', () async {
      var count = 0;
      final result = invoke('dart:async::Future::doWhile#1', [
        () {
          count++;
          return count < 3;
        }
      ]) as Future;
      await result;
      expect(count, 3);
    });

    test('Future.forEach iterates elements', () async {
      final collected = <int>[];
      final result = invoke('dart:async::Future::forEach#2', [
        [1, 2, 3],
        (int e) => collected.add(e),
      ]) as Future;
      await result;
      expect(collected, [1, 2, 3]);
    });

    test('future.then chains value', () async {
      final f = Future.value(10);
      final chained = invoke('dart:async::Future::then#2',
          [f, (v) => (v as int) * 2, null]) as Future;
      expect(await chained, 20);
    });

    test('future.catchError handles error', () async {
      final f = Future.error('bad');
      final caught = invoke('dart:async::Future::catchError#2',
          [f, (e) => 'recovered', null]) as Future;
      expect(await caught, 'recovered');
    });

    test('future.whenComplete runs action', () async {
      var completed = false;
      final f = Future.value(42);
      final result = invoke('dart:async::Future::whenComplete#1',
          [f, () => completed = true]) as Future;
      expect(await result, 42);
      expect(completed, true);
    });

    test('future.timeout with no timeout returns value', () async {
      final f = Future.value(42);
      final result = invoke('dart:async::Future::timeout#2',
          [f, const Duration(seconds: 5), null]) as Future;
      expect(await result, 42);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Completer bindings
  // ══════════════════════════════════════════════════════════════════

  group('CompleterBindings registration', () {
    test('Completer bindings are registered', () {
      expect(registry.lookupByName('dart:async::Completer::#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Completer::complete#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Completer::future#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Completer::isCompleted#0'),
          isNot(equals(-1)));
    });
  });

  group('CompleterBindings invoke', () {
    test('Completer constructor + complete + future', () async {
      final c = invoke('dart:async::Completer::#0', []);
      expect(c, isA<Completer>());

      final future = invoke('dart:async::Completer::future#0', [c]) as Future;
      expect(invoke('dart:async::Completer::isCompleted#0', [c]), false);

      invoke('dart:async::Completer::complete#1', [c, 42]);
      expect(await future, 42);
      expect(invoke('dart:async::Completer::isCompleted#0', [c]), true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // StreamController bindings
  // ══════════════════════════════════════════════════════════════════

  group('StreamControllerBindings registration', () {
    test('StreamController bindings are registered', () {
      expect(registry.lookupByName('dart:async::StreamController::#5'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::StreamController::add#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::StreamController::close#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::StreamController::stream#0'),
          isNot(equals(-1)));
    });
  });

  group('StreamControllerBindings invoke', () {
    test('StreamController constructor + add + close + stream', () async {
      final sc = invoke('dart:async::StreamController::#5',
          [null, null, null, null, null]);
      expect(sc, isA<StreamController>());

      final stream =
          invoke('dart:async::StreamController::stream#0', [sc]) as Stream;
      final collected = <int>[];
      stream.listen((e) => collected.add(e as int));

      invoke('dart:async::StreamController::add#1', [sc, 1]);
      invoke('dart:async::StreamController::add#1', [sc, 2]);
      invoke('dart:async::StreamController::close#0', [sc]);

      // Wait for stream to process events.
      await (sc as StreamController).done;
      expect(collected, [1, 2]);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Stream bindings
  // ══════════════════════════════════════════════════════════════════

  group('StreamBindings registration', () {
    test('Stream bindings are registered', () {
      expect(registry.lookupByName('dart:async::Stream::fromIterable#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Stream::listen#4'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Stream::toList#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Stream::map#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Stream::where#1'),
          isNot(equals(-1)));
    });
  });

  group('StreamBindings invoke', () {
    test('Stream.fromIterable creates stream', () async {
      final s =
          invoke('dart:async::Stream::fromIterable#1', [[1, 2, 3]]) as Stream;
      final result =
          invoke('dart:async::Stream::toList#0', [s]) as Future;
      expect(await result, [1, 2, 3]);
    });

    test('Stream.map transforms elements', () async {
      final s = Stream.fromIterable([1, 2, 3]);
      final mapped =
          invoke('dart:async::Stream::map#1', [s, (e) => (e as int) * 10])
              as Stream;
      final result =
          invoke('dart:async::Stream::toList#0', [mapped]) as Future;
      expect(await result, [10, 20, 30]);
    });

    test('Stream.where filters elements', () async {
      final s = Stream.fromIterable([1, 2, 3, 4]);
      final filtered = invoke(
              'dart:async::Stream::where#1', [s, (e) => (e as int) > 2])
          as Stream;
      final result =
          invoke('dart:async::Stream::toList#0', [filtered]) as Future;
      expect(await result, [3, 4]);
    });

    test('Stream.listen receives events', () async {
      final s = Stream.fromIterable([10, 20]);
      final collected = <int>[];
      invoke('dart:async::Stream::listen#4',
          [s, (e) => collected.add(e as int), null, null, null]);
      // Give time for microtasks to execute.
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(collected, [10, 20]);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Timer bindings
  // ══════════════════════════════════════════════════════════════════

  group('TimerBindings registration', () {
    test('Timer bindings are registered', () {
      expect(registry.lookupByName('dart:async::Timer::#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Timer::run#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Timer::periodic#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Timer::cancel#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Timer::isActive#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::Timer::tick#0'),
          isNot(equals(-1)));
    });
  });

  group('TimerBindings invoke', () {
    test('Timer.run fires zero-delay callback', () async {
      var fired = false;
      invoke('dart:async::Timer::run#1', [() => fired = true]);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      expect(fired, true);
    });

    test('Timer constructor creates timer, cancel stops it', () async {
      var fired = false;
      final t = invoke('dart:async::Timer::#2',
          [const Duration(milliseconds: 50), () => fired = true]) as Timer;
      expect(invoke('dart:async::Timer::isActive#0', [t]), true);
      invoke('dart:async::Timer::cancel#0', [t]);
      expect(invoke('dart:async::Timer::isActive#0', [t]), false);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(fired, false);
    });

    test('Timer.periodic fires repeatedly', () async {
      var count = 0;
      final t = invoke('dart:async::Timer::periodic#2',
              [const Duration(milliseconds: 10), (Timer t) => count++])
          as Timer;
      await Future.delayed(const Duration(milliseconds: 60));
      invoke('dart:async::Timer::cancel#0', [t]);
      expect(count, greaterThan(0));
      expect(invoke('dart:async::Timer::tick#0', [t]) as int, greaterThan(0));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Zone / scheduleMicrotask bindings
  // ══════════════════════════════════════════════════════════════════

  group('ZoneBindings registration', () {
    test('Zone bindings are registered', () {
      expect(registry.lookupByName('dart:async::Zone::current#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:async::::scheduleMicrotask#1'),
          isNot(equals(-1)));
    });
  });

  group('ZoneBindings invoke', () {
    test('Zone.current returns a Zone', () {
      final zone = invoke('dart:async::Zone::current#0', []);
      expect(zone, isA<Zone>());
    });

    test('scheduleMicrotask runs callback', () async {
      var ran = false;
      invoke('dart:async::::scheduleMicrotask#1', [() => ran = true]);
      await Future.delayed(Duration.zero);
      expect(ran, true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Future.asStream / Future.ignore
  // ══════════════════════════════════════════════════════════════════

  group('FutureBindings asStream/ignore', () {
    test('Future.asStream is registered', () {
      expect(registry.lookupByName('dart:async::Future::asStream#0'),
          isNot(equals(-1)));
    });

    test('future.asStream() returns single-element stream', () async {
      final f = Future.value(42);
      final stream =
          invoke('dart:async::Future::asStream#0', [f]) as Stream;
      final result = await stream.toList();
      expect(result, [42]);
    });

    test('Future.ignore is registered', () {
      expect(registry.lookupByName('dart:async::Future::ignore#0'),
          isNot(equals(-1)));
    });

    test('future.ignore() returns void and suppresses error', () async {
      final f = Future.error('ignored');
      // ignore() should not throw — it swallows errors
      invoke('dart:async::Future::ignore#0', [f]);
      // Give time for microtasks to settle
      await Future.delayed(Duration.zero);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Completer.sync
  // ══════════════════════════════════════════════════════════════════

  group('CompleterBindings sync', () {
    test('Completer.sync is registered', () {
      expect(registry.lookupByName('dart:async::Completer::sync#0'),
          isNot(equals(-1)));
    });

    test('Completer.sync() creates synchronous completer', () async {
      final c = invoke('dart:async::Completer::sync#0', []);
      expect(c, isA<Completer>());

      final future = invoke('dart:async::Completer::future#0', [c]) as Future;
      invoke('dart:async::Completer::complete#1', [c, 99]);
      expect(await future, 99);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Zone.bindBinaryCallback / Zone.handleUncaughtError
  // ══════════════════════════════════════════════════════════════════

  group('ZoneBindings bindBinaryCallback/handleUncaughtError', () {
    test('Zone.bindBinaryCallback is registered', () {
      expect(
          registry.lookupByName('dart:async::Zone::bindBinaryCallback#1'),
          isNot(equals(-1)));
    });

    test('zone.bindBinaryCallback wraps callback in zone', () {
      final zone = Zone.current;
      final cb = invoke('dart:async::Zone::bindBinaryCallback#1',
          [zone, (a, b) => (a as int) + (b as int)]) as Function;
      expect(cb(3, 4), 7);
    });

    test('Zone.handleUncaughtError is registered', () {
      expect(
          registry.lookupByName('dart:async::Zone::handleUncaughtError#2'),
          isNot(equals(-1)));
    });

    test('zone.handleUncaughtError forwards to zone', () {
      // Create a zone that captures errors
      Object? capturedError;
      final zone = Zone.current.fork(
        specification: ZoneSpecification(
          handleUncaughtError: (self, parent, zone, error, stackTrace) {
            capturedError = error;
          },
        ),
      );
      invoke('dart:async::Zone::handleUncaughtError#2',
          [zone, 'test-error', StackTrace.current]);
      expect(capturedError, 'test-error');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Zone.fork full params / ZoneSpecification / Zone.[]
  // ══════════════════════════════════════════════════════════════════

  group('ZoneBindings fork/ZoneSpecification/operator[]', () {
    test('Zone.fork with zoneValues stores values', () {
      final zone = Zone.current;
      final forked = invoke('dart:async::Zone::fork#2', [
        zone,
        null, // specification
        {'myKey': 42},
      ]) as Zone;
      expect(forked, isA<Zone>());
      // zone[key] access
      expect(invoke('dart:async::Zone::[]#1', [forked, 'myKey']), 42);
    });

    test('Zone.[] is registered', () {
      expect(registry.lookupByName('dart:async::Zone::[]#1'),
          isNot(equals(-1)));
    });

    test('Zone.fork with ZoneSpecification (handleUncaughtError)', () {
      Object? capturedError;
      final spec = ZoneSpecification(
        handleUncaughtError: (self, parent, zone, error, stackTrace) {
          capturedError = error;
        },
      );
      final forked = invoke('dart:async::Zone::fork#2', [
        Zone.current,
        spec,
        null,
      ]) as Zone;
      forked.handleUncaughtError('zone-err', StackTrace.current);
      expect(capturedError, 'zone-err');
    });

    test('Zone.fork with both specification and zoneValues', () {
      Object? capturedError;
      final spec = ZoneSpecification(
        handleUncaughtError: (self, parent, zone, error, stackTrace) {
          capturedError = error;
        },
      );
      final forked = invoke('dart:async::Zone::fork#2', [
        Zone.current,
        spec,
        {'key': 'val'},
      ]) as Zone;
      expect(invoke('dart:async::Zone::[]#1', [forked, 'key']), 'val');
      forked.handleUncaughtError('err2', StackTrace.current);
      expect(capturedError, 'err2');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // End-to-end compile+run tests
  // ══════════════════════════════════════════════════════════════════

  group('AsyncBindings e2e', () {
    Future<(Object?, List<String>)> runAsyncWithHost(String source,
        {int? fuelBudget}) async {
      final printLog = <String>[];
      final module = await compileDart(source);
      final reg = HostFunctionRegistry();
      CoreBindings.registerAll(reg, printFn: (v) => printLog.add('$v'));
      AsyncBindings.registerAll(reg);
      final interp = DarticInterpreter(
        hostFunctionRegistry: reg,
        fuelBudget: fuelBudget ?? DarticInterpreter.defaultFuelBudget,
      );
      interp.execute(module);
      final result = interp.entryResult;
      if (result is Future) {
        await result;
      }
      return (result, printLog);
    }

    test('Completer<int> usage', () async {
      final (_, prints) = await runAsyncWithHost('''
import 'dart:async';

Future<void> main() async {
  var c = Completer<int>();
  c.complete(42);
  var v = await c.future;
  print(v);
}
''');
      expect(prints, ['42']);
    });

    test('Future.value usage', () async {
      final (_, prints) = await runAsyncWithHost('''
import 'dart:async';

Future<void> main() async {
  var f = Future.value(99);
  var v = await f;
  print(v);
}
''');
      expect(prints, ['99']);
    });

    test('Stream.fromIterable + toList', () async {
      final (_, prints) = await runAsyncWithHost('''
import 'dart:async';

Future<void> main() async {
  var s = Stream.fromIterable([1, 2, 3]);
  var list = await s.toList();
  print(list);
}
''');
      expect(prints, ['[1, 2, 3]']);
    });

    test('Completer.sync compile+run', () async {
      final (_, prints) = await runAsyncWithHost('''
import 'dart:async';

Future<void> main() async {
  var c = Completer<int>.sync();
  c.complete(77);
  var v = await c.future;
  print(v);
}
''');
      expect(prints, ['77']);
    });

    test('future.asStream().toList()', () async {
      final (_, prints) = await runAsyncWithHost('''
import 'dart:async';

Future<void> main() async {
  var f = Future.value(42);
  var list = await f.asStream().toList();
  print(list);
}
''');
      expect(prints, ['[42]']);
    });
  });
}
