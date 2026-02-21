/// Registers `Set` host bindings for the CALL_HOST pipeline.
///
/// Covers Set instance methods, getters, set operations, and callback methods.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::Set` host function bindings.
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

    // _Set.cast<R>() → Set<R>
    registry.register('dart:_compact_hash::_Set::cast#0', (args) {
      return (args[0] as Set).cast();
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
    // set.cast<R>() → Set<R>
    registry.register('dart:core::Set::cast#0', (args) {
      return (args[0] as Set).cast();
    });
    registry.register('dart:core::Set::symmetricDifference#1', (args) {
      final a = args[0] as Set;
      final b = args[1] as Set;
      return a.union(b).difference(a.intersection(b));
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

    // ── Callback methods ──

    registry.register('dart:core::Set::forEach#1', (args) {
      final fn = args[1] as Function;
      for (final e in args[0] as Set) {
        fn(e);
      }
      return null;
    });
    registry.register('dart:core::Set::map#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Set).map((e) => fn(e));
    });
    registry.register('dart:core::Set::where#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Set).where((e) => fn(e) as bool);
    });
    registry.register('dart:core::Set::any#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Set).any((e) => fn(e) as bool);
    });
    registry.register('dart:core::Set::every#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Set).every((e) => fn(e) as bool);
    });
    registry.register('dart:core::Set::fold#2', (args) {
      final fn = args[2] as Function;
      return (args[0] as Set).fold(args[1], (prev, e) => fn(prev, e));
    });
    // Manual iteration: Set.reduce((a,b) => fn(a,b)) fails at runtime
    // because (dynamic, dynamic) => dynamic is not a subtype of (T, T) => T.
    registry.register('dart:core::Set::reduce#1', (args) {
      final fn = args[1] as Function;
      final set = args[0] as Set;
      final iter = set.iterator;
      if (!iter.moveNext()) {
        throw StateError('No element');
      }
      var value = iter.current;
      while (iter.moveNext()) {
        value = fn(value, iter.current);
      }
      return value;
    });
    registry.register('dart:core::Set::expand#1', (args) {
      return (args[0] as Set)
          .expand((e) => (args[1] as Function)(e) as Iterable);
    });
    // Manual iteration for firstWhere/lastWhere/singleWhere: delegating to
    // Set's typed methods fails because (dynamic) => dynamic is not a subtype
    // of (T) => bool when invoked through dynamic dispatch.
    registry.register('dart:core::Set::firstWhere#2', (args) {
      final fn = args[1] as Function;
      final orElse =
          (args.length > 2 && args[2] != null) ? args[2] as Function : null;
      for (final e in args[0] as Set) {
        if (fn(e) as bool) return e;
      }
      if (orElse != null) return orElse();
      throw StateError('No element');
    });
    registry.register('dart:core::Set::lastWhere#2', (args) {
      final fn = args[1] as Function;
      final orElse =
          (args.length > 2 && args[2] != null) ? args[2] as Function : null;
      Object? result;
      var found = false;
      for (final e in args[0] as Set) {
        if (fn(e) as bool) {
          result = e;
          found = true;
        }
      }
      if (found) return result;
      if (orElse != null) return orElse();
      throw StateError('No element');
    });
    registry.register('dart:core::Set::singleWhere#2', (args) {
      final fn = args[1] as Function;
      final orElse =
          (args.length > 2 && args[2] != null) ? args[2] as Function : null;
      Object? result;
      var found = false;
      for (final e in args[0] as Set) {
        if (fn(e) as bool) {
          if (found) throw StateError('Too many elements');
          result = e;
          found = true;
        }
      }
      if (found) return result;
      if (orElse != null) return orElse();
      throw StateError('No element');
    });
    registry.register('dart:core::Set::takeWhile#1', (args) {
      return (args[0] as Set)
          .takeWhile((e) => (args[1] as Function)(e) as bool);
    });
    registry.register('dart:core::Set::skipWhile#1', (args) {
      return (args[0] as Set)
          .skipWhile((e) => (args[1] as Function)(e) as bool);
    });
    registry.register('dart:core::Set::toSet#0', (args) {
      return (args[0] as Set).toSet();
    });
    registry.register('dart:core::Set::elementAt#1', (args) {
      return (args[0] as Set).elementAt(args[1] as int);
    });
    registry.register('dart:core::Set::take#1', (args) {
      return (args[0] as Set).take(args[1] as int);
    });
    registry.register('dart:core::Set::skip#1', (args) {
      return (args[0] as Set).skip(args[1] as int);
    });
    registry.register('dart:core::Set::single#0', (args) {
      return (args[0] as Set).single;
    });
  }
}
