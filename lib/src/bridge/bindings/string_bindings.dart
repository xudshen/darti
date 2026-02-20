/// Registers `String` host bindings for the CALL_HOST pipeline.
///
/// Covers String instance methods, getters, operators, and static methods.
/// Basic equality (==) uses specialized opcodes and is NOT handled here.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all `dart:core::String` host function bindings.
abstract final class StringBindings {
  static void register(HostFunctionRegistry registry) {
    // ── Getters (symbol #0, receiver only) ──

    // String.isEmpty getter
    registry.register('dart:core::String::isEmpty#0', (args) {
      return (args[0] as String).isEmpty;
    });

    // String.isNotEmpty getter
    registry.register('dart:core::String::isNotEmpty#0', (args) {
      return (args[0] as String).isNotEmpty;
    });

    // String.hashCode getter
    registry.register('dart:core::String::hashCode#0', (args) {
      return (args[0] as String).hashCode;
    });

    // String.length getter
    registry.register('dart:core::String::length#0', (args) {
      return (args[0] as String).length;
    });

    // String.codeUnits getter
    registry.register('dart:core::String::codeUnits#0', (args) {
      return (args[0] as String).codeUnits;
    });

    // ── Methods with 0 params (symbol #0, receiver only) ──

    // String.toString()
    registry.register('dart:core::String::toString#0', (args) {
      return (args[0] as String).toString();
    });

    // String.toLowerCase()
    registry.register('dart:core::String::toLowerCase#0', (args) {
      return (args[0] as String).toLowerCase();
    });

    // String.toUpperCase()
    registry.register('dart:core::String::toUpperCase#0', (args) {
      return (args[0] as String).toUpperCase();
    });

    // String.trim()
    registry.register('dart:core::String::trim#0', (args) {
      return (args[0] as String).trim();
    });

    // String.trimLeft()
    registry.register('dart:core::String::trimLeft#0', (args) {
      return (args[0] as String).trimLeft();
    });

    // String.trimRight()
    registry.register('dart:core::String::trimRight#0', (args) {
      return (args[0] as String).trimRight();
    });

    // ── Methods with parameters ──

    // substring(int start, [int? end]) — 2 formal params
    registry.register('dart:core::String::substring#2', (args) {
      final self = args[0] as String;
      final start = args[1] as int;
      if (args.length > 2 && args[2] != null) {
        return self.substring(start, args[2] as int);
      }
      return self.substring(start);
    });

    // indexOf(Pattern pattern, [int start = 0]) — 2 formal params
    registry.register('dart:core::String::indexOf#2', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      if (args.length > 2) {
        return self.indexOf(pattern, args[2] as int);
      }
      return self.indexOf(pattern);
    });

    // lastIndexOf(Pattern pattern, [int? start]) — 2 formal params
    registry.register('dart:core::String::lastIndexOf#2', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      if (args.length > 2 && args[2] != null) {
        return self.lastIndexOf(pattern, args[2] as int);
      }
      return self.lastIndexOf(pattern);
    });

    // contains(Pattern other, [int startIndex = 0]) — 2 formal params
    registry.register('dart:core::String::contains#2', (args) {
      final self = args[0] as String;
      final other = args[1] as Pattern;
      if (args.length > 2) {
        return self.contains(other, args[2] as int);
      }
      return self.contains(other);
    });

    // startsWith(Pattern pattern, [int index = 0]) — 2 formal params
    registry.register('dart:core::String::startsWith#2', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      if (args.length > 2) {
        return self.startsWith(pattern, args[2] as int);
      }
      return self.startsWith(pattern);
    });

    // endsWith(String other) — 1 formal param
    registry.register('dart:core::String::endsWith#1', (args) {
      return (args[0] as String).endsWith(args[1] as String);
    });

    // replaceAll(Pattern from, String replace) — 2 formal params
    registry.register('dart:core::String::replaceAll#2', (args) {
      return (args[0] as String)
          .replaceAll(args[1] as Pattern, args[2] as String);
    });

    // replaceFirst(Pattern from, String to, [int startIndex = 0]) — 3 formal params
    registry.register('dart:core::String::replaceFirst#3', (args) {
      final self = args[0] as String;
      if (args.length > 3) {
        return self.replaceFirst(
            args[1] as Pattern, args[2] as String, args[3] as int);
      }
      return self.replaceFirst(args[1] as Pattern, args[2] as String);
    });

    // split(Pattern pattern) — 1 formal param
    registry.register('dart:core::String::split#1', (args) {
      return (args[0] as String).split(args[1] as Pattern);
    });

    // compareTo(String other) — 1 formal param
    registry.register('dart:core::String::compareTo#1', (args) {
      return (args[0] as String).compareTo(args[1] as String);
    });

    // codeUnitAt(int index) — 1 formal param
    registry.register('dart:core::String::codeUnitAt#1', (args) {
      return (args[0] as String).codeUnitAt(args[1] as int);
    });

    // padLeft(int width, [String padding = ' ']) — 2 formal params
    registry.register('dart:core::String::padLeft#2', (args) {
      final self = args[0] as String;
      if (args.length > 2) {
        return self.padLeft(args[1] as int, args[2] as String);
      }
      return self.padLeft(args[1] as int);
    });

    // padRight(int width, [String padding = ' ']) — 2 formal params
    registry.register('dart:core::String::padRight#2', (args) {
      final self = args[0] as String;
      if (args.length > 2) {
        return self.padRight(args[1] as int, args[2] as String);
      }
      return self.padRight(args[1] as int);
    });

    // replaceRange(int start, int? end, String replacement) — 3 formal params
    registry.register('dart:core::String::replaceRange#3', (args) {
      return (args[0] as String)
          .replaceRange(args[1] as int, args[2] as int?, args[3] as String);
    });

    // ── Callback methods (depend on Match/Runes) ──

    // replaceAllMapped(Pattern from, String Function(Match) replace) — 2 params
    registry.register('dart:core::String::replaceAllMapped#2', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      final fn = args[2] as Function;
      return self.replaceAllMapped(pattern, (m) => fn(m) as String);
    });

    // replaceFirstMapped(Pattern from, String Function(Match) replace,
    //                    [int startIndex = 0]) — 3 params
    registry.register('dart:core::String::replaceFirstMapped#3', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      final fn = args[2] as Function;
      final start =
          (args.length > 3 && args[3] != null) ? args[3] as int : 0;
      return self.replaceFirstMapped(pattern, (m) => fn(m) as String, start);
    });

    // splitMapJoin(Pattern, {onMatch, onNonMatch}) — 3 params
    registry.register('dart:core::String::splitMapJoin#3', (args) {
      final self = args[0] as String;
      final pattern = args[1] as Pattern;
      final onMatch = args.length > 2 ? args[2] as Function? : null;
      final onNonMatch = args.length > 3 ? args[3] as Function? : null;
      return self.splitMapJoin(
        pattern,
        onMatch: onMatch != null ? (m) => onMatch(m) as String : null,
        onNonMatch:
            onNonMatch != null ? (s) => onNonMatch(s) as String : null,
      );
    });

    // allMatches(String string, [int start = 0]) — Pattern interface, 2 params
    // Kernel may resolve to either String:: or Pattern:: prefix.
    allMatches(List<Object?> args) {
      final self = args[0] as String;
      final string = args[1] as String;
      final start =
          (args.length > 2 && args[2] != null) ? args[2] as int : 0;
      return self.allMatches(string, start);
    }

    registry.register('dart:core::String::allMatches#2', allMatches);
    registry.register('dart:core::Pattern::allMatches#2', allMatches);

    // matchAsPrefix(String string, [int start = 0]) — Pattern interface, 2 params
    matchAsPrefix(List<Object?> args) {
      final self = args[0] as String;
      final string = args[1] as String;
      final start =
          (args.length > 2 && args[2] != null) ? args[2] as int : 0;
      return self.matchAsPrefix(string, start);
    }

    registry.register('dart:core::String::matchAsPrefix#2', matchAsPrefix);
    registry.register('dart:core::Pattern::matchAsPrefix#2', matchAsPrefix);

    // runes getter — returns Runes
    registry.register('dart:core::String::runes#0', (args) {
      return (args[0] as String).runes;
    });

    // ── Operators ──

    // operator + (String other) — 1 formal param
    registry.register('dart:core::String::+#1', (args) {
      return (args[0] as String) + (args[1] as String);
    });

    // operator * (int times) — 1 formal param
    registry.register('dart:core::String::*#1', (args) {
      return (args[0] as String) * (args[1] as int);
    });

    // operator [] (int index) — 1 formal param
    registry.register('dart:core::String::[]#1', (args) {
      return (args[0] as String)[(args[1] as int)];
    });

    // ── Static methods ──

    // String.fromCharCode(int charCode) — 1 param (no receiver)
    registry.register('dart:core::String::fromCharCode#1', (args) {
      return String.fromCharCode(args[0] as int);
    });

    // String.fromCharCodes(Iterable<int> charCodes, [int start = 0, int? end])
    // — 3 formal params (no receiver)
    registry.register('dart:core::String::fromCharCodes#3', (args) {
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
