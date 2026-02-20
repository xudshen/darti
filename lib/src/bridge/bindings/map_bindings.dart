/// Registers `Map` host registry for the CALL_HOST pipeline.
///
/// Covers Map instance methods, getters, and operators.
/// Callback-based methods (forEach, map, etc.) are deferred to 5.3.3
/// when DarticCallbackProxy is ready.
///
/// See: docs/design/04-interop.md
library;

import 'dart:collection';

import '../host_function_registry.dart';

/// Registers all `dart:core::Map` host function registry.
abstract final class MapBindings {
  static void register(HostFunctionRegistry registry) {
    // ── LinkedHashMap factories (CFE lowers map literals/spreads to these) ──
    registry.register('dart:collection::LinkedHashMap::of#1', (args) {
      return LinkedHashMap<dynamic, dynamic>.of(args[0] as Map);
    });
    registry.register('dart:collection::LinkedHashMap::#0', (args) {
      return <dynamic, dynamic>{};
    });

    // ── Getters ──
    registry.register('dart:core::Map::length#0', (args) {
      return (args[0] as Map).length;
    });
    registry.register('dart:core::Map::isEmpty#0', (args) {
      return (args[0] as Map).isEmpty;
    });
    registry.register('dart:core::Map::isNotEmpty#0', (args) {
      return (args[0] as Map).isNotEmpty;
    });
    registry.register('dart:core::Map::keys#0', (args) {
      return (args[0] as Map).keys;
    });
    registry.register('dart:core::Map::values#0', (args) {
      return (args[0] as Map).values;
    });
    registry.register('dart:core::Map::entries#0', (args) {
      return (args[0] as Map).entries;
    });
    registry.register('dart:core::Map::hashCode#0', (args) {
      return (args[0] as Map).hashCode;
    });

    // ── Operators ──
    registry.register('dart:core::Map::[]#1', (args) {
      return (args[0] as Map)[args[1]];
    });
    registry.register('dart:core::Map::[]=#2', (args) {
      (args[0] as Map)[args[1]] = args[2];
      return args[2];
    });

    // ── Methods ──
    registry.register('dart:core::Map::containsKey#1', (args) {
      return (args[0] as Map).containsKey(args[1]);
    });
    registry.register('dart:core::Map::containsValue#1', (args) {
      return (args[0] as Map).containsValue(args[1]);
    });
    registry.register('dart:core::Map::remove#1', (args) {
      return (args[0] as Map).remove(args[1]);
    });
    registry.register('dart:core::Map::addAll#1', (args) {
      (args[0] as Map).addAll(args[1] as Map);
      return null;
    });
    registry.register('dart:core::Map::clear#0', (args) {
      (args[0] as Map).clear();
      return null;
    });
    registry.register('dart:core::Map::toString#0', (args) {
      return (args[0] as Map).toString();
    });
    registry.register('dart:core::Map::putIfAbsent#2', (args) {
      final fn = args[2] as Function;
      return (args[0] as Map).putIfAbsent(
        args[1],
        () => fn(),
      );
    });
    registry.register('dart:core::Map::addEntries#1', (args) {
      (args[0] as Map).addEntries((args[1] as Iterable).cast<MapEntry>());
      return null;
    });
    // #N convention: N = total arg count excluding receiver.
    // update#3 = update(key, update, {ifAbsent}) → 3 args after receiver.
    registry.register('dart:core::Map::update#3', (args) {
      final updateFn = args[2] as Function;
      final ifAbsentFn = args.length > 3 ? args[3] as Function? : null;
      return (args[0] as Map).update(
        args[1],
        (v) => updateFn(v),
        ifAbsent: ifAbsentFn != null
            ? () => ifAbsentFn()
            : null,
      );
    });
  }
}
