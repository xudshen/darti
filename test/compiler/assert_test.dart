import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Compiler + e2e tests for assert statement compilation.
void main() {
  group('assert compilation', () {
    test('assert(true) falls through normally', () async {
      final result = await _compileAndRun('''
int f() {
  assert(true);
  return 42;
}
int main() => f();
''');
      expect(result, 42);
    });

    test('assert(false) throws AssertionError', () async {
      final module = await compileDart('''
int f() {
  assert(false);
  return 0;
}
int main() => f();
''');
      final interp = DarticInterpreter();
      expect(
        () => interp.execute(module),
        throwsA(isA<AssertionError>()),
      );
    });

    test('assert with message includes message in error', () async {
      final module = await compileDart('''
int f() {
  assert(false, 'custom message');
  return 0;
}
int main() => f();
''');
      final interp = DarticInterpreter();
      expect(
        () => interp.execute(module),
        throwsA(
          isA<AssertionError>().having(
            (e) => e.message,
            'message',
            'custom message',
          ),
        ),
      );
    });

    test('assert(false) caught by try-catch', () async {
      final result = await _compileAndRun('''
int f() {
  try {
    assert(false);
    return 0;
  } catch (e) {
    return 99;
  }
}
int main() => f();
''');
      expect(result, 99);
    });

    test('assert with variable condition', () async {
      final result = await _compileAndRun('''
int f() {
  int x = 5;
  assert(x > 0);
  return x;
}
int main() => f();
''');
      expect(result, 5);
    });

    test('assert generates ASSERT opcode', () async {
      final module = await compileDart('''
void f() {
  assert(true);
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final hasAssert = f.bytecode.any((instr) => (instr & 0xFF) == Op.assert_);
      expect(hasAssert, isTrue, reason: 'ASSERT opcode not found');
    });
  });
}

Future<int> _compileAndRun(String source) async {
  final module = await compileDart(source);
  final interp = DarticInterpreter();
  interp.execute(module);
  return interp.valueStack.readInt(0);
}
