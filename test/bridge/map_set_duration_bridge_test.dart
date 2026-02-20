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

  group('MapBindings registration', () {
    test('Map registry are registered', () {
      expect(registry.lookupByName('dart:core::Map::length#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::isEmpty#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::isNotEmpty#0'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::Map::keys#0'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::values#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::entries#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::[]#1'), isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::Map::[]=#2'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::containsKey#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::containsValue#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::remove#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::addAll#1'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::Map::clear#0'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Map::toString#0'),
          isNot(equals(-1)));
    });
  });

  group('MapBindings invoke', () {
    test('Map.length', () {
      expect(invoke('dart:core::Map::length#0', [{'a': 1, 'b': 2}]), 2);
    });

    test('Map.isEmpty / isNotEmpty', () {
      expect(invoke('dart:core::Map::isEmpty#0', [<String, int>{}]), true);
      expect(
          invoke('dart:core::Map::isNotEmpty#0', [
            {'a': 1}
          ]),
          true);
    });

    test('Map.[] operator', () {
      expect(
          invoke('dart:core::Map::[]#1', [
            {'a': 1},
            'a'
          ]),
          1);
    });

    test('Map.[]= operator', () {
      final map = <String, int>{};
      invoke('dart:core::Map::[]=#2', [map, 'x', 42]);
      expect(map['x'], 42);
    });

    test('Map.containsKey', () {
      expect(
          invoke('dart:core::Map::containsKey#1', [
            {'a': 1},
            'a'
          ]),
          true);
      expect(
          invoke('dart:core::Map::containsKey#1', [
            {'a': 1},
            'b'
          ]),
          false);
    });

    test('Map.containsValue', () {
      expect(
          invoke('dart:core::Map::containsValue#1', [
            {'a': 1},
            1
          ]),
          true);
    });

    test('Map.remove', () {
      final map = {'a': 1, 'b': 2};
      final removed = invoke('dart:core::Map::remove#1', [map, 'a']);
      expect(removed, 1);
      expect(map.containsKey('a'), false);
    });

    test('Map.addAll', () {
      final map = <String, int>{'a': 1};
      invoke('dart:core::Map::addAll#1', [
        map,
        {'b': 2}
      ]);
      expect(map, {'a': 1, 'b': 2});
    });

    test('Map.clear', () {
      final map = {'a': 1};
      invoke('dart:core::Map::clear#0', [map]);
      expect(map.isEmpty, true);
    });

    test('Map.keys / values', () {
      final map = {'a': 1, 'b': 2};
      expect(
          (invoke('dart:core::Map::keys#0', [map]) as Iterable).toList(),
          ['a', 'b']);
      expect(
          (invoke('dart:core::Map::values#0', [map]) as Iterable).toList(),
          [1, 2]);
    });

    test('Map.toString', () {
      expect(invoke('dart:core::Map::toString#0', [{'a': 1}]),
          '{a: 1}');
    });
  });

  group('SetBindings registration', () {
    test('Set registry are registered', () {
      expect(registry.lookupByName('dart:core::Set::length#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Set::isEmpty#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Set::isNotEmpty#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Set::contains#1'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::Set::add#1'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Set::remove#1'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::Set::union#1'), isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Set::intersection#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Set::difference#1'),
          isNot(equals(-1)));
      expect(
          registry.lookupByName('dart:core::Set::clear#0'), isNot(equals(-1)));
    });
  });

  group('SetBindings invoke', () {
    test('Set.length', () {
      expect(invoke('dart:core::Set::length#0', [{1, 2, 3}]), 3);
    });

    test('Set.isEmpty / isNotEmpty', () {
      expect(invoke('dart:core::Set::isEmpty#0', [<int>{}]), true);
      expect(invoke('dart:core::Set::isNotEmpty#0', [{1}]), true);
    });

    test('Set.contains', () {
      expect(invoke('dart:core::Set::contains#1', [{1, 2, 3}, 2]), true);
      expect(invoke('dart:core::Set::contains#1', [{1, 2, 3}, 4]), false);
    });

    test('Set.add', () {
      final s = <int>{1, 2};
      final added = invoke('dart:core::Set::add#1', [s, 3]);
      expect(added, true);
      expect(s.length, 3);
    });

    test('Set.remove', () {
      final s = <int>{1, 2, 3};
      final removed = invoke('dart:core::Set::remove#1', [s, 2]);
      expect(removed, true);
      expect(s.length, 2);
    });

    test('Set.union', () {
      final result = invoke('dart:core::Set::union#1', [{1, 2}, {2, 3}]);
      expect(result, {1, 2, 3});
    });

    test('Set.intersection', () {
      final result =
          invoke('dart:core::Set::intersection#1', [{1, 2, 3}, {2, 3, 4}]);
      expect(result, {2, 3});
    });

    test('Set.difference', () {
      final result =
          invoke('dart:core::Set::difference#1', [{1, 2, 3}, {2}]);
      expect(result, {1, 3});
    });

    test('Set.first / last', () {
      expect(invoke('dart:core::Set::first#0', [{10, 20, 30}]), 10);
      expect(invoke('dart:core::Set::last#0', [{10, 20, 30}]), 30);
    });

    test('Set.containsAll', () {
      expect(invoke('dart:core::Set::containsAll#1', [{1, 2, 3}, [1, 2]]),
          true);
    });

    test('Set.toList', () {
      expect(invoke('dart:core::Set::toList#1', [{1, 2, 3}]), [1, 2, 3]);
    });

    test('Set.clear', () {
      final s = {1, 2};
      invoke('dart:core::Set::clear#0', [s]);
      expect(s.isEmpty, true);
    });

    test('Set.toString', () {
      expect(invoke('dart:core::Set::toString#0', [{1, 2}]), '{1, 2}');
    });

    test('Set.join', () {
      expect(invoke('dart:core::Set::join#1', [{1, 2, 3}, ',']), '1,2,3');
    });
  });

  group('Map callback invoke', () {
    test('Map::forEach#1', () {
      final keys = <String>[];
      invoke('dart:core::Map::forEach#1', [
        {'a': 1, 'b': 2},
        (k, v) => keys.add(k as String),
      ]);
      expect(keys, ['a', 'b']);
    });

    test('Map::map#1', () {
      final result = invoke('dart:core::Map::map#1', [
        {'a': 1},
        (k, v) => MapEntry('${k}_mapped', (v as int) * 10),
      ]);
      expect(result, {'a_mapped': 10});
    });

    test('Map::updateAll#1', () {
      final map = {'a': 1, 'b': 2};
      invoke('dart:core::Map::updateAll#1', [
        map,
        (k, v) => (v as int) * 2,
      ]);
      expect(map, {'a': 2, 'b': 4});
    });

    test('Map::removeWhere#1', () {
      final map = {'a': 1, 'b': 2, 'c': 3};
      invoke('dart:core::Map::removeWhere#1', [
        map,
        (k, v) => (v as int) > 1,
      ]);
      expect(map, {'a': 1});
    });
  });

  group('Set callback invoke', () {
    test('Set::forEach#1', () {
      final collected = <int>[];
      invoke('dart:core::Set::forEach#1', [
        {1, 2, 3},
        (e) => collected.add(e as int),
      ]);
      expect(collected, [1, 2, 3]);
    });

    test('Set::map#1', () {
      final result = invoke('dart:core::Set::map#1', [
        {1, 2, 3},
        (e) => (e as int) * 2,
      ]);
      expect((result as Iterable).toList(), [2, 4, 6]);
    });

    test('Set::where#1', () {
      final result = invoke('dart:core::Set::where#1', [
        {1, 2, 3, 4},
        (e) => (e as int).isEven,
      ]);
      expect((result as Iterable).toList(), [2, 4]);
    });

    test('Set::any#1', () {
      expect(
        invoke('dart:core::Set::any#1', [
          {1, 2, 3},
          (e) => (e as int) > 2,
        ]),
        true,
      );
    });

    test('Set::every#1', () {
      expect(
        invoke('dart:core::Set::every#1', [
          {2, 4, 6},
          (e) => (e as int).isEven,
        ]),
        true,
      );
      expect(
        invoke('dart:core::Set::every#1', [
          {2, 3, 6},
          (e) => (e as int).isEven,
        ]),
        false,
      );
    });

    test('Set::fold#2', () {
      expect(
        invoke('dart:core::Set::fold#2', [
          {1, 2, 3},
          0,
          (prev, e) => (prev as int) + (e as int),
        ]),
        6,
      );
    });

    test('Set::reduce#1', () {
      expect(
        invoke('dart:core::Set::reduce#1', [
          {1, 2, 3},
          (a, b) => (a as int) + (b as int),
        ]),
        6,
      );
    });

    test('Set::expand#1', () {
      final result = invoke('dart:core::Set::expand#1', [
        {1, 2},
        (e) => [e, (e as int) * 10],
      ]);
      expect((result as Iterable).toList(), [1, 10, 2, 20]);
    });

    test('Set::firstWhere#2 with orElse', () {
      expect(
        invoke('dart:core::Set::firstWhere#2', [
          {1, 2, 3, 4},
          (e) => (e as int).isEven,
          null,
        ]),
        2,
      );
      // With orElse
      expect(
        invoke('dart:core::Set::firstWhere#2', [
          {1, 3, 5},
          (e) => (e as int).isEven,
          () => -1,
        ]),
        -1,
      );
    });

    test('Set::lastWhere#2', () {
      expect(
        invoke('dart:core::Set::lastWhere#2', [
          {1, 2, 3, 4},
          (e) => (e as int) < 3,
          null,
        ]),
        2,
      );
    });

    test('Set::singleWhere#2', () {
      expect(
        invoke('dart:core::Set::singleWhere#2', [
          {1, 2, 3},
          (e) => (e as int) == 2,
          null,
        ]),
        2,
      );
    });

    test('Set::takeWhile#1', () {
      final result = invoke('dart:core::Set::takeWhile#1', [
        {1, 2, 3, 4},
        (e) => (e as int) < 3,
      ]);
      expect((result as Iterable).toList(), [1, 2]);
    });

    test('Set::skipWhile#1', () {
      final result = invoke('dart:core::Set::skipWhile#1', [
        {1, 2, 3, 4},
        (e) => (e as int) < 3,
      ]);
      expect((result as Iterable).toList(), [3, 4]);
    });

    test('Set::toSet#0', () {
      final original = {1, 2, 3};
      final copy = invoke('dart:core::Set::toSet#0', [original]) as Set;
      expect(copy, {1, 2, 3});
      expect(identical(copy, original), false);
    });

    test('Set::elementAt#1', () {
      expect(invoke('dart:core::Set::elementAt#1', [{10, 20, 30}, 1]), 20);
    });

    test('Set::take#1', () {
      final result = invoke('dart:core::Set::take#1', [{1, 2, 3, 4}, 2]);
      expect((result as Iterable).toList(), [1, 2]);
    });

    test('Set::skip#1', () {
      final result = invoke('dart:core::Set::skip#1', [{1, 2, 3, 4}, 2]);
      expect((result as Iterable).toList(), [3, 4]);
    });

    test('Set::single#0', () {
      expect(invoke('dart:core::Set::single#0', [{42}]), 42);
    });
  });

  group('Map callback e2e', () {
    test('Map.forEach value sum', () async {
      final result = await compileAndRunWithHost('''
int main() {
  Map<String, int> m = {'a': 1, 'b': 2, 'c': 3};
  int sum = 0;
  m.forEach((k, v) {
    sum = sum + v;
  });
  return sum;
}
''');
      expect(result, 6);
    });

    test('Map.removeWhere then check length', () async {
      final result = await compileAndRunWithHost('''
int main() {
  Map<String, int> m = {'a': 1, 'b': 2, 'c': 3};
  m.removeWhere((k, v) => v > 1);
  return m.length;
}
''');
      expect(result, 1);
    });
  });

  group('Set callback e2e', () {
    test('Set.where filter then toList', () async {
      final result = await compileAndRunWithHost('''
String main() {
  Set<int> s = {1, 2, 3, 4, 5};
  return s.where((e) => e > 3).toList().toString();
}
''');
      expect(result, '[4, 5]');
    });

    test('Set.fold sum', () async {
      final result = await compileAndRunWithHost('''
int main() {
  Set<int> s = {1, 2, 3};
  return s.fold(0, (prev, e) => prev + e);
}
''');
      expect(result, 6);
    });
  });

  group('DurationBindings registration', () {
    test('Duration registry are registered', () {
      expect(registry.lookupByName('dart:core::Duration::inDays#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::inHours#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::inMinutes#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::inSeconds#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::inMilliseconds#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::inMicroseconds#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::isNegative#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::abs#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::+#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::-#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::*#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::~/#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::<#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::>#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::<=#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::>=#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::unary-#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::#6'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Duration::zero#0'),
          isNot(equals(-1)));
    });
  });

  group('DurationBindings invoke', () {
    test('Duration getters', () {
      final d = const Duration(hours: 1, minutes: 30, seconds: 15);
      expect(invoke('dart:core::Duration::inHours#0', [d]), 1);
      expect(invoke('dart:core::Duration::inMinutes#0', [d]), 90);
      expect(invoke('dart:core::Duration::inSeconds#0', [d]), 5415);
      expect(invoke('dart:core::Duration::isNegative#0', [d]), false);
    });

    test('Duration.inDays', () {
      final d = const Duration(days: 3);
      expect(invoke('dart:core::Duration::inDays#0', [d]), 3);
    });

    test('Duration.inMilliseconds / inMicroseconds', () {
      final d = const Duration(milliseconds: 500);
      expect(invoke('dart:core::Duration::inMilliseconds#0', [d]), 500);
      expect(invoke('dart:core::Duration::inMicroseconds#0', [d]), 500000);
    });

    test('Duration.abs()', () {
      final d = const Duration(seconds: -5);
      final result = invoke('dart:core::Duration::abs#0', [d]) as Duration;
      expect(result.inSeconds, 5);
    });

    test('Duration.compareTo', () {
      final d1 = const Duration(seconds: 1);
      final d2 = const Duration(seconds: 2);
      expect(invoke('dart:core::Duration::compareTo#1', [d1, d2]),
          lessThan(0));
    });

    test('Duration.toString', () {
      final d = const Duration(hours: 1, minutes: 2, seconds: 3);
      expect(invoke('dart:core::Duration::toString#0', [d]),
          '1:02:03.000000');
    });

    test('Duration + operator', () {
      final d1 = const Duration(seconds: 10);
      final d2 = const Duration(seconds: 5);
      final result = invoke('dart:core::Duration::+#1', [d1, d2]) as Duration;
      expect(result.inSeconds, 15);
    });

    test('Duration - operator', () {
      final d1 = const Duration(seconds: 10);
      final d2 = const Duration(seconds: 3);
      final result = invoke('dart:core::Duration::-#1', [d1, d2]) as Duration;
      expect(result.inSeconds, 7);
    });

    test('Duration * operator', () {
      final d = const Duration(seconds: 10);
      final result = invoke('dart:core::Duration::*#1', [d, 3]) as Duration;
      expect(result.inSeconds, 30);
    });

    test('Duration ~/ operator', () {
      final d = const Duration(seconds: 10);
      final result = invoke('dart:core::Duration::~/#1', [d, 3]) as Duration;
      expect(result.inMicroseconds,
          (const Duration(seconds: 10) ~/ 3).inMicroseconds);
    });

    test('Duration comparison operators', () {
      final d1 = const Duration(seconds: 1);
      final d2 = const Duration(seconds: 2);
      expect(invoke('dart:core::Duration::<#1', [d1, d2]), true);
      expect(invoke('dart:core::Duration::>#1', [d1, d2]), false);
      expect(invoke('dart:core::Duration::<=#1', [d1, d1]), true);
      expect(invoke('dart:core::Duration::>=#1', [d2, d1]), true);
    });

    test('Duration unary- operator', () {
      final d = const Duration(seconds: 5);
      final result =
          invoke('dart:core::Duration::unary-#0', [d]) as Duration;
      expect(result.inSeconds, -5);
    });

    test('Duration constructor with all 6 args', () {
      final result = invoke('dart:core::Duration::#6', [
        1, // days
        2, // hours
        3, // minutes
        4, // seconds
        5, // milliseconds
        6, // microseconds
      ]) as Duration;
      expect(result.inDays, 1);
      expect(result.inHours, 26); // 1*24 + 2
    });

    test('Duration.zero static getter', () {
      final result =
          invoke('dart:core::Duration::zero#0', []) as Duration;
      expect(result.inSeconds, 0);
    });

    test('Duration.hashCode', () {
      final d = const Duration(seconds: 5);
      expect(invoke('dart:core::Duration::hashCode#0', [d]), d.hashCode);
    });

    test('Duration static constants', () {
      expect(
          invoke(
              'dart:core::Duration::microsecondsPerMillisecond#0', []),
          1000);
      expect(
          invoke('dart:core::Duration::millisecondsPerSecond#0', []),
          1000);
      expect(
          invoke('dart:core::Duration::secondsPerMinute#0', []), 60);
      expect(
          invoke('dart:core::Duration::minutesPerHour#0', []), 60);
      expect(
          invoke('dart:core::Duration::hoursPerDay#0', []), 24);
    });
  });

  group('ErrorBindings registration', () {
    test('Error registry are registered', () {
      expect(registry.lookupByName('dart:core::ArgumentError::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::ArgumentError::message#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::ArgumentError::toString#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::RangeError::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::RangeError::range#5'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StateError::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::UnsupportedError::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::FormatException::#3'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Error::toString#0'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::Exception::toString#0'),
          isNot(equals(-1)));
      expect(
          registry
              .lookupByName('dart:core::ConcurrentModificationError::#1'),
          isNot(equals(-1)));
      expect(registry.lookupByName('dart:core::StackOverflowError::#0'),
          isNot(equals(-1)));
    });
  });

  group('ErrorBindings invoke', () {
    test('ArgumentError constructor and message', () {
      final err =
          invoke('dart:core::ArgumentError::#1', ['bad arg']) as ArgumentError;
      expect(
          invoke('dart:core::ArgumentError::message#0', [err]), 'bad arg');
    });

    test('ArgumentError.toString', () {
      final err =
          invoke('dart:core::ArgumentError::#1', ['bad arg']) as ArgumentError;
      expect(invoke('dart:core::ArgumentError::toString#0', [err]),
          contains('bad arg'));
    });

    test('RangeError constructor', () {
      final err =
          invoke('dart:core::RangeError::#1', ['out of range']) as RangeError;
      expect(invoke('dart:core::RangeError::toString#0', [err]),
          contains('out of range'));
    });

    test('RangeError.range', () {
      final err = invoke(
          'dart:core::RangeError::range#5', [10, 0, 5, 'index', null]) as RangeError;
      expect(err, isA<RangeError>());
    });

    test('StateError constructor and message', () {
      final err =
          invoke('dart:core::StateError::#1', ['bad state']) as StateError;
      expect(invoke('dart:core::StateError::message#0', [err]), 'bad state');
    });

    test('UnsupportedError constructor and message', () {
      final err = invoke('dart:core::UnsupportedError::#1', ['not supported'])
          as UnsupportedError;
      expect(invoke('dart:core::UnsupportedError::message#0', [err]),
          'not supported');
    });

    test('FormatException constructor', () {
      final err = invoke(
              'dart:core::FormatException::#3', ['bad format', 'source', 5])
          as FormatException;
      expect(
          invoke('dart:core::FormatException::message#0', [err]),
          'bad format');
    });

    test('FormatException with fewer args', () {
      final err =
          invoke('dart:core::FormatException::#3', []) as FormatException;
      expect(err, isA<FormatException>());
    });

    test('ConcurrentModificationError constructor', () {
      final err =
          invoke('dart:core::ConcurrentModificationError::#1', ['oops']);
      expect(err, isA<ConcurrentModificationError>());
    });

    test('StackOverflowError constructor', () {
      final err = invoke('dart:core::StackOverflowError::#0', []);
      expect(err, isA<StackOverflowError>());
    });

    test('Error.toString', () {
      final err = ArgumentError('test');
      expect(invoke('dart:core::Error::toString#0', [err]),
          contains('test'));
    });

    test('Exception.toString', () {
      final exc = FormatException('test');
      expect(invoke('dart:core::Exception::toString#0', [exc]),
          contains('test'));
    });
  });
}
