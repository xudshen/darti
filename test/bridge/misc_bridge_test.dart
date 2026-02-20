import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  late HostFunctionRegistry registry;

  setUp(() {
    registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
  });

  // ── Helper to invoke a binding by symbolic name ──
  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  // ══════════════════════════════════════════════════════════════════
  // Stopwatch
  // ══════════════════════════════════════════════════════════════════

  group('StopwatchBindings registration', () {
    test('Stopwatch bindings are registered', () {
      expect(registry.lookupByName('dart:core::Stopwatch::#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Stopwatch::isRunning#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Stopwatch::start#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Stopwatch::stop#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Stopwatch::reset#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Stopwatch::elapsed#0'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::Stopwatch::elapsedMilliseconds#0'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::Stopwatch::elapsedMicroseconds#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Stopwatch::elapsedTicks#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Stopwatch::frequency#0'),
          isNot(equals(-1)));
    });
  });

  group('StopwatchBindings invoke', () {
    test('constructor returns Stopwatch with isRunning false', () {
      final sw = invoke('dart:core::Stopwatch::#0', []);
      expect(sw, isA<Stopwatch>());
      expect(invoke('dart:core::Stopwatch::isRunning#0', [sw]), false);
    });

    test('start → isRunning true → stop → elapsed >= 0 → reset → elapsed 0',
        () {
      final sw = invoke('dart:core::Stopwatch::#0', []) as Stopwatch;
      invoke('dart:core::Stopwatch::start#0', [sw]);
      expect(invoke('dart:core::Stopwatch::isRunning#0', [sw]), true);
      invoke('dart:core::Stopwatch::stop#0', [sw]);
      expect(invoke('dart:core::Stopwatch::isRunning#0', [sw]), false);
      expect(
          invoke('dart:core::Stopwatch::elapsedMilliseconds#0', [sw]) as int,
          greaterThanOrEqualTo(0));
      invoke('dart:core::Stopwatch::reset#0', [sw]);
      expect(
          invoke('dart:core::Stopwatch::elapsedMilliseconds#0', [sw]) as int,
          equals(0));
    });

    test('frequency returns positive int', () {
      final sw = invoke('dart:core::Stopwatch::#0', []) as Stopwatch;
      expect(invoke('dart:core::Stopwatch::frequency#0', [sw]) as int,
          greaterThan(0));
    });

    test('elapsed returns Duration', () {
      final sw = invoke('dart:core::Stopwatch::#0', []) as Stopwatch;
      expect(invoke('dart:core::Stopwatch::elapsed#0', [sw]), isA<Duration>());
    });

    test('elapsedMicroseconds returns int', () {
      final sw = invoke('dart:core::Stopwatch::#0', []) as Stopwatch;
      expect(invoke('dart:core::Stopwatch::elapsedMicroseconds#0', [sw]),
          isA<int>());
    });

    test('elapsedTicks returns int', () {
      final sw = invoke('dart:core::Stopwatch::#0', []) as Stopwatch;
      expect(
          invoke('dart:core::Stopwatch::elapsedTicks#0', [sw]), isA<int>());
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // StackTrace
  // ══════════════════════════════════════════════════════════════════

  group('StackTraceBindings registration', () {
    test('StackTrace bindings are registered', () {
      expect(registry.lookupByName('dart:core::StackTrace::current#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StackTrace::toString#0'),
          isNot(equals(-1)));
    });
  });

  group('StackTraceBindings invoke', () {
    test('StackTrace.current returns non-null StackTrace', () {
      final st = invoke('dart:core::StackTrace::current#0', []);
      expect(st, isA<StackTrace>());
      expect(st, isNotNull);
    });

    test('StackTrace.toString returns non-empty string', () {
      final st =
          invoke('dart:core::StackTrace::current#0', []) as StackTrace;
      final str = invoke('dart:core::StackTrace::toString#0', [st]) as String;
      expect(str, isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Symbol
  // ══════════════════════════════════════════════════════════════════

  group('SymbolBindings registration', () {
    test('Symbol bindings are registered', () {
      expect(registry.lookupByName('dart:core::Symbol::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Symbol::hashCode#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Symbol::==#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Symbol::toString#0'),
          isNot(equals(-1)));
    });
  });

  group('SymbolBindings invoke', () {
    test('Symbol constructor creates Symbol', () {
      final sym = invoke('dart:core::Symbol::#1', ['foo']);
      expect(sym, isA<Symbol>());
    });

    test('two Symbol("foo") are == via operator==', () {
      final sym1 = invoke('dart:core::Symbol::#1', ['foo']);
      final sym2 = invoke('dart:core::Symbol::#1', ['foo']);
      expect(invoke('dart:core::Symbol::==#1', [sym1, sym2]), true);
    });

    test('hashCode matches for equal symbols', () {
      final sym1 = invoke('dart:core::Symbol::#1', ['bar']);
      final sym2 = invoke('dart:core::Symbol::#1', ['bar']);
      final h1 = invoke('dart:core::Symbol::hashCode#0', [sym1]) as int;
      final h2 = invoke('dart:core::Symbol::hashCode#0', [sym2]) as int;
      expect(h1, equals(h2));
    });

    test('toString returns representation', () {
      final sym = invoke('dart:core::Symbol::#1', ['test']);
      final str = invoke('dart:core::Symbol::toString#0', [sym]) as String;
      expect(str, contains('test'));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Expando
  // ══════════════════════════════════════════════════════════════════

  group('ExpandoBindings registration', () {
    test('Expando bindings are registered', () {
      expect(registry.lookupByName('dart:core::Expando::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Expando::name#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Expando::[]#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Expando::[]=#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Expando::toString#0'),
          isNot(equals(-1)));
    });
  });

  group('ExpandoBindings invoke', () {
    test('Expando constructor with name', () {
      final expando = invoke('dart:core::Expando::#1', ['test']);
      expect(expando, isA<Expando>());
      expect(invoke('dart:core::Expando::name#0', [expando]), 'test');
    });

    test('Expando constructor without name', () {
      final expando = invoke('dart:core::Expando::#1', [null]);
      expect(expando, isA<Expando>());
      expect(invoke('dart:core::Expando::name#0', [expando]), isNull);
    });

    test('Expando []= and [] operators', () {
      final expando =
          invoke('dart:core::Expando::#1', ['store']) as Expando;
      final obj = Object();
      invoke('dart:core::Expando::[]=#2', [expando, obj, 42]);
      expect(invoke('dart:core::Expando::[]#1', [expando, obj]), 42);
    });

    test('Expando stores per-object independently', () {
      final expando =
          invoke('dart:core::Expando::#1', ['multi']) as Expando;
      final obj1 = Object();
      final obj2 = Object();
      invoke('dart:core::Expando::[]=#2', [expando, obj1, 'a']);
      invoke('dart:core::Expando::[]=#2', [expando, obj2, 'b']);
      expect(invoke('dart:core::Expando::[]#1', [expando, obj1]), 'a');
      expect(invoke('dart:core::Expando::[]#1', [expando, obj2]), 'b');
    });

    test('Expando toString', () {
      final expando = invoke('dart:core::Expando::#1', ['myExpando']);
      final str =
          invoke('dart:core::Expando::toString#0', [expando]) as String;
      expect(str, isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // MapEntry
  // ══════════════════════════════════════════════════════════════════

  group('MapEntryBindings registration', () {
    test('MapEntry bindings are registered', () {
      expect(registry.lookupByName('dart:core::MapEntry::#2'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::MapEntry::key#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::MapEntry::value#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::MapEntry::toString#0'),
          isNot(equals(-1)));
    });
  });

  group('MapEntryBindings invoke', () {
    test('MapEntry constructor and getters', () {
      final entry = invoke('dart:core::MapEntry::#2', ['key', 42]);
      expect(entry, isA<MapEntry>());
      expect(invoke('dart:core::MapEntry::key#0', [entry]), 'key');
      expect(invoke('dart:core::MapEntry::value#0', [entry]), 42);
    });

    test('MapEntry toString', () {
      final entry = invoke('dart:core::MapEntry::#2', ['a', 1]);
      final str =
          invoke('dart:core::MapEntry::toString#0', [entry]) as String;
      expect(str, contains('MapEntry'));
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // Iterator
  // ══════════════════════════════════════════════════════════════════

  group('IteratorBindings registration', () {
    test('Iterator bindings are registered', () {
      expect(registry.lookupByName('dart:core::Iterator::moveNext#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Iterator::current#0'),
          isNot(equals(-1)));
    });
  });

  group('IteratorBindings invoke', () {
    test('Iterator from List.iterator traverses all elements', () {
      // Get iterator from [1, 2, 3] via List::iterator#0
      final list = [1, 2, 3];
      final iter = invoke('dart:core::List::iterator#0', [list]);
      expect(iter, isA<Iterator>());

      // First element
      expect(invoke('dart:core::Iterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::Iterator::current#0', [iter]), 1);

      // Second element
      expect(invoke('dart:core::Iterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::Iterator::current#0', [iter]), 2);

      // Third element
      expect(invoke('dart:core::Iterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::Iterator::current#0', [iter]), 3);

      // End
      expect(invoke('dart:core::Iterator::moveNext#0', [iter]), false);
    });

    test('Iterator from Iterable.iterator works', () {
      final iterable = Iterable.generate(3, (i) => i * 10);
      final iter = invoke('dart:core::Iterable::iterator#0', [iterable]);

      expect(invoke('dart:core::Iterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::Iterator::current#0', [iter]), 0);
      expect(invoke('dart:core::Iterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::Iterator::current#0', [iter]), 10);
      expect(invoke('dart:core::Iterator::moveNext#0', [iter]), true);
      expect(invoke('dart:core::Iterator::current#0', [iter]), 20);
      expect(invoke('dart:core::Iterator::moveNext#0', [iter]), false);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // End-to-end compile+run tests
  // ══════════════════════════════════════════════════════════════════

  group('MiscBindings e2e', () {
    test('Symbol equality', () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return Symbol('foo') == Symbol('foo');
}
''');
      expect(result, true);
    });

    test('MapEntry key', () async {
      final result = await compileAndRunWithHost('''
String main() {
  MapEntry<String, int> entry = MapEntry('a', 1);
  return entry.key;
}
''');
      expect(result, 'a');
    });

    test('MapEntry value', () async {
      final result = await compileAndRunWithHost('''
int main() {
  MapEntry<String, int> entry = MapEntry('hello', 42);
  return entry.value;
}
''');
      expect(result, 42);
    });
  });
}
