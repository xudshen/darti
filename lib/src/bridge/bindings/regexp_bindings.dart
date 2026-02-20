/// Registers `RegExp`, `Match`, and `RegExpMatch` host bindings for the
/// CALL_HOST pipeline.
///
/// Covers RegExp constructor, instance getters, methods, and the
/// Match / RegExpMatch interfaces for accessing match results.
///
/// See: docs/design/04-interop.md
library;

import '../host_function_registry.dart';

/// Registers all RegExp, Match, and RegExpMatch host function bindings.
abstract final class RegExpBindings {
  static void register(HostFunctionRegistry registry) {
    _registerRegExp(registry);
    _registerMatch(registry);
    _registerRegExpMatch(registry);
  }

  static void _registerRegExp(HostFunctionRegistry registry) {
    // ── Constructor ──
    // RegExp(String source, {bool multiLine, bool caseSensitive, bool unicode, bool dotAll})
    // Kernel passes 5 args: source + 4 named bools
    registry.register('dart:core::RegExp::#5', (args) {
      return RegExp(
        args[0] as String,
        multiLine:
            args.length > 1 && args[1] != null ? args[1] as bool : false,
        caseSensitive:
            args.length > 2 && args[2] != null ? args[2] as bool : true,
        unicode:
            args.length > 3 && args[3] != null ? args[3] as bool : false,
        dotAll: args.length > 4 && args[4] != null ? args[4] as bool : false,
      );
    });

    // ── Getters ──
    registry.register('dart:core::RegExp::pattern#0', (args) {
      return (args[0] as RegExp).pattern;
    });
    registry.register('dart:core::RegExp::isMultiLine#0', (args) {
      return (args[0] as RegExp).isMultiLine;
    });
    registry.register('dart:core::RegExp::isCaseSensitive#0', (args) {
      return (args[0] as RegExp).isCaseSensitive;
    });
    registry.register('dart:core::RegExp::isUnicode#0', (args) {
      return (args[0] as RegExp).isUnicode;
    });
    registry.register('dart:core::RegExp::isDotAll#0', (args) {
      return (args[0] as RegExp).isDotAll;
    });
    registry.register('dart:core::RegExp::hashCode#0', (args) {
      return (args[0] as RegExp).hashCode;
    });

    // ── Methods ──
    registry.register('dart:core::RegExp::hasMatch#1', (args) {
      return (args[0] as RegExp).hasMatch(args[1] as String);
    });
    registry.register('dart:core::RegExp::firstMatch#1', (args) {
      return (args[0] as RegExp).firstMatch(args[1] as String);
    });
    registry.register('dart:core::RegExp::allMatches#2', (args) {
      final re = args[0] as RegExp;
      final str = args[1] as String;
      if (args.length > 2 && args[2] != null) {
        return re.allMatches(str, args[2] as int);
      }
      return re.allMatches(str);
    });
    registry.register('dart:core::RegExp::stringMatch#1', (args) {
      return (args[0] as RegExp).stringMatch(args[1] as String);
    });
    registry.register('dart:core::RegExp::matchAsPrefix#2', (args) {
      final re = args[0] as RegExp;
      final str = args[1] as String;
      if (args.length > 2 && args[2] != null) {
        return re.matchAsPrefix(str, args[2] as int);
      }
      return re.matchAsPrefix(str);
    });
    registry.register('dart:core::RegExp::toString#0', (args) {
      return (args[0] as RegExp).toString();
    });
  }

  static void _registerMatch(HostFunctionRegistry registry) {
    // ── Match getters ──
    registry.register('dart:core::Match::start#0', (args) {
      return (args[0] as Match).start;
    });
    registry.register('dart:core::Match::end#0', (args) {
      return (args[0] as Match).end;
    });
    registry.register('dart:core::Match::input#0', (args) {
      return (args[0] as Match).input;
    });
    registry.register('dart:core::Match::groupCount#0', (args) {
      return (args[0] as Match).groupCount;
    });
    registry.register('dart:core::Match::pattern#0', (args) {
      return (args[0] as Match).pattern;
    });

    // ── Match methods ──
    registry.register('dart:core::Match::group#1', (args) {
      return (args[0] as Match).group(args[1] as int);
    });
    registry.register('dart:core::Match::[]#1', (args) {
      return (args[0] as Match)[args[1] as int];
    });
    registry.register('dart:core::Match::groups#1', (args) {
      return (args[0] as Match).groups((args[1] as List).cast<int>());
    });
  }

  static void _registerRegExpMatch(HostFunctionRegistry registry) {
    // RegExpMatch inherits from Match, so also register under RegExpMatch
    // prefix. Kernel may resolve to RegExpMatch or _RegExpMatch depending
    // on the dispatch target.

    // ── Inherited Match getters ──
    registry.register('dart:core::RegExpMatch::start#0', (args) {
      return (args[0] as Match).start;
    });
    registry.register('dart:core::RegExpMatch::end#0', (args) {
      return (args[0] as Match).end;
    });
    registry.register('dart:core::RegExpMatch::input#0', (args) {
      return (args[0] as Match).input;
    });
    registry.register('dart:core::RegExpMatch::groupCount#0', (args) {
      return (args[0] as Match).groupCount;
    });
    registry.register('dart:core::RegExpMatch::pattern#0', (args) {
      return (args[0] as Match).pattern;
    });

    // ── Inherited Match methods ──
    registry.register('dart:core::RegExpMatch::group#1', (args) {
      return (args[0] as Match).group(args[1] as int);
    });
    registry.register('dart:core::RegExpMatch::[]#1', (args) {
      return (args[0] as Match)[args[1] as int];
    });
    registry.register('dart:core::RegExpMatch::groups#1', (args) {
      return (args[0] as Match).groups((args[1] as List).cast<int>());
    });

    // ── RegExpMatch-specific methods ──
    registry.register('dart:core::RegExpMatch::namedGroup#1', (args) {
      return (args[0] as RegExpMatch).namedGroup(args[1] as String);
    });
    registry.register('dart:core::RegExpMatch::groupNames#0', (args) {
      return (args[0] as RegExpMatch).groupNames;
    });
  }
}
