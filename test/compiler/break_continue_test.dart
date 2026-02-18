import 'package:dartic/src/runtime/interpreter.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// Tests for break/continue/label statement compilation.
void main() {
  group('break in loops', () {
    test('break exits while loop early', () async {
      final result = await _compileAndRun('''
int f() {
  int sum = 0;
  int i = 0;
  while (i < 100) {
    if (i >= 5) break;
    sum = sum + i;
    i = i + 1;
  }
  return sum;
}
int main() => f();
''');
      // 0 + 1 + 2 + 3 + 4 = 10
      expect(result, 10);
    });

    test('break exits for loop early', () async {
      final result = await _compileAndRun('''
int f() {
  int sum = 0;
  for (int i = 0; i < 100; i = i + 1) {
    if (i >= 3) break;
    sum = sum + i;
  }
  return sum;
}
int main() => f();
''');
      // 0 + 1 + 2 = 3
      expect(result, 3);
    });
  });

  group('continue in loops', () {
    test('continue skips current iteration in while loop', () async {
      final result = await _compileAndRun('''
int f() {
  int sum = 0;
  int i = 0;
  while (i < 10) {
    i = i + 1;
    if (i % 2 == 0) continue;
    sum = sum + i;
  }
  return sum;
}
int main() => f();
''');
      // 1 + 3 + 5 + 7 + 9 = 25
      expect(result, 25);
    });

    test('continue skips current iteration in for loop', () async {
      final result = await _compileAndRun('''
int f() {
  int sum = 0;
  for (int i = 0; i < 10; i = i + 1) {
    if (i % 3 == 0) continue;
    sum = sum + i;
  }
  return sum;
}
int main() => f();
''');
      // Skip 0,3,6,9 → sum = 1+2+4+5+7+8 = 27
      expect(result, 27);
    });
  });

  group('nested break/continue', () {
    test('break only exits innermost loop', () async {
      final result = await _compileAndRun('''
int f() {
  int count = 0;
  for (int i = 0; i < 3; i = i + 1) {
    for (int j = 0; j < 10; j = j + 1) {
      if (j >= 2) break;
      count = count + 1;
    }
  }
  return count;
}
int main() => f();
''');
      // Each outer iteration runs inner 2 times (j=0,1), 3 outer = 6
      expect(result, 6);
    });

    test('labeled break exits outer loop', () async {
      final result = await _compileAndRun('''
int f() {
  int count = 0;
  outer:
  for (int i = 0; i < 10; i = i + 1) {
    for (int j = 0; j < 10; j = j + 1) {
      if (i + j >= 5) break outer;
      count = count + 1;
    }
  }
  return count;
}
int main() => f();
''');
      // i=0: j=0,1,2,3,4 (5 iterations, j=5 breaks outer)
      // Total = 5
      expect(result, 5);
    });
  });

  group('break in switch', () {
    test('break exits switch statement', () async {
      final result = await _compileAndRun('''
int f(int x) {
  int result = 0;
  switch (x) {
    case 1:
      result = 10;
      break;
    case 2:
      result = 20;
      break;
    default:
      result = -1;
  }
  return result;
}
int main() => f(1);
''');
      expect(result, 10);
    });
  });
}

Future<int> _compileAndRun(String source) async {
  final module = await compileDart(source);
  final interp = DarticInterpreter();
  interp.execute(module);
  return interp.valueStack.readInt(0);
}
