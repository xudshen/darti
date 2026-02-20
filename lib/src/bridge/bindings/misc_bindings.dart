/// Registers miscellaneous dart:core host bindings:
/// Stopwatch, StackTrace, Symbol, Expando, MapEntry, Iterator.
library;

import '../host_function_registry.dart';

/// Registers all miscellaneous dart:core host function bindings.
abstract final class MiscBindings {
  static void register(HostFunctionRegistry registry) {
    _registerStopwatch(registry);
    _registerStackTrace(registry);
    _registerSymbol(registry);
    _registerExpando(registry);
    _registerMapEntry(registry);
    _registerIterator(registry);
  }

  static void _registerStopwatch(HostFunctionRegistry registry) {
    // Constructor
    registry.register('dart:core::Stopwatch::#0', (args) {
      return Stopwatch();
    });
    // Getters
    registry.register('dart:core::Stopwatch::elapsed#0', (args) {
      return (args[0] as Stopwatch).elapsed;
    });
    registry.register('dart:core::Stopwatch::elapsedMilliseconds#0', (args) {
      return (args[0] as Stopwatch).elapsedMilliseconds;
    });
    registry.register('dart:core::Stopwatch::elapsedMicroseconds#0', (args) {
      return (args[0] as Stopwatch).elapsedMicroseconds;
    });
    registry.register('dart:core::Stopwatch::elapsedTicks#0', (args) {
      return (args[0] as Stopwatch).elapsedTicks;
    });
    registry.register('dart:core::Stopwatch::frequency#0', (args) {
      return (args[0] as Stopwatch).frequency;
    });
    registry.register('dart:core::Stopwatch::isRunning#0', (args) {
      return (args[0] as Stopwatch).isRunning;
    });
    // Methods
    registry.register('dart:core::Stopwatch::start#0', (args) {
      (args[0] as Stopwatch).start();
      return null;
    });
    registry.register('dart:core::Stopwatch::stop#0', (args) {
      (args[0] as Stopwatch).stop();
      return null;
    });
    registry.register('dart:core::Stopwatch::reset#0', (args) {
      (args[0] as Stopwatch).reset();
      return null;
    });
  }

  static void _registerStackTrace(HostFunctionRegistry registry) {
    // StackTrace.current — static getter (no receiver)
    registry.register('dart:core::StackTrace::current#0', (args) {
      return StackTrace.current;
    });
    registry.register('dart:core::StackTrace::toString#0', (args) {
      return (args[0] as StackTrace).toString();
    });
  }

  static void _registerSymbol(HostFunctionRegistry registry) {
    // Constructor: Symbol(String name)
    // Kernel resolves Symbol to dart:_internal::Symbol, so register both.
    Symbol symbolFactory(List<Object?> args) => Symbol(args[0] as String);
    registry.register('dart:core::Symbol::#1', symbolFactory);
    registry.register('dart:_internal::Symbol::#1', symbolFactory);
    registry.register('dart:core::Symbol::hashCode#0', (args) {
      return (args[0] as Symbol).hashCode;
    });
    registry.register('dart:core::Symbol::==#1', (args) {
      return args[0] == args[1];
    });
    registry.register('dart:core::Symbol::toString#0', (args) {
      return args[0].toString();
    });
  }

  static void _registerExpando(HostFunctionRegistry registry) {
    // Constructor: Expando([String? name])
    registry.register('dart:core::Expando::#1', (args) {
      if (args.isNotEmpty && args[0] != null) {
        return Expando(args[0] as String);
      }
      return Expando();
    });
    registry.register('dart:core::Expando::name#0', (args) {
      return (args[0] as Expando).name;
    });
    // operator [](Object object)
    registry.register('dart:core::Expando::[]#1', (args) {
      return (args[0] as Expando)[args[1]!];
    });
    // operator []=(Object object, T? value)
    registry.register('dart:core::Expando::[]=#2', (args) {
      (args[0] as Expando)[args[1]!] = args[2];
      return args[2];
    });
    registry.register('dart:core::Expando::toString#0', (args) {
      return (args[0] as Expando).toString();
    });
  }

  static void _registerMapEntry(HostFunctionRegistry registry) {
    // Constructor: MapEntry(K key, V value)
    // Kernel may resolve the constructor to the internal factory `MapEntry::_#2`.
    MapEntry mapEntryFactory(List<Object?> args) => MapEntry(args[0], args[1]);
    registry.register('dart:core::MapEntry::#2', mapEntryFactory);
    registry.register('dart:core::MapEntry::_#2', mapEntryFactory);
    registry.register('dart:core::MapEntry::key#0', (args) {
      return (args[0] as MapEntry).key;
    });
    registry.register('dart:core::MapEntry::value#0', (args) {
      return (args[0] as MapEntry).value;
    });
    registry.register('dart:core::MapEntry::toString#0', (args) {
      return (args[0] as MapEntry).toString();
    });
  }

  static void _registerIterator(HostFunctionRegistry registry) {
    // Iterator.moveNext() and Iterator.current
    // Kernel may resolve to concrete iterator types like _ListIterator;
    // register under Iterator prefix for generic use.
    registry.register('dart:core::Iterator::moveNext#0', (args) {
      return (args[0] as Iterator).moveNext();
    });
    registry.register('dart:core::Iterator::current#0', (args) {
      return (args[0] as Iterator).current;
    });
  }
}
