/// Registers `String` host bindings for the CALL_HOST pipeline.
///
/// Covers String instance methods, getters, operators, and static methods.
/// Basic equality (==) uses specialized opcodes and is NOT handled here.
///
/// See: docs/design/04-interop.md
library;

import '../host_bindings.dart';

/// Registers all `dart:core::String` host function bindings.
abstract final class StringBindings {
  static void register(HostBindings bindings) {
    // ── Getters (symbol #0, receiver only) ──

    // String.isEmpty getter
    bindings.register('dart:core::String::isEmpty#0', (args) {
      return (args[0] as String).isEmpty;
    });

    // String.isNotEmpty getter
    bindings.register('dart:core::String::isNotEmpty#0', (args) {
      return (args[0] as String).isNotEmpty;
    });

    // String.hashCode getter
    bindings.register('dart:core::String::hashCode#0', (args) {
      return (args[0] as String).hashCode;
    });

    // String.length getter
    bindings.register('dart:core::String::length#0', (args) {
      return (args[0] as String).length;
    });

    // ── Methods with 0 params (symbol #0, receiver only) ──

    // String.toString()
    bindings.register('dart:core::String::toString#0', (args) {
      return (args[0] as String).toString();
    });

    // String.toLowerCase()
    bindings.register('dart:core::String::toLowerCase#0', (args) {
      return (args[0] as String).toLowerCase();
    });

    // String.toUpperCase()
    bindings.register('dart:core::String::toUpperCase#0', (args) {
      return (args[0] as String).toUpperCase();
    });

    // String.trim()
    bindings.register('dart:core::String::trim#0', (args) {
      return (args[0] as String).trim();
    });

    // String.trimLeft()
    bindings.register('dart:core::String::trimLeft#0', (args) {
      return (args[0] as String).trimLeft();
    });

    // String.trimRight()
    bindings.register('dart:core::String::trimRight#0', (args) {
      return (args[0] as String).trimRight();
    });

    // ── Methods with parameters ──

    // substring(int start, [int? end]) — 2 formal params
    bindings.register('dart:core::String::substring#2', (args) {
      final self = args[0] as String;
      final start = args[1] as int;
      if (args.length > 2 && args[2] != null) {
        return self.substring(start, args[2] as int);
      }
      return self.substring(start);
    });

    // indexOf(Pattern pattern, [int start = 0]) — 2 formal params
    bindings.register('dart:core::String::indexOf#2', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      if (args.length > 2) {
        return self.indexOf(pattern, args[2] as int);
      }
      return self.indexOf(pattern);
    });

    // lastIndexOf(Pattern pattern, [int? start]) — 2 formal params
    bindings.register('dart:core::String::lastIndexOf#2', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      if (args.length > 2 && args[2] != null) {
        return self.lastIndexOf(pattern, args[2] as int);
      }
      return self.lastIndexOf(pattern);
    });

    // contains(Pattern other, [int startIndex = 0]) — 2 formal params
    bindings.register('dart:core::String::contains#2', (args) {
      final self = args[0] as String;
      final other = args[1] as Pattern;
      if (args.length > 2) {
        return self.contains(other, args[2] as int);
      }
      return self.contains(other);
    });

    // startsWith(Pattern pattern, [int index = 0]) — 2 formal params
    bindings.register('dart:core::String::startsWith#2', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      if (args.length > 2) {
        return self.startsWith(pattern, args[2] as int);
      }
      return self.startsWith(pattern);
    });

    // endsWith(String other) — 1 formal param
    bindings.register('dart:core::String::endsWith#1', (args) {
      return (args[0] as String).endsWith(args[1] as String);
    });

    // replaceAll(Pattern from, String replace) — 2 formal params
    bindings.register('dart:core::String::replaceAll#2', (args) {
      return (args[0] as String)
          .replaceAll(args[1] as Pattern, args[2] as String);
    });

    // replaceFirst(Pattern from, String to, [int startIndex = 0]) — 3 formal params
    bindings.register('dart:core::String::replaceFirst#3', (args) {
      final self = args[0] as String;
      if (args.length > 3) {
        return self.replaceFirst(
            args[1] as Pattern, args[2] as String, args[3] as int);
      }
      return self.replaceFirst(args[1] as Pattern, args[2] as String);
    });

    // split(Pattern pattern) — 1 formal param
    bindings.register('dart:core::String::split#1', (args) {
      return (args[0] as String).split(args[1] as Pattern);
    });

    // compareTo(String other) — 1 formal param
    bindings.register('dart:core::String::compareTo#1', (args) {
      return (args[0] as String).compareTo(args[1] as String);
    });

    // codeUnitAt(int index) — 1 formal param
    bindings.register('dart:core::String::codeUnitAt#1', (args) {
      return (args[0] as String).codeUnitAt(args[1] as int);
    });

    // padLeft(int width, [String padding = ' ']) — 2 formal params
    bindings.register('dart:core::String::padLeft#2', (args) {
      final self = args[0] as String;
      if (args.length > 2) {
        return self.padLeft(args[1] as int, args[2] as String);
      }
      return self.padLeft(args[1] as int);
    });

    // padRight(int width, [String padding = ' ']) — 2 formal params
    bindings.register('dart:core::String::padRight#2', (args) {
      final self = args[0] as String;
      if (args.length > 2) {
        return self.padRight(args[1] as int, args[2] as String);
      }
      return self.padRight(args[1] as int);
    });

    // replaceRange(int start, int? end, String replacement) — 3 formal params
    bindings.register('dart:core::String::replaceRange#3', (args) {
      return (args[0] as String)
          .replaceRange(args[1] as int, args[2] as int?, args[3] as String);
    });

    // ── Operators ──

    // operator + (String other) — 1 formal param
    bindings.register('dart:core::String::+#1', (args) {
      return (args[0] as String) + (args[1] as String);
    });

    // operator * (int times) — 1 formal param
    bindings.register('dart:core::String::*#1', (args) {
      return (args[0] as String) * (args[1] as int);
    });

    // operator [] (int index) — 1 formal param
    bindings.register('dart:core::String::[]#1', (args) {
      return (args[0] as String)[(args[1] as int)];
    });

    // ── Static methods ──

    // String.fromCharCode(int charCode) — 1 param (no receiver)
    bindings.register('dart:core::String::fromCharCode#1', (args) {
      return String.fromCharCode(args[0] as int);
    });

    // String.fromCharCodes(Iterable<int> charCodes, [int start = 0, int? end])
    // — 3 formal params (no receiver)
    bindings.register('dart:core::String::fromCharCodes#3', (args) {
      final codes = (args[0] as Iterable).cast<int>();
      if (args.length > 1 && args[1] != null) {
        final start = args[1] as int;
        if (args.length > 2 && args[2] != null) {
          return String.fromCharCodes(codes, start, args[2] as int);
        }
        return String.fromCharCodes(codes, start);
      }
      return String.fromCharCodes(codes);
    });
  }
}
