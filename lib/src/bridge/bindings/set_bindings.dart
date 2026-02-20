/// Registers `Set` host registry for the CALL_HOST pipeline.
///
/// Covers Set instance methods, getters, and set operations.
/// Callback-based methods (where, map, etc.) are deferred to 5.3.3
/// when DarticCallbackProxy is ready.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::Set` host function registry.
abstract final class SetBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Internal _Set factories ──
    // Dart SDK lowers set literals {a, b, c} to _Set()..add(a)..add(b)..add(c).
    // We must register the _Set constructor from dart:_compact_hash.
    registry.register('dart:_compact_hash::_Set::#0', (args) {
      return <dynamic>{};
    });

    // _Set instance methods (kernel may resolve to _Set rather than Set)
    registry.register('dart:_compact_hash::_Set::add#1', (args) {
      return (args[0] as Set).add(args[1]);
    });

    // ── Getters ──
    registry.register('dart:core::Set::length#0', (args) {
      return (args[0] as Set).length;
    });
    registry.register('dart:core::Set::isEmpty#0', (args) {
      return (args[0] as Set).isEmpty;
    });
    registry.register('dart:core::Set::isNotEmpty#0', (args) {
      return (args[0] as Set).isNotEmpty;
    });
    registry.register('dart:core::Set::first#0', (args) {
      return (args[0] as Set).first;
    });
    registry.register('dart:core::Set::last#0', (args) {
      return (args[0] as Set).last;
    });
    registry.register('dart:core::Set::hashCode#0', (args) {
      return (args[0] as Set).hashCode;
    });

    // ── Methods ──
    registry.register('dart:core::Set::contains#1', (args) {
      return (args[0] as Set).contains(args[1]);
    });
    registry.register('dart:core::Set::add#1', (args) {
      return (args[0] as Set).add(args[1]);
    });
    registry.register('dart:core::Set::addAll#1', (args) {
      (args[0] as Set).addAll(args[1] as Iterable);
      return null;
    });
    registry.register('dart:core::Set::remove#1', (args) {
      return (args[0] as Set).remove(args[1]);
    });
    registry.register('dart:core::Set::removeAll#1', (args) {
      (args[0] as Set).removeAll(args[1] as Iterable);
      return null;
    });
    registry.register('dart:core::Set::retainAll#1', (args) {
      (args[0] as Set).retainAll(args[1] as Iterable);
      return null;
    });
    registry.register('dart:core::Set::union#1', (args) {
      return (args[0] as Set).union(args[1] as Set);
    });
    registry.register('dart:core::Set::intersection#1', (args) {
      return (args[0] as Set).intersection(args[1] as Set);
    });
    registry.register('dart:core::Set::difference#1', (args) {
      return (args[0] as Set).difference(args[1] as Set);
    });
    registry.register('dart:core::Set::toList#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as Set).toList(growable: args[1] as bool);
      }
      return (args[0] as Set).toList();
    });
    registry.register('dart:core::Set::clear#0', (args) {
      (args[0] as Set).clear();
      return null;
    });
    registry.register('dart:core::Set::toString#0', (args) {
      return (args[0] as Set).toString();
    });
    registry.register('dart:core::Set::containsAll#1', (args) {
      return (args[0] as Set).containsAll(args[1] as Iterable);
    });
    registry.register('dart:core::Set::lookup#1', (args) {
      return (args[0] as Set).lookup(args[1]);
    });
    registry.register('dart:core::Set::join#1', (args) {
      return (args[0] as Set).join(args.length > 1 ? args[1] as String : '');
    });
    registry.register('dart:core::Set::iterator#0', (args) {
      return (args[0] as Set).iterator;
    });
  }
}
