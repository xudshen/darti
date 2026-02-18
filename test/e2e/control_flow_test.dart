import 'package:dartic/src/bytecode/module.dart';
import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end tests for control flow statements.
///
/// Full pipeline: Dart source → CFE (.dill) → DarticCompiler → DarticInterpreter.
void main() {
  group('if/else e2e', () {
    test('abs(-5) returns 5', () async {
      final result = await _compileAndRun('''
int abs(int x) {
  if (x < 0) return -x;
  return x;
}
int main() => abs(-5);
''');
      expect(result, 5);
    });

    test('abs(3) returns 3', () async {
      final result = await _compileAndRun('''
int abs(int x) {
  if (x < 0) return -x;
  return x;
}
int main() => abs(3);
''');
      expect(result, 3);
    });

    test('max(3, 7) returns 7', () async {
      final result = await _compileAndRun('''
int max(int a, int b) {
  if (a > b) return a;
  else return b;
}
int main() => max(3, 7);
''');
      expect(result, 7);
    });

    test('max(10, 2) returns 10', () async {
      final result = await _compileAndRun('''
int max(int a, int b) {
  if (a > b) return a;
  else return b;
}
int main() => max(10, 2);
''');
      expect(result, 10);
    });

    test('nested if: clamp(x, lo, hi)', () async {
      final result = await _compileAndRun('''
int clamp(int x, int lo, int hi) {
  if (x < lo) return lo;
  if (x > hi) return hi;
  return x;
}
int main() => clamp(15, 0, 10);
''');
      expect(result, 10);
    });

    test('if with variable assignment in block', () async {
      final result = await _compileAndRun('''
int f(int x) {
  int result = 0;
  if (x > 0) {
    result = x * 2;
  }
  return result;
}
int main() => f(5);
''');
      expect(result, 10);
    });
  });

  group('loops e2e', () {
    test('while loop: sum 1 to 10 = 55', () async {
      final result = await _compileAndRun('''
int sumTo(int n) {
  int sum = 0;
  int i = 1;
  while (i <= n) {
    sum = sum + i;
    i = i + 1;
  }
  return sum;
}
int main() => sumTo(10);
''');
      expect(result, 55);
    });

    test('for loop: sum 1 to 10 = 55', () async {
      final result = await _compileAndRun('''
int sumFor(int n) {
  int sum = 0;
  for (int i = 1; i <= n; i = i + 1) {
    sum = sum + i;
  }
  return sum;
}
int main() => sumFor(10);
''');
      expect(result, 55);
    });

    test('do-while loop: at least one iteration', () async {
      final result = await _compileAndRun('''
int f() {
  int x = 0;
  do {
    x = x + 1;
  } while (x < 5);
  return x;
}
int main() => f();
''');
      expect(result, 5);
    });

    test('factorial via while loop', () async {
      final result = await _compileAndRun('''
int factorial(int n) {
  int result = 1;
  int i = 2;
  while (i <= n) {
    result = result * i;
    i = i + 1;
  }
  return result;
}
int main() => factorial(6);
''');
      expect(result, 720);
    });

    test('nested loops: multiplication table sum', () async {
      final result = await _compileAndRun('''
int f() {
  int sum = 0;
  for (int i = 1; i <= 3; i = i + 1) {
    for (int j = 1; j <= 3; j = j + 1) {
      sum = sum + i * j;
    }
  }
  return sum;
}
int main() => f();
''');
      // 1*1+1*2+1*3 + 2*1+2*2+2*3 + 3*1+3*2+3*3
      // = (1+2+3) + (2+4+6) + (3+6+9) = 6 + 12 + 18 = 36
      expect(result, 36);
    });

    test('fibonacci via loop', () async {
      final result = await _compileAndRun('''
int fib(int n) {
  if (n <= 1) return n;
  int a = 0;
  int b = 1;
  for (int i = 2; i <= n; i = i + 1) {
    int temp = a + b;
    a = b;
    b = temp;
  }
  return b;
}
int main() => fib(10);
''');
      expect(result, 55);
    });
  });
}

/// Compiles Dart source → .dill → bytecode → executes → returns main's int result.
Future<int> _compileAndRun(String source) async {
  final module = await compileDart(source);
  return _executeAndReadResult(module);
}

int _executeAndReadResult(DarticModule module) {
  final interp = DarticInterpreter();
  interp.execute(module);
  return interp.valueStack.readInt(0);
}
