/// Registers `Iterable` host bindings for the CALL_HOST pipeline.
///
/// Covers Iterable instance methods and getters that do not require
/// callbacks. Callback-based methods (map, where, fold, etc.) are
/// deferred to 5.3.3 when DarticCallbackProxy is ready.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::Iterable` host function bindings.
abstract final class IterableBindings {
  static void register(HostBindings bindings) {
    // ── Getters ──
    bindings.register('dart:core::Iterable::length#0', (args) {
      return (args[0] as Iterable).length;
    });
    bindings.register('dart:core::Iterable::isEmpty#0', (args) {
      return (args[0] as Iterable).isEmpty;
    });
    bindings.register('dart:core::Iterable::isNotEmpty#0', (args) {
      return (args[0] as Iterable).isNotEmpty;
    });
    bindings.register('dart:core::Iterable::first#0', (args) {
      return (args[0] as Iterable).first;
    });
    bindings.register('dart:core::Iterable::last#0', (args) {
      return (args[0] as Iterable).last;
    });

    // ── Methods ──
    bindings.register('dart:core::Iterable::toList#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as Iterable).toList(growable: args[1] as bool);
      }
      return (args[0] as Iterable).toList();
    });
    bindings.register('dart:core::Iterable::toSet#0', (args) {
      return (args[0] as Iterable).toSet();
    });
    bindings.register('dart:core::Iterable::contains#1', (args) {
      return (args[0] as Iterable).contains(args[1]);
    });
    bindings.register('dart:core::Iterable::join#1', (args) {
      return (args[0] as Iterable).join(
        args.length > 1 ? args[1] as String : '',
      );
    });
    bindings.register('dart:core::Iterable::elementAt#1', (args) {
      return (args[0] as Iterable).elementAt(args[1] as int);
    });
    bindings.register('dart:core::Iterable::take#1', (args) {
      return (args[0] as Iterable).take(args[1] as int);
    });
    bindings.register('dart:core::Iterable::skip#1', (args) {
      return (args[0] as Iterable).skip(args[1] as int);
    });
    bindings.register('dart:core::Iterable::toString#0', (args) {
      return (args[0] as Iterable).toString();
    });
    bindings.register('dart:core::Iterable::iterator#0', (args) {
      return (args[0] as Iterable).iterator;
    });

    // ── Callback-based methods ──

    bindings.register('dart:core::Iterable::forEach#1', (args) {
      final fn = args[1] as Function;
      for (final e in args[0] as Iterable) {
        fn(e);
      }
      return null;
    });
    bindings.register('dart:core::Iterable::map#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Iterable).map((e) => fn(e));
    });
    bindings.register('dart:core::Iterable::where#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Iterable)
          .where((e) => fn(e) as bool);
    });
    bindings.register('dart:core::Iterable::fold#2', (args) {
      final fn = args[2] as Function;
      return (args[0] as Iterable)
          .fold(args[1], (prev, e) => fn(prev, e));
    });
    bindings.register('dart:core::Iterable::any#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Iterable)
          .any((e) => fn(e) as bool);
    });
    bindings.register('dart:core::Iterable::every#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Iterable)
          .every((e) => fn(e) as bool);
    });
  }
}
