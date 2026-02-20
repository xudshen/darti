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

  group('bool bridge', () {
    test('true.toString()', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return true.toString();
}
''');
      expect(result, 'true');
    });

    test('false.toString()', () async {
      final result = await compileAndRunWithHost('''
String main() {
  return false.toString();
}
''');
      expect(result, 'false');
    });
  });

  group('String bridge', () {
    test("''.isEmpty", () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return ''.isEmpty;
}
''');
      expect(result, true);
    });

    test("'hello'.isNotEmpty", () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return 'hello'.isNotEmpty;
}
''');
      expect(result, true);
    });

    test("'hello world'.substring(0, 5)", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'hello world'.substring(0, 5);
}
''');
      expect(result, 'hello');
    });

    test("'hello'.indexOf('l')", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.indexOf('l');
}
''');
      expect(result, 2);
    });

    test("'hello'.contains('ell')", () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return 'hello'.contains('ell');
}
''');
      expect(result, true);
    });

    test("'Hello'.toLowerCase()", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'Hello'.toLowerCase();
}
''');
      expect(result, 'hello');
    });

    test("'hello'.toUpperCase()", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'hello'.toUpperCase();
}
''');
      expect(result, 'HELLO');
    });

    test("' hi '.trim()", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return ' hi '.trim();
}
''');
      expect(result, 'hi');
    });

    test("'hello'.startsWith('hel')", () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return 'hello'.startsWith('hel');
}
''');
      expect(result, true);
    });

    test("'hello'.endsWith('lo')", () async {
      final result = await compileAndRunWithHost('''
bool main() {
  return 'hello'.endsWith('lo');
}
''');
      expect(result, true);
    });

    test("'hello'.replaceAll('l', 'r')", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'hello'.replaceAll('l', 'r');
}
''');
      expect(result, 'herro');
    });

    test("'hello'.codeUnitAt(0)", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.codeUnitAt(0);
}
''');
      expect(result, 104);
    });

    test("'hello'[0]", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'hello'[0];
}
''');
      expect(result, 'h');
    });

    test("'hello' + ' world'", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'hello' + ' world';
}
''');
      expect(result, 'hello world');
    });

    test("'abc'.compareTo('abd')", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'abc'.compareTo('abd');
}
''');
      expect(result, lessThan(0));
    });

    test("String.fromCharCode(65)", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return String.fromCharCode(65);
}
''');
      expect(result, 'A');
    });

    test("'abc' * 3", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'abc' * 3;
}
''');
      expect(result, 'abcabcabc');
    });

    test("'hello'.toString()", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'hello'.toString();
}
''');
      expect(result, 'hello');
    });

    test("' hi '.trimLeft()", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return ' hi '.trimLeft();
}
''');
      expect(result, 'hi ');
    });

    test("' hi '.trimRight()", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return ' hi '.trimRight();
}
''');
      expect(result, ' hi');
    });

    test("'hello'.lastIndexOf('l')", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.lastIndexOf('l');
}
''');
      expect(result, 3);
    });

    test("'hello'.substring(2)", () async {
      final result = await compileAndRunWithHost('''
String main() {
  return 'hello'.substring(2);
}
''');
      expect(result, 'llo');
    });
  });

  group('String codeUnits', () {
    test('codeUnits.length', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.codeUnits.length;
}
''');
      expect(result, 5);
    });

    test('codeUnits[0]', () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.codeUnits[0];
}
''');
      expect(result, 104);
    });
  });

  // ── String callback methods (Task 5.6.6) ──

  group('String callback methods — registration', () {
    test('callback bindings are registered', () {
      expect(registry.lookupByName('dart:core::String::replaceAllMapped#2'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::String::replaceFirstMapped#3'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::String::splitMapJoin#3'),
          isNot(-1));
      expect(
          registry.lookupByName('dart:core::String::allMatches#2'), isNot(-1));
      expect(
          registry.lookupByName('dart:core::String::matchAsPrefix#2'),
          isNot(-1));
      expect(registry.lookupByName('dart:core::String::runes#0'), isNot(-1));
    });
  });

  group('String callback methods — invoke', () {
    test('replaceAllMapped replaces all matches', () {
      final result = invoke('dart:core::String::replaceAllMapped#2', [
        'abc123def456',
        RegExp(r'\d+'),
        (Match m) => '[${m.group(0)}]',
      ]);
      expect(result, 'abc[123]def[456]');
    });

    test('replaceFirstMapped replaces only first match', () {
      final result = invoke('dart:core::String::replaceFirstMapped#3', [
        'abc123def456',
        RegExp(r'\d+'),
        (Match m) => '[${m.group(0)}]',
        null,
      ]);
      expect(result, 'abc[123]def456');
    });

    test('replaceFirstMapped with startIndex', () {
      final result = invoke('dart:core::String::replaceFirstMapped#3', [
        'abc123def456',
        RegExp(r'\d+'),
        (Match m) => '[${m.group(0)}]',
        6,
      ]);
      expect(result, 'abc123def[456]');
    });

    test('splitMapJoin with onMatch and onNonMatch', () {
      final result = invoke('dart:core::String::splitMapJoin#3', [
        'a1b2c3',
        RegExp(r'\d'),
        (Match m) => '(${m.group(0)})',
        (String s) => s.toUpperCase(),
      ]);
      expect(result, 'A(1)B(2)C(3)');
    });

    test('splitMapJoin with null onNonMatch', () {
      final result = invoke('dart:core::String::splitMapJoin#3', [
        'a1b2',
        RegExp(r'\d'),
        (Match m) => '*',
        null,
      ]);
      expect(result, 'a*b*');
    });

    test('allMatches returns all occurrences', () {
      final matches = invoke('dart:core::String::allMatches#2', [
        'hello',
        'hello world hello',
        null,
      ]) as Iterable;
      expect(matches.length, 2);
    });

    test('allMatches with start index', () {
      final matches = invoke('dart:core::String::allMatches#2', [
        'hello',
        'hello world hello',
        6,
      ]) as Iterable;
      expect(matches.length, 1);
    });

    test('matchAsPrefix matches at start', () {
      final match = invoke('dart:core::String::matchAsPrefix#2', [
        'hello',
        'hello world',
        null,
      ]) as Match;
      expect(match.group(0), 'hello');
    });

    test('matchAsPrefix returns null when no match at start', () {
      final result = invoke('dart:core::String::matchAsPrefix#2', [
        'hello',
        'world hello',
        null,
      ]);
      expect(result, isNull);
    });

    test('matchAsPrefix with start offset', () {
      final match = invoke('dart:core::String::matchAsPrefix#2', [
        'world',
        'hello world',
        6,
      ]) as Match;
      expect(match.group(0), 'world');
    });

    test('runes getter returns Runes', () {
      final runes = invoke('dart:core::String::runes#0', ['hello']);
      expect(runes, isA<Runes>());
      expect((runes as Runes).length, 5);
    });
  });

  group('String callback methods — e2e', () {
    test('replaceAllMapped with RegExp callback', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  return 'a1b2'.replaceAllMapped(RegExp(r'\d'), (m) => '0');
}
""");
      expect(result, 'a0b0');
    });

    test('replaceFirstMapped replaces only first', () async {
      final result = await compileAndRunWithHost(r"""
String main() {
  return 'a1b2'.replaceFirstMapped(RegExp(r'\d'), (m) => 'X');
}
""");
      expect(result, 'aXb2');
    });

    test("'hello'.runes.length returns 5", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'hello'.runes.length;
}
''');
      expect(result, 5);
    });

    test("allMatches count", () async {
      final result = await compileAndRunWithHost('''
int main() {
  return 'ab'.allMatches('ababab').length;
}
''');
      expect(result, 3);
    });
  });
}
