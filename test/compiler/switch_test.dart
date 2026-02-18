import 'package:dartic/src/bytecode/opcodes.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Compiler tests for switch/case statement compilation.
///
/// Phase 2 strategy: compile switch as if-else chain (sequential comparisons).
void main() {
  group('switch compilation', () {
    test('basic int switch generates comparison chain', () async {
      final module = await compileDart('''
int f(int x) {
  switch (x) {
    case 0:
      return 10;
    case 1:
      return 20;
    default:
      return -1;
  }
}
void main() {}
''');
      final f = findFunc(module, 'f');
      final code = f.bytecode;

      // Should have EQ_INT comparisons for each case value.
      final eq1 = findOp(code, Op.eqInt);
      expect(eq1, isNot(-1), reason: 'EQ_INT not found for first case');

      final eq2 = findOp(code, Op.eqInt, start: eq1 + 1);
      expect(eq2, isNot(-1), reason: 'EQ_INT not found for second case');
    });
  });

  group('switch e2e', () {
    test('switch matches correct case', () async {
      final result = await _compileAndRun('''
int f(int x) {
  switch (x) {
    case 0:
      return 10;
    case 1:
      return 20;
    case 2:
      return 30;
    default:
      return -1;
  }
}
int main() => f(1);
''');
      expect(result, 20);
    });

    test('switch default case', () async {
      final result = await _compileAndRun('''
int f(int x) {
  switch (x) {
    case 0:
      return 10;
    case 1:
      return 20;
    default:
      return -1;
  }
}
int main() => f(99);
''');
      expect(result, -1);
    });

    test('switch no match and no default skips', () async {
      final result = await _compileAndRun('''
int f(int x) {
  int result = 0;
  switch (x) {
    case 0:
      result = 10;
    case 1:
      result = 20;
  }
  return result;
}
int main() => f(99);
''');
      expect(result, 0);
    });

    test('switch first case matches', () async {
      final result = await _compileAndRun('''
int f(int x) {
  switch (x) {
    case 42:
      return 100;
    default:
      return 0;
  }
}
int main() => f(42);
''');
      expect(result, 100);
    });

    test('multiple case values share body (empty case fall-through)',
        () async {
      final result = await _compileAndRun('''
int f(int x) {
  switch (x) {
    case 1:
    case 2:
    case 3:
      return 100;
    default:
      return 0;
  }
}
int main() => f(2);
''');
      expect(result, 100);
    });
  });
}

Future<int> _compileAndRun(String source) async {
  final module = await compileDart(source);
  final interp = DarticInterpreter();
  interp.execute(module);
  return interp.valueStack.readInt(0);
}
