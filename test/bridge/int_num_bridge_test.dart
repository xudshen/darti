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
  group('int bridge', () {
    test('(-42).abs() returns 42', () async {
      final result = await _run('''
int main() {
  return (-42).abs();
}
''');
      expect(result, 42);
    });

    test('42.isEven', () async {
      final result = await _run('''
bool main() {
  return 42.isEven;
}
''');
      expect(result, true);
    });

    test('43.isOdd', () async {
      final result = await _run('''
bool main() {
  return 43.isOdd;
}
''');
      expect(result, true);
    });

    test('42.toRadixString(16)', () async {
      final result = await _run('''
String main() {
  return 42.toRadixString(16);
}
''');
      expect(result, '2a');
    });

    test('42.clamp(0, 10)', () async {
      final result = await _run('''
int main() {
  return 42.clamp(0, 10);
}
''');
      expect(result, 10);
    });

    test('42.compareTo(43)', () async {
      final result = await _run('''
int main() {
  return 42.compareTo(43);
}
''');
      expect(result, lessThan(0));
    });

    test('42.remainder(5)', () async {
      final result = await _run('''
int main() {
  return 42.remainder(5);
}
''');
      expect(result, 2);
    });

    test('42.bitLength', () async {
      final result = await _run('''
int main() {
  return 42.bitLength;
}
''');
      expect(result, 6);
    });

    test('42.sign', () async {
      final result = await _run('''
int main() {
  return 42.sign;
}
''');
      expect(result, 1);
    });

    test('42.toStringAsFixed(2)', () async {
      final result = await _run('''
String main() {
  return 42.toStringAsFixed(2);
}
''');
      expect(result, '42.00');
    });

    test('int.parse("42")', () async {
      final result = await _run('''
int main() {
  return int.parse('42');
}
''');
      expect(result, 42);
    });
  });

  group('num bridge', () {
    test('42.isNegative', () async {
      final result = await _run('''
bool main() {
  return 42.isNegative;
}
''');
      expect(result, false);
    });
  });
}
