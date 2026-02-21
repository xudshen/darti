/// Registers `dart:collection` host bindings for the CALL_HOST pipeline.
///
/// Covers LinkedHashMap/LinkedHashSet (via internal _compact_hash types),
/// Queue (ListQueue), SplayTreeMap, SplayTreeSet, HashMap, HashSet,
/// and UnmodifiableListView.
///
/// Note: Many collection operations resolve to `dart:core::Map`/`Set`/
/// `Iterable` interfaces at the Kernel level, which are already registered
/// in CoreBindings (MapBindings, SetBindings, IterableBindings).
///
/// See: docs/design/04-interop.md
library;

import 'dart:collection';

import '../host_function_registry.dart';

/// Registers all `dart:collection` host function bindings.
abstract final class CollectionBindings {
  static void register(HostFunctionRegistry registry) {
    // ══════════════════════════════════════════════════════════════════
    // LinkedHashMap / LinkedHashSet internal constructors
    // ══════════════════════════════════════════════════════════════════
    // LinkedHashMap() and LinkedHashSet() are factory constructors that
    // redirect to dart:_compact_hash::_Map and dart:_compact_hash::_Set.

    registry.register('dart:_compact_hash::_Map::#0', (args) {
      // ignore: prefer_collection_literals — intentionally constructs typed map
      return LinkedHashMap<Object?, Object?>();
    });

    registry.register('dart:_compact_hash::_Set::#0', (args) {
      // ignore: prefer_collection_literals — intentionally constructs typed set
      return LinkedHashSet<Object?>();
    });

    // LinkedHashMap.from(Map other)
    registry.register('dart:collection::LinkedHashMap::from#1', (args) {
      return LinkedHashMap.from(args[0] as Map);
    });

    // LinkedHashMap.of(Map<K, V> other)
    registry.register('dart:collection::LinkedHashMap::of#1', (args) {
      return LinkedHashMap.of(args[0] as Map);
    });

    // LinkedHashSet.from(Iterable elements)
    registry.register('dart:collection::LinkedHashSet::from#1', (args) {
      return LinkedHashSet.from(args[0] as Iterable);
    });

    // LinkedHashSet.of(Iterable<E> elements)
    registry.register('dart:collection::LinkedHashSet::of#1', (args) {
      return LinkedHashSet.of(args[0] as Iterable);
    });

    // LinkedHashMap._fromEntries(Iterable<MapEntry> entries)
    // CFE lowers Map.fromEntries to this internal factory.
    registry.register('dart:collection::LinkedHashMap::_fromEntries#1', (args) {
      return Map.fromEntries((args[0] as Iterable).cast<MapEntry>());
    });

    // ══════════════════════════════════════════════════════════════════
    // HashMap / HashSet
    // ══════════════════════════════════════════════════════════════════

    // HashMap({bool Function(K, K)? equals, int Function(K)? hashCode,
    //          bool Function(dynamic)? isValidKey})
    registry.register('dart:collection::HashMap::#3', (args) {
      final equals = args.isNotEmpty ? args[0] as Function? : null;
      final hashCodeFn = args.length > 1 ? args[1] as Function? : null;
      final isValidKey = args.length > 2 ? args[2] as Function? : null;
      return HashMap<Object?, Object?>(
        equals: equals != null ? (a, b) => equals(a, b) as bool : null,
        hashCode: hashCodeFn != null ? (k) => hashCodeFn(k) as int : null,
        isValidKey: isValidKey != null ? (k) => isValidKey(k) as bool : null,
      );
    });

    // HashMap.from(Map other)
    registry.register('dart:collection::HashMap::from#1', (args) {
      return HashMap.from(args[0] as Map);
    });

    // HashMap.of(Map<K, V> other)
    registry.register('dart:collection::HashMap::of#1', (args) {
      return HashMap.of(args[0] as Map);
    });

    // HashSet({bool Function(E, E)? equals, int Function(E)? hashCode,
    //          bool Function(dynamic)? isValidKey})
    registry.register('dart:collection::HashSet::#3', (args) {
      final equals = args.isNotEmpty ? args[0] as Function? : null;
      final hashCodeFn = args.length > 1 ? args[1] as Function? : null;
      final isValidKey = args.length > 2 ? args[2] as Function? : null;
      return HashSet<Object?>(
        equals: equals != null ? (a, b) => equals(a, b) as bool : null,
        hashCode: hashCodeFn != null ? (e) => hashCodeFn(e) as int : null,
        isValidKey: isValidKey != null ? (k) => isValidKey(k) as bool : null,
      );
    });

    // HashSet.from(Iterable elements)
    registry.register('dart:collection::HashSet::from#1', (args) {
      return HashSet.from(args[0] as Iterable);
    });

    // HashSet.of(Iterable<E> elements)
    registry.register('dart:collection::HashSet::of#1', (args) {
      return HashSet.of(args[0] as Iterable);
    });

    // ══════════════════════════════════════════════════════════════════
    // Queue (ListQueue)
    // ══════════════════════════════════════════════════════════════════
    // Queue() factory redirects to ListQueue internally.

    registry.register('dart:collection::ListQueue::#1', (args) {
      final initialCapacity =
          args.isNotEmpty ? args[0] as int? : null;
      if (initialCapacity != null) {
        return ListQueue<Object?>(initialCapacity);
      }
      return ListQueue<Object?>();
    });

    // Queue.from(Iterable elements)
    registry.register('dart:collection::Queue::from#1', (args) {
      return Queue.from(args[0] as Iterable);
    });

    // Queue.of(Iterable<E> elements)
    registry.register('dart:collection::Queue::of#1', (args) {
      return Queue.of(args[0] as Iterable);
    });

    // queue.add(E value)
    registry.register('dart:collection::Queue::add#1', (args) {
      (args[0] as Queue).add(args[1]);
      return null;
    });

    // queue.addFirst(E value)
    registry.register('dart:collection::Queue::addFirst#1', (args) {
      (args[0] as Queue).addFirst(args[1]);
      return null;
    });

    // queue.addLast(E value)
    registry.register('dart:collection::Queue::addLast#1', (args) {
      (args[0] as Queue).addLast(args[1]);
      return null;
    });

    // queue.removeFirst() → E
    registry.register('dart:collection::Queue::removeFirst#0', (args) {
      return (args[0] as Queue).removeFirst();
    });

    // queue.removeLast() → E
    registry.register('dart:collection::Queue::removeLast#0', (args) {
      return (args[0] as Queue).removeLast();
    });

    // queue.clear()
    registry.register('dart:collection::Queue::clear#0', (args) {
      (args[0] as Queue).clear();
      return null;
    });

    // ══════════════════════════════════════════════════════════════════
    // SplayTreeMap
    // ══════════════════════════════════════════════════════════════════

    // SplayTreeMap([int Function(K, K)? compare, bool Function(dynamic)? isValidKey])
    registry.register('dart:collection::SplayTreeMap::#2', (args) {
      final compare = args.isNotEmpty ? args[0] as Function? : null;
      final isValidKey = args.length > 1 ? args[1] as Function? : null;
      return SplayTreeMap<Object?, Object?>(
        compare != null ? (a, b) => compare(a, b) as int : null,
        isValidKey != null ? (k) => isValidKey(k) as bool : null,
      );
    });

    // SplayTreeMap.from(Map other, [int Function(K, K)? compare,
    //                               bool Function(dynamic)? isValidKey])
    registry.register('dart:collection::SplayTreeMap::from#3', (args) {
      return SplayTreeMap.from(args[0] as Map);
    });

    // splayTreeMap[key] → V?
    registry.register('dart:collection::SplayTreeMap::[]#1', (args) {
      return (args[0] as SplayTreeMap)[args[1]];
    });

    // splayTreeMap[key] = value
    registry.register('dart:collection::SplayTreeMap::[]=#2', (args) {
      (args[0] as SplayTreeMap)[args[1]] = args[2];
      return args[2];
    });

    // splayTreeMap.firstKey() → K?
    registry.register('dart:collection::SplayTreeMap::firstKey#0', (args) {
      return (args[0] as SplayTreeMap).firstKey();
    });

    // splayTreeMap.lastKey() → K?
    registry.register('dart:collection::SplayTreeMap::lastKey#0', (args) {
      return (args[0] as SplayTreeMap).lastKey();
    });

    // splayTreeMap.remove(Object? key) → V?
    registry.register('dart:collection::SplayTreeMap::remove#1', (args) {
      return (args[0] as SplayTreeMap).remove(args[1]);
    });

    // splayTreeMap.containsKey(Object? key) → bool
    registry.register('dart:collection::SplayTreeMap::containsKey#1', (args) {
      return (args[0] as SplayTreeMap).containsKey(args[1]);
    });

    // splayTreeMap.length → int
    registry.register('dart:collection::SplayTreeMap::length#0', (args) {
      return (args[0] as SplayTreeMap).length;
    });

    // splayTreeMap.keys → Iterable<K>
    registry.register('dart:collection::SplayTreeMap::keys#0', (args) {
      return (args[0] as SplayTreeMap).keys;
    });

    // splayTreeMap.values → Iterable<V>
    registry.register('dart:collection::SplayTreeMap::values#0', (args) {
      return (args[0] as SplayTreeMap).values;
    });

    // ══════════════════════════════════════════════════════════════════
    // SplayTreeSet
    // ══════════════════════════════════════════════════════════════════

    // SplayTreeSet([int Function(E, E)? compare, bool Function(dynamic)? isValidKey])
    registry.register('dart:collection::SplayTreeSet::#2', (args) {
      final compare = args.isNotEmpty ? args[0] as Function? : null;
      final isValidKey = args.length > 1 ? args[1] as Function? : null;
      return SplayTreeSet<Object?>(
        compare != null ? (a, b) => compare(a, b) as int : null,
        isValidKey != null ? (k) => isValidKey(k) as bool : null,
      );
    });

    // SplayTreeSet.from(Iterable elements, [...])
    registry.register('dart:collection::SplayTreeSet::from#3', (args) {
      return SplayTreeSet.from(args[0] as Iterable);
    });

    // splayTreeSet.add(E value) → bool
    registry.register('dart:collection::SplayTreeSet::add#1', (args) {
      return (args[0] as SplayTreeSet).add(args[1]);
    });

    // splayTreeSet.first → E
    registry.register('dart:collection::SplayTreeSet::first#0', (args) {
      return (args[0] as SplayTreeSet).first;
    });

    // splayTreeSet.last → E
    registry.register('dart:collection::SplayTreeSet::last#0', (args) {
      return (args[0] as SplayTreeSet).last;
    });

    // splayTreeSet.contains(Object? element) → bool
    registry.register('dart:collection::SplayTreeSet::contains#1', (args) {
      return (args[0] as SplayTreeSet).contains(args[1]);
    });

    // splayTreeSet.remove(Object? value) → bool
    registry.register('dart:collection::SplayTreeSet::remove#1', (args) {
      return (args[0] as SplayTreeSet).remove(args[1]);
    });

    // splayTreeSet.length → int
    registry.register('dart:collection::SplayTreeSet::length#0', (args) {
      return (args[0] as SplayTreeSet).length;
    });

    // ══════════════════════════════════════════════════════════════════
    // UnmodifiableListView
    // ══════════════════════════════════════════════════════════════════

    // UnmodifiableListView(Iterable<E> source)
    registry.register('dart:collection::UnmodifiableListView::#1', (args) {
      return UnmodifiableListView(args[0] as Iterable);
    });

    // unmodifiableListView[index] → E
    registry.register('dart:collection::UnmodifiableListView::[]#1', (args) {
      return (args[0] as UnmodifiableListView)[args[1] as int];
    });

    // unmodifiableListView.length → int
    registry.register('dart:collection::UnmodifiableListView::length#0',
        (args) {
      return (args[0] as UnmodifiableListView).length;
    });

    // unmodifiableListView.iterator → Iterator<E>
    registry.register('dart:collection::UnmodifiableListView::iterator#0',
        (args) {
      return (args[0] as UnmodifiableListView).iterator;
    });

    // ══════════════════════════════════════════════════════════════════
    // UnmodifiableMapView
    // ══════════════════════════════════════════════════════════════════

    // UnmodifiableMapView(Map<K, V> map)
    registry.register('dart:collection::UnmodifiableMapView::#1', (args) {
      return UnmodifiableMapView(args[0] as Map);
    });

    // unmodifiableMapView[key] → V?
    registry.register('dart:collection::UnmodifiableMapView::[]#1', (args) {
      return (args[0] as UnmodifiableMapView)[args[1]];
    });

    // unmodifiableMapView.length → int
    registry.register('dart:collection::UnmodifiableMapView::length#0',
        (args) {
      return (args[0] as UnmodifiableMapView).length;
    });

    // unmodifiableMapView.keys → Iterable<K>
    registry.register('dart:collection::UnmodifiableMapView::keys#0', (args) {
      return (args[0] as UnmodifiableMapView).keys;
    });

    // unmodifiableMapView.values → Iterable<V>
    registry.register('dart:collection::UnmodifiableMapView::values#0',
        (args) {
      return (args[0] as UnmodifiableMapView).values;
    });

    // unmodifiableMapView.containsKey(Object? key) → bool
    registry.register('dart:collection::UnmodifiableMapView::containsKey#1',
        (args) {
      return (args[0] as UnmodifiableMapView).containsKey(args[1]);
    });

    // ══════════════════════════════════════════════════════════════════
    // UnmodifiableSetView
    // ══════════════════════════════════════════════════════════════════

    // UnmodifiableSetView(Set<E> source)
    registry.register('dart:collection::UnmodifiableSetView::#1', (args) {
      return UnmodifiableSetView(args[0] as Set);
    });

    // unmodifiableSetView.length → int
    registry.register('dart:collection::UnmodifiableSetView::length#0', (args) {
      return (args[0] as UnmodifiableSetView).length;
    });

    // unmodifiableSetView.contains(Object? element) → bool
    registry.register('dart:collection::UnmodifiableSetView::contains#1',
        (args) {
      return (args[0] as UnmodifiableSetView).contains(args[1]);
    });

    // unmodifiableSetView.iterator → Iterator<E>
    registry.register('dart:collection::UnmodifiableSetView::iterator#0',
        (args) {
      return (args[0] as UnmodifiableSetView).iterator;
    });

    // unmodifiableSetView.lookup(Object? element) → E?
    registry.register('dart:collection::UnmodifiableSetView::lookup#1', (args) {
      return (args[0] as UnmodifiableSetView).lookup(args[1]);
    });

    // unmodifiableSetView.toSet() → Set<E>
    registry.register('dart:collection::UnmodifiableSetView::toSet#0', (args) {
      return (args[0] as UnmodifiableSetView).toSet();
    });
  }
}
