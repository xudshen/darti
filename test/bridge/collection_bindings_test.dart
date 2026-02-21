import 'dart:collection';

import 'package:dartic/src/bridge/bindings/collection_bindings.dart';
import 'package:dartic/src/bridge/collection_bindings.dart';
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
    CollectionBindings.register(registry);
  });

  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  group('CollectionBindings LinkedHashMap/LinkedHashSet', () {
    test('_compact_hash _Map constructor', () {
      final map = invoke('dart:_compact_hash::_Map::#0', []);
      expect(map, isA<LinkedHashMap>());
      expect((map as Map).isEmpty, isTrue);
    });

    test('_compact_hash _Set constructor', () {
      final set = invoke('dart:_compact_hash::_Set::#0', []);
      expect(set, isA<LinkedHashSet>());
      expect((set as Set).isEmpty, isTrue);
    });

    test('LinkedHashMap.from', () {
      final map = invoke('dart:collection::LinkedHashMap::from#1', [
        {'a': 1, 'b': 2}
      ]);
      expect(map, isA<LinkedHashMap>());
      expect((map as Map)['a'], 1);
    });

    test('LinkedHashSet.from', () {
      final set = invoke('dart:collection::LinkedHashSet::from#1', [
        [1, 2, 3]
      ]);
      expect(set, isA<LinkedHashSet>());
      expect((set as Set).length, 3);
    });
  });

  group('CollectionBindings HashMap/HashSet', () {
    test('HashMap constructor', () {
      final map = invoke('dart:collection::HashMap::#3', [null, null, null]);
      expect(map, isA<HashMap>());
    });

    test('HashSet constructor', () {
      final set = invoke('dart:collection::HashSet::#3', [null, null, null]);
      expect(set, isA<HashSet>());
    });
  });

  group('CollectionBindings Queue', () {
    test('ListQueue constructor and operations', () {
      final queue = invoke('dart:collection::ListQueue::#1', [null]) as Queue;
      invoke('dart:collection::Queue::add#1', [queue, 'a']);
      invoke('dart:collection::Queue::addFirst#1', [queue, 'z']);
      invoke('dart:collection::Queue::addLast#1', [queue, 'm']);
      expect(invoke('dart:collection::Queue::removeFirst#0', [queue]), 'z');
      expect(invoke('dart:collection::Queue::removeLast#0', [queue]), 'm');
      invoke('dart:collection::Queue::clear#0', [queue]);
      expect(queue.isEmpty, isTrue);
    });
  });

  group('CollectionBindings SplayTreeMap', () {
    test('constructor and operations', () {
      final map =
          invoke('dart:collection::SplayTreeMap::#2', [null, null])
              as SplayTreeMap;
      invoke('dart:collection::SplayTreeMap::[]=#2', [map, 'b', 2]);
      invoke('dart:collection::SplayTreeMap::[]=#2', [map, 'a', 1]);
      invoke('dart:collection::SplayTreeMap::[]=#2', [map, 'c', 3]);

      expect(invoke('dart:collection::SplayTreeMap::[]#1', [map, 'a']), 1);
      expect(invoke('dart:collection::SplayTreeMap::length#0', [map]), 3);
      expect(invoke('dart:collection::SplayTreeMap::firstKey#0', [map]), 'a');
      expect(invoke('dart:collection::SplayTreeMap::lastKey#0', [map]), 'c');
      expect(
          invoke('dart:collection::SplayTreeMap::containsKey#1', [map, 'b']),
          isTrue);
      invoke('dart:collection::SplayTreeMap::remove#1', [map, 'b']);
      expect(invoke('dart:collection::SplayTreeMap::length#0', [map]), 2);
    });
  });

  group('CollectionBindings SplayTreeSet', () {
    test('constructor and operations', () {
      final set =
          invoke('dart:collection::SplayTreeSet::#2', [null, null])
              as SplayTreeSet;
      invoke('dart:collection::SplayTreeSet::add#1', [set, 3]);
      invoke('dart:collection::SplayTreeSet::add#1', [set, 1]);
      invoke('dart:collection::SplayTreeSet::add#1', [set, 2]);

      expect(invoke('dart:collection::SplayTreeSet::first#0', [set]), 1);
      expect(invoke('dart:collection::SplayTreeSet::last#0', [set]), 3);
      expect(invoke('dart:collection::SplayTreeSet::length#0', [set]), 3);
      expect(
          invoke('dart:collection::SplayTreeSet::contains#1', [set, 2]),
          isTrue);
      invoke('dart:collection::SplayTreeSet::remove#1', [set, 2]);
      expect(invoke('dart:collection::SplayTreeSet::length#0', [set]), 2);
    });
  });

  group('CollectionBindings UnmodifiableListView', () {
    test('constructor and accessors', () {
      final view = invoke('dart:collection::UnmodifiableListView::#1', [
        [10, 20, 30]
      ]) as UnmodifiableListView;
      expect(
          invoke('dart:collection::UnmodifiableListView::length#0', [view]), 3);
      expect(
          invoke('dart:collection::UnmodifiableListView::[]#1', [view, 1]), 20);
    });
  });

  group('CollectionBindings Map.fromEntries', () {
    test('LinkedHashMap._fromEntries is registered', () {
      // CFE may lower Map.fromEntries to LinkedHashMap._fromEntries
      expect(
          registry.lookupByName(
              'dart:collection::LinkedHashMap::_fromEntries#1'),
          isNot(equals(-1)));
    });

    test('Map.fromEntries creates map from entries', () {
      final entries = [MapEntry('a', 1), MapEntry('b', 2)];
      final map = invoke(
              'dart:collection::LinkedHashMap::_fromEntries#1', [entries])
          as Map;
      expect(map, {'a': 1, 'b': 2});
    });
  });

  group('Set.symmetricDifference', () {
    test('Set.symmetricDifference is registered', () {
      expect(
          registry.lookupByName('dart:core::Set::symmetricDifference#1'),
          isNot(equals(-1)));
    });

    test('symmetricDifference returns elements in either but not both', () {
      final a = {1, 2, 3};
      final b = {2, 3, 4};
      final result = invoke(
              'dart:core::Set::symmetricDifference#1', [a, b])
          as Set;
      expect(result, {1, 4});
    });
  });

  group('Collection cast()', () {
    test('List.cast is registered', () {
      expect(registry.lookupByName('dart:core::List::cast#0'),
          isNot(equals(-1)));
    });

    test('_GrowableList.cast is registered', () {
      expect(registry.lookupByName('dart:core::_GrowableList::cast#0'),
          isNot(equals(-1)));
    });

    test('Map.cast is registered', () {
      expect(registry.lookupByName('dart:core::Map::cast#0'),
          isNot(equals(-1)));
    });

    test('Set.cast is registered', () {
      expect(registry.lookupByName('dart:core::Set::cast#0'),
          isNot(equals(-1)));
    });

    test('_Set.cast is registered', () {
      expect(registry.lookupByName('dart:_compact_hash::_Set::cast#0'),
          isNot(equals(-1)));
    });

    test('Iterable.cast is registered', () {
      expect(registry.lookupByName('dart:core::Iterable::cast#0'),
          isNot(equals(-1)));
    });

    test('List.cast returns a list', () {
      final list = [1, 2, 3];
      final result = invoke('dart:core::List::cast#0', [list]) as List;
      expect(result.toList(), [1, 2, 3]);
    });

    test('Map.cast returns a map', () {
      final map = {'a': 1, 'b': 2};
      final result = invoke('dart:core::Map::cast#0', [map]) as Map;
      expect(result, {'a': 1, 'b': 2});
    });

    test('Set.cast returns a set', () {
      final set = {1, 2, 3};
      final result = invoke('dart:core::Set::cast#0', [set]) as Set;
      expect(result, {1, 2, 3});
    });

    test('Iterable.cast returns an iterable', () {
      final iter = [1, 2, 3] as Iterable;
      final result = invoke('dart:core::Iterable::cast#0', [iter]) as Iterable;
      expect(result.toList(), [1, 2, 3]);
    });
  });

  group('CollectionBindings UnmodifiableMapView', () {
    test('constructor and accessors', () {
      final view = invoke('dart:collection::UnmodifiableMapView::#1', [
        {'x': 1, 'y': 2}
      ]) as UnmodifiableMapView;
      expect(
          invoke('dart:collection::UnmodifiableMapView::length#0', [view]), 2);
      expect(
          invoke('dart:collection::UnmodifiableMapView::[]#1', [view, 'x']), 1);
      expect(
          invoke(
              'dart:collection::UnmodifiableMapView::containsKey#1', [view, 'y']),
          isTrue);
    });
  });

  group('Collection comparator support', () {
    test('SplayTreeMap with custom comparator', () {
      // Reverse order comparator
      int compare(Object? a, Object? b) =>
          (b as Comparable).compareTo(a as Comparable);
      final map =
          invoke('dart:collection::SplayTreeMap::#2', [compare, null])
              as SplayTreeMap;
      invoke('dart:collection::SplayTreeMap::[]=#2', [map, 'a', 1]);
      invoke('dart:collection::SplayTreeMap::[]=#2', [map, 'b', 2]);
      invoke('dart:collection::SplayTreeMap::[]=#2', [map, 'c', 3]);
      // Reverse order: first key should be 'c', last 'a'
      expect(invoke('dart:collection::SplayTreeMap::firstKey#0', [map]), 'c');
      expect(invoke('dart:collection::SplayTreeMap::lastKey#0', [map]), 'a');
    });

    test('SplayTreeSet with custom comparator', () {
      // Reverse order comparator
      int compare(Object? a, Object? b) =>
          (b as Comparable).compareTo(a as Comparable);
      final set =
          invoke('dart:collection::SplayTreeSet::#2', [compare, null])
              as SplayTreeSet;
      invoke('dart:collection::SplayTreeSet::add#1', [set, 1]);
      invoke('dart:collection::SplayTreeSet::add#1', [set, 2]);
      invoke('dart:collection::SplayTreeSet::add#1', [set, 3]);
      // Reverse order: first should be 3, last 1
      expect(invoke('dart:collection::SplayTreeSet::first#0', [set]), 3);
      expect(invoke('dart:collection::SplayTreeSet::last#0', [set]), 1);
    });

    test('HashMap with custom equals/hashCode', () {
      // Case-insensitive string map
      bool equals(Object? a, Object? b) =>
          (a as String).toLowerCase() == (b as String).toLowerCase();
      int hashFn(Object? e) => (e as String).toLowerCase().hashCode;
      bool isValidKey(Object? k) => k is String;
      final map = invoke('dart:collection::HashMap::#3',
          [equals, hashFn, isValidKey]) as HashMap;
      map['Hello'] = 1;
      expect(map['hello'], 1);
      expect(map['HELLO'], 1);
    });

    test('HashSet with custom equals/hashCode', () {
      bool equals(Object? a, Object? b) =>
          (a as String).toLowerCase() == (b as String).toLowerCase();
      int hashFn(Object? e) => (e as String).toLowerCase().hashCode;
      bool isValidKey(Object? k) => k is String;
      final set = invoke('dart:collection::HashSet::#3',
          [equals, hashFn, isValidKey]) as HashSet;
      set.add('Hello');
      expect(set.contains('hello'), true);
      expect(set.contains('HELLO'), true);
      expect(set.length, 1);
    });

    test('SplayTreeMap without comparator still works', () {
      final map =
          invoke('dart:collection::SplayTreeMap::#2', [null, null])
              as SplayTreeMap;
      invoke('dart:collection::SplayTreeMap::[]=#2', [map, 'a', 1]);
      invoke('dart:collection::SplayTreeMap::[]=#2', [map, 'b', 2]);
      expect(invoke('dart:collection::SplayTreeMap::firstKey#0', [map]), 'a');
    });
  });

  group('CollectionBindings UnmodifiableSetView', () {
    test('constructor is registered', () {
      expect(
          registry.lookupByName('dart:collection::UnmodifiableSetView::#1'),
          isNot(equals(-1)));
    });

    test('constructor creates unmodifiable set view', () {
      final view = invoke('dart:collection::UnmodifiableSetView::#1', [
        {10, 20, 30}
      ]);
      expect(view, isA<UnmodifiableSetView>());
    });

    test('length returns correct count', () {
      final view = UnmodifiableSetView({10, 20, 30});
      expect(
          invoke('dart:collection::UnmodifiableSetView::length#0', [view]), 3);
    });

    test('contains checks membership', () {
      final view = UnmodifiableSetView({10, 20, 30});
      expect(
          invoke(
              'dart:collection::UnmodifiableSetView::contains#1', [view, 20]),
          true);
      expect(
          invoke(
              'dart:collection::UnmodifiableSetView::contains#1', [view, 99]),
          false);
    });

    test('iterator returns an iterator', () {
      final view = UnmodifiableSetView({10, 20, 30});
      final iter = invoke(
          'dart:collection::UnmodifiableSetView::iterator#0', [view]);
      expect(iter, isA<Iterator>());
    });

    test('lookup returns element or null', () {
      final view = UnmodifiableSetView({10, 20, 30});
      expect(
          invoke(
              'dart:collection::UnmodifiableSetView::lookup#1', [view, 20]),
          20);
      expect(
          invoke(
              'dart:collection::UnmodifiableSetView::lookup#1', [view, 99]),
          isNull);
    });

    test('toSet returns a new set', () {
      final view = UnmodifiableSetView({10, 20, 30});
      final result = invoke(
          'dart:collection::UnmodifiableSetView::toSet#0', [view]) as Set;
      expect(result, {10, 20, 30});
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // E2E compile+run tests
  // ══════════════════════════════════════════════════════════════════

  group('CollectionBindings e2e', () {
    Future<(Object?, List<String>)> runCollectionWithHost(
        String source) async {
      final printLog = <String>[];
      final module = await compileDart(source);
      final reg = HostFunctionRegistry();
      CoreBindings.registerAll(reg, printFn: (v) => printLog.add('$v'));
      CollectionBindingsHub.registerAll(reg);
      final interp = DarticInterpreter(
        hostFunctionRegistry: reg,
        fuelBudget: DarticInterpreter.defaultFuelBudget,
      );
      interp.execute(module);
      return (interp.entryResult, printLog);
    }

    test('Map.fromEntries compile+run', () async {
      final (_, prints) = await runCollectionWithHost('''
void main() {
  var entries = [MapEntry('a', 1), MapEntry('b', 2), MapEntry('c', 3)];
  var map = Map.fromEntries(entries);
  print(map.length);
  print(map['b']);
}
''');
      expect(prints, ['3', '2']);
    });
  });
}
