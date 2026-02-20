/// Dynamic dispatch for host (VM-native) objects.
///
/// When the interpreter encounters a dynamic property access or method call
/// on a non-DarticObject receiver (e.g., `dynamic x = [1,2]; x.length`),
/// the [HostDispatchRegistry] resolves the receiver's type to a dispatcher,
/// which routes by property/method name through the existing [HostFunctionRegistry].
///
/// See: docs/design/04-interop.md "HostClassWrapper"
library;

import 'host_function_registry.dart';

/// Abstract base for host class property/method dispatch.
///
/// Each implementation handles one or more host types. Phase 7's
/// BridgeGenerator will produce hardcoded-switch subclasses; the current
/// [BindingLookupDispatcher] uses name-based HostFunctionRegistry lookup.
abstract class HostDispatcher {
  /// Gets a named property from [host] (getter dispatch).
  Object? getProperty(Object host, String name);

  /// Invokes a named method on [host] with [args] (method dispatch).
  Object? invokeMethod(Object host, String name, List<Object?> args);
}

/// [HostDispatcher] backed by HostFunctionRegistry name lookup.
///
/// Constructs binding keys from a list of class name prefixes and looks up
/// methods/getters in the existing HostFunctionRegistry registry. This avoids
/// duplicating dispatch logic that's already in the binding registrations.
class BindingLookupDispatcher implements HostDispatcher {
  BindingLookupDispatcher(this._registry, this._prefixes);

  final HostFunctionRegistry _registry;

  /// Binding key prefixes to try, e.g. `['dart:core::List::', 'dart:core::_GrowableList::']`.
  /// Tried in order; first match wins.
  final List<String> _prefixes;

  /// Sentinel used to distinguish "method not found" from "method returned null".
  static const notFound = #_bindingLookupDispatcherNotFound;

  @override
  Object? getProperty(Object host, String name) {
    for (final prefix in _prefixes) {
      final id = _registry.lookupByName('$prefix$name#0');
      if (id >= 0) return _registry.invoke(id, [host]);
    }
    return notFound;
  }

  @override
  Object? invokeMethod(Object host, String name, List<Object?> args) {
    // Try exact arg count first, then widen by up to 3 to cover optional
    // parameters (e.g., String.contains has 2 formals but is often called
    // with 1 arg). The binding functions already guard missing optionals.
    for (final prefix in _prefixes) {
      for (var arity = args.length; arity <= args.length + 3; arity++) {
        final id = _registry.lookupByName('$prefix$name#$arity');
        if (id >= 0) return _registry.invoke(id, [host, ...args]);
      }
    }
    return notFound;
  }
}

/// [HostDispatcher] for [Invocation] objects passed to noSuchMethod.
///
/// Dispatches property access directly without going through HostFunctionRegistry,
/// since Invocation is a core Dart abstract class with known properties.
class _InvocationDispatcher implements HostDispatcher {
  @override
  Object? getProperty(Object host, String name) {
    final inv = host as Invocation;
    return switch (name) {
      'memberName' => inv.memberName,
      'positionalArguments' => inv.positionalArguments,
      'namedArguments' => inv.namedArguments,
      'typeArguments' => inv.typeArguments,
      'isMethod' => inv.isMethod,
      'isGetter' => inv.isGetter,
      'isSetter' => inv.isSetter,
      _ => BindingLookupDispatcher.notFound,
    };
  }

  @override
  Object? invokeMethod(Object host, String name, List<Object?> args) {
    return BindingLookupDispatcher.notFound;
  }
}

/// Registry mapping receiver types to [HostDispatcher] instances.
///
/// Uses `is` checks for reliable subtype matching (e.g., `_GrowableList is List`).
class HostDispatchRegistry {
  HostDispatchRegistry(HostFunctionRegistry registry)
      : _list = BindingLookupDispatcher(registry, [
          'dart:core::List::',
          'dart:core::_GrowableList::',
          'dart:core::Iterable::',
        ]),
        _map = BindingLookupDispatcher(registry, [
          'dart:core::Map::',
          'dart:collection::LinkedHashMap::',
        ]),
        _set = BindingLookupDispatcher(registry, [
          'dart:core::Set::',
          'dart:_compact_hash::_Set::',
          'dart:core::Iterable::',
        ]),
        _string = BindingLookupDispatcher(registry, [
          'dart:core::String::',
        ]),
        _int = BindingLookupDispatcher(registry, [
          'dart:core::int::',
          'dart:core::num::',
        ]),
        _double = BindingLookupDispatcher(registry, [
          'dart:core::double::',
          'dart:core::num::',
        ]),
        _bool = BindingLookupDispatcher(registry, [
          'dart:core::bool::',
        ]),
        _iterable = BindingLookupDispatcher(registry, [
          'dart:core::Iterable::',
        ]),
        _duration = BindingLookupDispatcher(registry, [
          'dart:core::Duration::',
        ]);

  final HostDispatcher _list;
  final HostDispatcher _map;
  final HostDispatcher _set;
  final HostDispatcher _string;
  final HostDispatcher _int;
  final HostDispatcher _double;
  final HostDispatcher _bool;
  final HostDispatcher _iterable;
  final HostDispatcher _duration;
  final HostDispatcher _invocation = _InvocationDispatcher();

  /// Looks up the [HostDispatcher] for [receiver] based on its runtime type.
  ///
  /// Returns null if no dispatcher is registered for the receiver's type.
  HostDispatcher? lookup(Object receiver) {
    // Order matters: check concrete types before interfaces.
    if (receiver is String) return _string;
    if (receiver is int) return _int;
    if (receiver is double) return _double;
    if (receiver is bool) return _bool;
    if (receiver is List) return _list;
    if (receiver is Map) return _map;
    if (receiver is Set) return _set;
    if (receiver is Duration) return _duration;
    if (receiver is Iterable) return _iterable;
    if (receiver is Invocation) return _invocation;
    return null;
  }
}
