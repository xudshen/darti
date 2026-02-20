/// Registers `Iterable` host bindings for the CALL_HOST pipeline.
///
/// Covers Iterable factory constructors, instance methods and getters.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::Iterable` host function bindings.
abstract final class IterableBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Factory constructors ──

    // Iterable.generate(int count, [E Function(int)? generator])
    registry.register('dart:core::Iterable::generate#2', (args) {
      final count = args[0] as int;
      final generator = args[1] as Function;
      return Iterable.generate(count, (i) => generator(i));
    });
    registry.register('dart:core::Iterable::generate#1', (args) {
      final count = args[0] as int;
      return Iterable.generate(count);
    });

    // ── Getters ──
    registry.register('dart:core::Iterable::length#0', (args) {
      return (args[0] as Iterable).length;
    });
    registry.register('dart:core::Iterable::isEmpty#0', (args) {
      return (args[0] as Iterable).isEmpty;
    });
    registry.register('dart:core::Iterable::isNotEmpty#0', (args) {
      return (args[0] as Iterable).isNotEmpty;
    });
    registry.register('dart:core::Iterable::first#0', (args) {
      return (args[0] as Iterable).first;
    });
    registry.register('dart:core::Iterable::last#0', (args) {
      return (args[0] as Iterable).last;
    });

    // ── Methods ──
    registry.register('dart:core::Iterable::toList#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as Iterable).toList(growable: args[1] as bool);
      }
      return (args[0] as Iterable).toList();
    });
    registry.register('dart:core::Iterable::toSet#0', (args) {
      return (args[0] as Iterable).toSet();
    });
    registry.register('dart:core::Iterable::contains#1', (args) {
      return (args[0] as Iterable).contains(args[1]);
    });
    registry.register('dart:core::Iterable::join#1', (args) {
      return (args[0] as Iterable).join(
        args.length > 1 ? args[1] as String : '',
      );
    });
    registry.register('dart:core::Iterable::elementAt#1', (args) {
      return (args[0] as Iterable).elementAt(args[1] as int);
    });
    registry.register('dart:core::Iterable::take#1', (args) {
      return (args[0] as Iterable).take(args[1] as int);
    });
    registry.register('dart:core::Iterable::skip#1', (args) {
      return (args[0] as Iterable).skip(args[1] as int);
    });
    registry.register('dart:core::Iterable::toString#0', (args) {
      return (args[0] as Iterable).toString();
    });
    registry.register('dart:core::Iterable::iterator#0', (args) {
      return (args[0] as Iterable).iterator;
    });

    // ── Callback-based methods ──

    registry.register('dart:core::Iterable::forEach#1', (args) {
      final fn = args[1] as Function;
      for (final e in args[0] as Iterable) {
        fn(e);
      }
      return null;
    });
    registry.register('dart:core::Iterable::map#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Iterable).map((e) => fn(e));
    });
    registry.register('dart:core::Iterable::where#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Iterable)
          .where((e) => fn(e) as bool);
    });
    registry.register('dart:core::Iterable::fold#2', (args) {
      final fn = args[2] as Function;
      return (args[0] as Iterable)
          .fold(args[1], (prev, e) => fn(prev, e));
    });
    registry.register('dart:core::Iterable::any#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Iterable)
          .any((e) => fn(e) as bool);
    });
    registry.register('dart:core::Iterable::every#1', (args) {
      final fn = args[1] as Function;
      return (args[0] as Iterable)
          .every((e) => fn(e) as bool);
    });
    // Manual iteration: Iterable.reduce((a,b) => fn(a,b)) fails at runtime
    // because (dynamic, dynamic) => dynamic is not a subtype of (T, T) => T.
    registry.register('dart:core::Iterable::reduce#1', (args) {
      final fn = args[1] as Function;
      final iter = (args[0] as Iterable).iterator;
      if (!iter.moveNext()) {
        throw StateError('No element');
      }
      var value = iter.current;
      while (iter.moveNext()) {
        value = fn(value, iter.current);
      }
      return value;
    });
    registry.register('dart:core::Iterable::expand#1', (args) {
      return (args[0] as Iterable)
          .expand((e) => (args[1] as Function)(e) as Iterable);
    });
    registry.register('dart:core::Iterable::firstWhere#2', (args) {
      final fn = args[1] as Function;
      if (args.length > 2 && args[2] != null) {
        final orElse = args[2] as Function;
        return (args[0] as Iterable)
            .firstWhere((e) => fn(e) as bool, orElse: () => orElse());
      }
      return (args[0] as Iterable).firstWhere((e) => fn(e) as bool);
    });
    registry.register('dart:core::Iterable::lastWhere#2', (args) {
      final fn = args[1] as Function;
      if (args.length > 2 && args[2] != null) {
        final orElse = args[2] as Function;
        return (args[0] as Iterable)
            .lastWhere((e) => fn(e) as bool, orElse: () => orElse());
      }
      return (args[0] as Iterable).lastWhere((e) => fn(e) as bool);
    });
    registry.register('dart:core::Iterable::singleWhere#2', (args) {
      final fn = args[1] as Function;
      if (args.length > 2 && args[2] != null) {
        final orElse = args[2] as Function;
        return (args[0] as Iterable)
            .singleWhere((e) => fn(e) as bool, orElse: () => orElse());
      }
      return (args[0] as Iterable).singleWhere((e) => fn(e) as bool);
    });
    registry.register('dart:core::Iterable::takeWhile#1', (args) {
      return (args[0] as Iterable)
          .takeWhile((e) => (args[1] as Function)(e) as bool);
    });
    registry.register('dart:core::Iterable::skipWhile#1', (args) {
      return (args[0] as Iterable)
          .skipWhile((e) => (args[1] as Function)(e) as bool);
    });
    registry.register('dart:core::Iterable::single#0', (args) {
      return (args[0] as Iterable).single;
    });
    registry.register('dart:core::Iterable::followedBy#1', (args) {
      return (args[0] as Iterable).followedBy(args[1] as Iterable);
    });
  }
}
