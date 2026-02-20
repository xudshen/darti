import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_function_registry.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  late HostFunctionRegistry registry;

  setUp(() {
    registry = HostFunctionRegistry();
    CoreBindings.registerAll(registry);
  });

  Object? invoke(String name, List<Object?> args) {
    final id = registry.lookupByName(name);
    if (id == -1) fail('Binding not found: $name');
    return registry.invoke(id, args);
  }

  // ── Registration tests ──

  group('registration', () {
    test('RegExp constructor is registered', () {
      expect(registry.lookupByName('dart:core::RegExp::#5'), isNot(-1));
    });

    test('RegExp getters are registered', () {
      expect(registry.lookupByName('dart:core::RegExp::pattern#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExp::isMultiLine#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::RegExp::isCaseSensitive#0'),
          isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExp::isUnicode#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExp::isDotAll#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExp::hashCode#0'), isNot(-1));
    });

    test('RegExp methods are registered', () {
      expect(
          registry.lookupByName('dart:core::RegExp::hasMatch#1'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExp::firstMatch#1'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExp::allMatches#2'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExp::stringMatch#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::RegExp::matchAsPrefix#2'),
          isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExp::toString#0'), isNot(-1));
    });

    test('Match getters and methods are registered', () {
      expect(registry.lookupByName('dart:core::Match::start#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Match::end#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Match::input#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::Match::groupCount#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Match::pattern#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::Match::group#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Match::[]#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::Match::groups#1'), isNot(-1));
    });

    test('RegExpMatch getters and methods are registered', () {
      expect(
          registry.lookupByName('dart:core::RegExpMatch::start#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::RegExpMatch::end#0'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExpMatch::input#0'), isNot(-1));
      expect(registry.lookupByName('dart:core::RegExpMatch::groupCount#0'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::RegExpMatch::pattern#0'),
          isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExpMatch::group#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::RegExpMatch::[]#1'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::RegExpMatch::groups#1'), isNot(-1));
      expect(registry.lookupByName('dart:core::RegExpMatch::namedGroup#1'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::RegExpMatch::groupNames#0'),
          isNot(-1));
    });
  });

  // ── RegExp constructor + getters ──

  group('RegExp constructor + getters', () {
    test('constructor with source only', () {
      final re = invoke('dart:core::RegExp::#5', [r'\d+']) as RegExp;
      expect(re.pattern, r'\d+');
      expect(re.isMultiLine, false);
      expect(re.isCaseSensitive, true);
      expect(re.isUnicode, false);
      expect(re.isDotAll, false);
    });

    test('constructor with all options', () {
      final re = invoke(
          'dart:core::RegExp::#5', [r'\d+', true, false, true, true]) as RegExp;
      expect(re.pattern, r'\d+');
      expect(re.isMultiLine, true);
      expect(re.isCaseSensitive, false);
      expect(re.isUnicode, true);
      expect(re.isDotAll, true);
    });

    test('constructor with null options uses defaults', () {
      final re = invoke(
          'dart:core::RegExp::#5', [r'\d+', null, null, null, null]) as RegExp;
      expect(re.isMultiLine, false);
      expect(re.isCaseSensitive, true);
      expect(re.isUnicode, false);
      expect(re.isDotAll, false);
    });

    test('pattern getter', () {
      final re = RegExp(r'hello');
      expect(invoke('dart:core::RegExp::pattern#0', [re]), r'hello');
    });

    test('isMultiLine getter', () {
      final re = RegExp(r'hello', multiLine: true);
      expect(invoke('dart:core::RegExp::isMultiLine#0', [re]), true);
    });

    test('isCaseSensitive getter', () {
      final re = RegExp(r'hello', caseSensitive: false);
      expect(invoke('dart:core::RegExp::isCaseSensitive#0', [re]), false);
    });

    test('isUnicode getter', () {
      final re = RegExp(r'hello', unicode: true);
      expect(invoke('dart:core::RegExp::isUnicode#0', [re]), true);
    });

    test('isDotAll getter', () {
      final re = RegExp(r'hello', dotAll: true);
      expect(invoke('dart:core::RegExp::isDotAll#0', [re]), true);
    });

    test('hashCode getter returns int', () {
      final re = RegExp(r'hello');
      expect(invoke('dart:core::RegExp::hashCode#0', [re]), isA<int>());
    });
  });

  // ── RegExp methods ──

  group('RegExp methods', () {
    test('hasMatch returns true when pattern matches', () {
      final re = RegExp(r'\d+');
      expect(invoke('dart:core::RegExp::hasMatch#1', [re, 'abc123']), true);
    });

    test('hasMatch returns false when pattern does not match', () {
      final re = RegExp(r'\d+');
      expect(invoke('dart:core::RegExp::hasMatch#1', [re, 'abc']), false);
    });

    test('firstMatch returns Match on success', () {
      final re = RegExp(r'\d+');
      final m =
          invoke('dart:core::RegExp::firstMatch#1', [re, 'abc123def']) as Match;
      expect(m.group(0), '123');
    });

    test('firstMatch returns null on no match', () {
      final re = RegExp(r'\d+');
      expect(invoke('dart:core::RegExp::firstMatch#1', [re, 'abc']), isNull);
    });

    test('allMatches without start', () {
      final re = RegExp(r'\d+');
      final matches = invoke(
              'dart:core::RegExp::allMatches#2', [re, 'a1b22c333'])
          as Iterable<RegExpMatch>;
      expect(matches.length, 3);
    });

    test('allMatches with start', () {
      final re = RegExp(r'\d+');
      final matches =
          invoke('dart:core::RegExp::allMatches#2', [re, 'a1b22c333', 3])
              as Iterable<RegExpMatch>;
      // Starting at index 3 ('22c333'), should match '22' and '333'
      expect(matches.length, 2);
    });

    test('allMatches with null start defaults to 0', () {
      final re = RegExp(r'\d+');
      final matches =
          invoke('dart:core::RegExp::allMatches#2', [re, 'a1b22c333', null])
              as Iterable<RegExpMatch>;
      expect(matches.length, 3);
    });

    test('stringMatch returns matched string', () {
      final re = RegExp(r'\d+');
      expect(
          invoke('dart:core::RegExp::stringMatch#1', [re, 'abc123']), '123');
    });

    test('stringMatch returns null on no match', () {
      final re = RegExp(r'\d+');
      expect(invoke('dart:core::RegExp::stringMatch#1', [re, 'abc']), isNull);
    });

    test('matchAsPrefix without start', () {
      final re = RegExp(r'\d+');
      final m =
          invoke('dart:core::RegExp::matchAsPrefix#2', [re, '123abc']) as Match;
      expect(m.group(0), '123');
    });

    test('matchAsPrefix with start', () {
      final re = RegExp(r'\d+');
      final m =
          invoke('dart:core::RegExp::matchAsPrefix#2', [re, 'abc123', 3])
              as Match;
      expect(m.group(0), '123');
    });

    test('matchAsPrefix returns null on no match at start', () {
      final re = RegExp(r'\d+');
      expect(invoke('dart:core::RegExp::matchAsPrefix#2', [re, 'abc123']),
          isNull);
    });

    test('toString', () {
      final re = RegExp(r'\d+');
      expect(invoke('dart:core::RegExp::toString#0', [re]), isA<String>());
    });
  });

  // ── Match getters and methods ──

  group('Match getters and methods', () {
    late Match match;

    setUp(() {
      match = RegExp(r'(\w+)@(\w+)').firstMatch('user@host')!;
    });

    test('start', () {
      expect(invoke('dart:core::Match::start#0', [match]), 0);
    });

    test('end', () {
      expect(invoke('dart:core::Match::end#0', [match]), 9);
    });

    test('input', () {
      expect(invoke('dart:core::Match::input#0', [match]), 'user@host');
    });

    test('groupCount', () {
      expect(invoke('dart:core::Match::groupCount#0', [match]), 2);
    });

    test('pattern returns the Pattern', () {
      expect(invoke('dart:core::Match::pattern#0', [match]), isA<Pattern>());
    });

    test('group(0) returns full match', () {
      expect(invoke('dart:core::Match::group#1', [match, 0]), 'user@host');
    });

    test('group(1) returns first capture', () {
      expect(invoke('dart:core::Match::group#1', [match, 1]), 'user');
    });

    test('group(2) returns second capture', () {
      expect(invoke('dart:core::Match::group#1', [match, 2]), 'host');
    });

    test('operator [] returns same as group', () {
      expect(invoke('dart:core::Match::[]#1', [match, 0]), 'user@host');
      expect(invoke('dart:core::Match::[]#1', [match, 1]), 'user');
    });

    test('groups returns list of group values', () {
      final result =
          invoke('dart:core::Match::groups#1', [match, [0, 1, 2]]) as List;
      expect(result, ['user@host', 'user', 'host']);
    });
  });

  // ── RegExpMatch specific ──

  group('RegExpMatch specific', () {
    late RegExpMatch match;

    setUp(() {
      match = RegExp(r'(?<user>\w+)@(?<domain>\w+)').firstMatch('foo@bar')!;
    });

    test('namedGroup', () {
      expect(invoke('dart:core::RegExpMatch::namedGroup#1', [match, 'user']),
          'foo');
      expect(invoke('dart:core::RegExpMatch::namedGroup#1', [match, 'domain']),
          'bar');
    });

    test('groupNames', () {
      final names =
          invoke('dart:core::RegExpMatch::groupNames#0', [match]) as Iterable;
      expect(names, containsAll(['user', 'domain']));
    });

    test('inherited start from RegExpMatch prefix', () {
      expect(invoke('dart:core::RegExpMatch::start#0', [match]), 0);
    });

    test('inherited end from RegExpMatch prefix', () {
      expect(invoke('dart:core::RegExpMatch::end#0', [match]), 7);
    });

    test('inherited input from RegExpMatch prefix', () {
      expect(invoke('dart:core::RegExpMatch::input#0', [match]), 'foo@bar');
    });

    test('inherited groupCount from RegExpMatch prefix', () {
      expect(invoke('dart:core::RegExpMatch::groupCount#0', [match]), 2);
    });

    test('inherited pattern from RegExpMatch prefix', () {
      expect(
          invoke('dart:core::RegExpMatch::pattern#0', [match]), isA<Pattern>());
    });

    test('inherited group from RegExpMatch prefix', () {
      expect(invoke('dart:core::RegExpMatch::group#1', [match, 0]), 'foo@bar');
      expect(invoke('dart:core::RegExpMatch::group#1', [match, 1]), 'foo');
    });

    test('inherited [] from RegExpMatch prefix', () {
      expect(invoke('dart:core::RegExpMatch::[]#1', [match, 0]), 'foo@bar');
    });

    test('inherited groups from RegExpMatch prefix', () {
      final result = invoke('dart:core::RegExpMatch::groups#1',
          [match, [0, 1, 2]]) as List;
      expect(result, ['foo@bar', 'foo', 'bar']);
    });
  });

  // ── E2e compile + run tests ──

  group('e2e compile + run', () {
    test(r"RegExp(r'\d+').hasMatch('abc123') returns true", () async {
      final result = await compileAndRunWithHost(r"""
bool main() {
  return RegExp(r'\d+').hasMatch('abc123');
}
""");
      expect(result, true);
    });

    test(r"RegExp firstMatch group(1) returns capture", () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  final m = RegExp(r'(\w+)@(\w+)').firstMatch('user@host');
  return m!.group(1)!;
}
""");
      expect(result, 'user');
    });

    test(r"RegExp allMatches length", () async {
      final result = await compileAndRunWithHost(r"""
int main() {
  return RegExp(r'\d+').allMatches('a1b22c333').length;
}
""");
      expect(result, 3);
    });

    test(r"RegExp hasMatch returns false", () async {
      final result = await compileAndRunWithHost(r"""
bool main() {
  return RegExp(r'\d+').hasMatch('abc');
}
""");
      expect(result, false);
    });

    test(r"RegExp stringMatch returns matched portion", () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  return RegExp(r'\d+').stringMatch('abc123')!;
}
""");
      expect(result, '123');
    });

    test(r"Match start and end", () async {
      final result = await compileAndRunWithHost(r"""
int main() {
  final m = RegExp(r'\d+').firstMatch('abc123def')!;
  return m.start;
}
""");
      expect(result, 3);
    });

    test(r"Match end property", () async {
      final result = await compileAndRunWithHost(r"""
int main() {
  final m = RegExp(r'\d+').firstMatch('abc123def')!;
  return m.end;
}
""");
      expect(result, 6);
    });
  });
}
