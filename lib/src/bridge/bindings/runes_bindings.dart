/// Registers `Runes` and `RuneIterator` host bindings for the CALL_HOST pipeline.
library;

import '../host_function_registry.dart';

/// Registers all Runes and RuneIterator host function bindings.
abstract final class RunesBindings {
  static void register(HostFunctionRegistry registry) {
    _registerRunes(registry);
    _registerRuneIterator(registry);
  }

  static void _registerRunes(HostFunctionRegistry registry) {
    // Constructor: Runes(String string)
    registry.register('dart:core::Runes::#1', (args) {
      return (args[0] as String).runes;
    });

    // Getters
    registry.register('dart:core::Runes::length#0', (args) {
      return (args[0] as Runes).length;
    });
    registry.register('dart:core::Runes::first#0', (args) {
      return (args[0] as Runes).first;
    });
    registry.register('dart:core::Runes::last#0', (args) {
      return (args[0] as Runes).last;
    });
    registry.register('dart:core::Runes::isEmpty#0', (args) {
      return (args[0] as Runes).isEmpty;
    });
    registry.register('dart:core::Runes::isNotEmpty#0', (args) {
      return (args[0] as Runes).isNotEmpty;
    });
    registry.register('dart:core::Runes::hashCode#0', (args) {
      return (args[0] as Runes).hashCode;
    });
    registry.register('dart:core::Runes::iterator#0', (args) {
      return (args[0] as Runes).iterator;
    });

    // Methods
    registry.register('dart:core::Runes::elementAt#1', (args) {
      return (args[0] as Runes).elementAt(args[1] as int);
    });
    registry.register('dart:core::Runes::contains#1', (args) {
      return (args[0] as Runes).contains(args[1]);
    });
    registry.register('dart:core::Runes::toList#1', (args) {
      if (args.length > 1 && args[1] != null) {
        return (args[0] as Runes).toList(growable: args[1] as bool);
      }
      return (args[0] as Runes).toList();
    });
    registry.register('dart:core::Runes::toString#0', (args) {
      return (args[0] as Runes).toString();
    });
    registry.register('dart:core::Runes::single#0', (args) {
      return (args[0] as Runes).single;
    });
    registry.register('dart:core::Runes::join#1', (args) {
      return (args[0] as Runes).join(args.length > 1 ? args[1] as String : '');
    });
  }

  static void _registerRuneIterator(HostFunctionRegistry registry) {
    // RuneIterator getters
    registry.register('dart:core::RuneIterator::current#0', (args) {
      return (args[0] as RuneIterator).current;
    });
    registry.register('dart:core::RuneIterator::currentSize#0', (args) {
      return (args[0] as RuneIterator).currentSize;
    });
    registry.register('dart:core::RuneIterator::currentAsString#0', (args) {
      return (args[0] as RuneIterator).currentAsString;
    });
    registry.register('dart:core::RuneIterator::rawIndex#0', (args) {
      return (args[0] as RuneIterator).rawIndex;
    });

    // RuneIterator methods
    registry.register('dart:core::RuneIterator::moveNext#0', (args) {
      return (args[0] as RuneIterator).moveNext();
    });
    registry.register('dart:core::RuneIterator::reset#1', (args) {
      if (args.length > 1 && args[1] != null) {
        (args[0] as RuneIterator).reset(args[1] as int);
      } else {
        (args[0] as RuneIterator).reset();
      }
      return null;
    });
    registry.register('dart:core::RuneIterator::movePrevious#0', (args) {
      return (args[0] as RuneIterator).movePrevious();
    });
  }
}
