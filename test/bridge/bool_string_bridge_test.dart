import 'package:dartic/src/bridge/core_bindings.dart';
import 'package:dartic/src/bridge/host_bindings.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

Future<Object?> _run(String source) async {
  final module = await compileDart(source);
  final bindings = HostBindings();
  CoreBindings.registerAll(bindings);
  final interp = DarticInterpreter(hostBindings: bindings);
  interp.execute(module);
  return interp.entryResult;
}

void main() {
  group('bool bridge', () {
    test('true.toString()', () async {
      final result = await _run('''
String main() {
  return true.toString();
}
''');
      expect(result, 'true');
    });

    test('false.toString()', () async {
      final result = await _run('''
String main() {
  return false.toString();
}
''');
      expect(result, 'false');
    });
  });

  group('String bridge', () {
    test("''.isEmpty", () async {
      final result = await _run('''
bool main() {
  return ''.isEmpty;
}
''');
      expect(result, true);
    });

    test("'hello'.isNotEmpty", () async {
      final result = await _run('''
bool main() {
  return 'hello'.isNotEmpty;
}
''');
      expect(result, true);
    });

    test("'hello world'.substring(0, 5)", () async {
      final result = await _run('''
String main() {
  return 'hello world'.substring(0, 5);
}
''');
      expect(result, 'hello');
    });

    test("'hello'.indexOf('l')", () async {
      final result = await _run('''
int main() {
  return 'hello'.indexOf('l');
}
''');
      expect(result, 2);
    });

    test("'hello'.contains('ell')", () async {
      final result = await _run('''
bool main() {
  return 'hello'.contains('ell');
}
''');
      expect(result, true);
    });

    test("'Hello'.toLowerCase()", () async {
      final result = await _run('''
String main() {
  return 'Hello'.toLowerCase();
}
''');
      expect(result, 'hello');
    });

    test("'hello'.toUpperCase()", () async {
      final result = await _run('''
String main() {
  return 'hello'.toUpperCase();
}
''');
      expect(result, 'HELLO');
    });

    test("' hi '.trim()", () async {
      final result = await _run('''
String main() {
  return ' hi '.trim();
}
''');
      expect(result, 'hi');
    });

    test("'hello'.startsWith('hel')", () async {
      final result = await _run('''
bool main() {
  return 'hello'.startsWith('hel');
}
''');
      expect(result, true);
    });

    test("'hello'.endsWith('lo')", () async {
      final result = await _run('''
bool main() {
  return 'hello'.endsWith('lo');
}
''');
      expect(result, true);
    });

    test("'hello'.replaceAll('l', 'r')", () async {
      final result = await _run('''
String main() {
  return 'hello'.replaceAll('l', 'r');
}
''');
      expect(result, 'herro');
    });

    test("'hello'.codeUnitAt(0)", () async {
      final result = await _run('''
int main() {
  return 'hello'.codeUnitAt(0);
}
''');
      expect(result, 104);
    });

    test("'hello'[0]", () async {
      final result = await _run('''
String main() {
  return 'hello'[0];
}
''');
      expect(result, 'h');
    });

    test("'hello' + ' world'", () async {
      final result = await _run('''
String main() {
  return 'hello' + ' world';
}
''');
      expect(result, 'hello world');
    });

    test("'abc'.compareTo('abd')", () async {
      final result = await _run('''
int main() {
  return 'abc'.compareTo('abd');
}
''');
      expect(result, lessThan(0));
    });

    test("String.fromCharCode(65)", () async {
      final result = await _run('''
String main() {
  return String.fromCharCode(65);
}
''');
      expect(result, 'A');
    });

    test("'abc' * 3", () async {
      final result = await _run('''
String main() {
  return 'abc' * 3;
}
''');
      expect(result, 'abcabcabc');
    });

    test("'hello'.toString()", () async {
      final result = await _run('''
String main() {
  return 'hello'.toString();
}
''');
      expect(result, 'hello');
    });

    test("' hi '.trimLeft()", () async {
      final result = await _run('''
String main() {
  return ' hi '.trimLeft();
}
''');
      expect(result, 'hi ');
    });

    test("' hi '.trimRight()", () async {
      final result = await _run('''
String main() {
  return ' hi '.trimRight();
}
''');
      expect(result, ' hi');
    });

    test("'hello'.lastIndexOf('l')", () async {
      final result = await _run('''
int main() {
  return 'hello'.lastIndexOf('l');
}
''');
      expect(result, 3);
    });

    test("'hello'.substring(2)", () async {
      final result = await _run('''
String main() {
  return 'hello'.substring(2);
}
''');
      expect(result, 'llo');
    });
  });
}
