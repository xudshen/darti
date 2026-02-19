/// Registers `Set` host bindings for the CALL_HOST pipeline.
///
/// Covers Set instance methods, getters, and set operations.
/// Callback-based methods (where, map, etc.) are deferred to 5.3.3
/// when DarticCallbackProxy is ready.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::Set` host function bindings.
abstract final class SetBindings {
  static void register(HostBindings bindings) {
    // ── Getters ──
    bindings.register('dart:core::Set::length#0', (args) {
      return (args[0] as Set).length;
    });
    bindings.register('dart:core::Set::isEmpty#0', (args) {
      return (args[0] as Set).isEmpty;
    });
    bindings.register('dart:core::Set::isNotEmpty#0', (args) {
      return (args[0] as Set).isNotEmpty;
    });
    bindings.register('dart:core::Set::first#0', (args) {
      return (args[0] as Set).first;
    });
    bindings.register('dart:core::Set::last#0', (args) {
      return (args[0] as Set).last;
    });
    bindings.register('dart:core::Set::hashCode#0', (args) {
      return (args[0] as Set).hashCode;
    });

    // ── Methods ──
    bindings.register('dart:core::Set::contains#1', (args) {
      return (args[0] as Set).contains(args[1]);
    });
    bindings.register('dart:core::Set::add#1', (args) {
      return (args[0] as Set).add(args[1]);
    });
    bindings.register('dart:core::Set::addAll#1', (args) {
      (args[0] as Set).addAll(args[1] as Iterable);
      return null;
    });
    bindings.register('dart:core::Set::remove#1', (args) {
      return (args[0] as Set).remove(args[1]);
    });
    bindings.register('dart:core::Set::removeAll#1', (args) {
      (args[0] as Set).removeAll(args[1] as Iterable);
      return null;
    });
    bindings.register('dart:core::Set::retainAll#1', (args) {
      (args[0] as Set).retainAll(args[1] as Iterable);
      return null;
    });
    bindings.register('dart:core::Set::union#1', (args) {
      return (args[0] as Set).union(args[1] as Set);
    });
    bindings.register('dart:core::Set::intersection#1', (args) {
      return (args[0] as Set).intersection(args[1] as Set);
    });
    bindings.register('dart:core::Set::difference#1', (args) {
      return (args[0] as Set).difference(args[1] as Set);
    });
    bindings.register('dart:core::Set::toList#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as Set).toList(growable: args[1] as bool);
      }
      return (args[0] as Set).toList();
    });
    bindings.register('dart:core::Set::clear#0', (args) {
      (args[0] as Set).clear();
      return null;
    });
    bindings.register('dart:core::Set::toString#0', (args) {
      return (args[0] as Set).toString();
    });
    bindings.register('dart:core::Set::containsAll#1', (args) {
      return (args[0] as Set).containsAll(args[1] as Iterable);
    });
    bindings.register('dart:core::Set::lookup#1', (args) {
      return (args[0] as Set).lookup(args[1]);
    });
    bindings.register('dart:core::Set::join#1', (args) {
      return (args[0] as Set).join(args.length > 1 ? args[1] as String : '');
    });
    bindings.register('dart:core::Set::iterator#0', (args) {
      return (args[0] as Set).iterator;
    });
  }
}
