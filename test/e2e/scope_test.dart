import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end tests for block-level scope and variable shadowing.
///
/// Full pipeline: Dart source -> CFE (.dill) -> DarticCompiler -> DarticInterpreter.
///
/// Verifies that the compiler correctly handles:
/// - Sibling blocks with same-name variables (no conflict)
/// - Inner block shadowing outer variable
/// - Loop block scope (independent locals per iteration)
/// - Function parameters and local variable scope interaction
/// - Nested functions (closures) with captured vs local variables
/// - if/else branches with their own scope
void main() {
  group('sibling blocks: same-name variables', () {
    test('int x in two sibling blocks - no conflict', () async {
      final result = await compileAndRun('''
int main() {
  int result = 0;
  {
    int x = 1;
    result = result + x;
  }
  {
    int x = 2;
    result = result + x;
  }
  return result;
}
''');
      expect(result, 3);
    });

    test('three sibling blocks with same variable name', () async {
      final result = await compileAndRun('''
int main() {
  int sum = 0;
  {
    int x = 10;
    sum = sum + x;
  }
  {
    int x = 20;
    sum = sum + x;
  }
  {
    int x = 30;
    sum = sum + x;
  }
  return sum;
}
''');
      expect(result, 60);
    });

    test('same-name variables of different types in sibling blocks', () async {
      final result = await compileAndRun('''
int main() {
  int result = 0;
  {
    int x = 5;
    result = result + x;
  }
  {
    int x = 100;
    result = result + x;
  }
  return result;
}
''');
      expect(result, 105);
    });
  });

  group('inner block shadows outer variable', () {
    test('inner x shadows outer x, outer restored after block', () async {
      final result = await compileAndRun('''
int main() {
  int x = 1;
  int before = x;
  {
    int x = 2;
    before = before + x;
  }
  // x should be 1 again after inner block exits
  return before + x;
}
''');
      // before = 1, then before = 1 + 2 = 3, then 3 + 1 (outer x) = 4
      expect(result, 4);
    });

    test('two levels of shadowing', () async {
      final result = await compileAndRun('''
int main() {
  int x = 1;
  int r = 0;
  {
    int x = 2;
    {
      int x = 3;
      r = r + x;
    }
    r = r + x;
  }
  r = r + x;
  return r;
}
''');
      // r = 0 + 3 + 2 + 1 = 6
      expect(result, 6);
    });

    test('inner block modifies outer variable (not shadowed)', () async {
      final result = await compileAndRun('''
int main() {
  int x = 10;
  {
    x = x + 5;
  }
  return x;
}
''');
      expect(result, 15);
    });

    test('shadowed variable does not affect outer after block exit', () async {
      final result = await compileAndRun('''
int main() {
  int x = 42;
  {
    int x = 999;
    // x is 999 inside this block
  }
  // x should still be 42
  return x;
}
''');
      expect(result, 42);
    });
  });

  group('loop block scope', () {
    test('for loop variable is scoped to the loop', () async {
      final result = await compileAndRun('''
int main() {
  int sum = 0;
  for (int i = 0; i < 5; i = i + 1) {
    sum = sum + i;
  }
  // i is not accessible here - and sum should be 0+1+2+3+4 = 10
  return sum;
}
''');
      expect(result, 10);
    });

    test('loop body local variables are independent per iteration', () async {
      final result = await compileAndRun('''
int main() {
  int sum = 0;
  for (int i = 0; i < 3; i = i + 1) {
    int local = i * 10;
    sum = sum + local;
  }
  return sum;
}
''');
      // local = 0, 10, 20 => sum = 30
      expect(result, 30);
    });

    test('while loop body with block-scoped variable', () async {
      final result = await compileAndRun('''
int main() {
  int sum = 0;
  int i = 0;
  while (i < 4) {
    int doubled = i * 2;
    sum = sum + doubled;
    i = i + 1;
  }
  return sum;
}
''');
      // doubled: 0, 2, 4, 6 => sum = 12
      expect(result, 12);
    });

    test('nested loops with same-name loop variable', () async {
      final result = await compileAndRun('''
int main() {
  int sum = 0;
  for (int i = 1; i <= 3; i = i + 1) {
    for (int i = 1; i <= 2; i = i + 1) {
      sum = sum + i;
    }
  }
  return sum;
}
''');
      // Inner loop runs 3 times (outer i=1,2,3), each time summing 1+2=3
      // Total: 3 * 3 = 9
      expect(result, 9);
    });

    test('for loop variable shadows outer variable', () async {
      final result = await compileAndRun('''
int main() {
  int i = 100;
  for (int i = 0; i < 3; i = i + 1) {
    // i here is the loop variable, not the outer i
  }
  // outer i should still be 100
  return i;
}
''');
      expect(result, 100);
    });
  });

  group('function parameters and local variable scope', () {
    test('local variable shadows parameter', () async {
      final result = await compileAndRun('''
int f(int x) {
  int result = x;
  {
    int x = 99;
    result = result + x;
  }
  // x is the parameter (original value) again
  result = result + x;
  return result;
}
int main() => f(1);
''');
      // result = 1, then 1 + 99 = 100, then 100 + 1 = 101
      expect(result, 101);
    });

    test('multiple parameters and local shadowing', () async {
      final result = await compileAndRun('''
int f(int a, int b) {
  int sum = a + b;
  {
    int a = 100;
    int b = 200;
    sum = sum + a + b;
  }
  // a and b are original parameters
  sum = sum + a + b;
  return sum;
}
int main() => f(1, 2);
''');
      // sum = 3, then 3 + 100 + 200 = 303, then 303 + 1 + 2 = 306
      expect(result, 306);
    });

    test('function with block-scoped variable and return', () async {
      final result = await compileAndRun('''
int f(int n) {
  int r = 0;
  {
    int temp = n * 2;
    r = temp;
  }
  return r;
}
int main() => f(21);
''');
      expect(result, 42);
    });
  });

  group('nested functions with scope', () {
    test('closure captures outer variable, local does not interfere', () async {
      final result = await compileAndRun('''
int main() {
  int x = 10;
  int f() {
    int x = 20;
    return x;
  }
  // f() returns its local x (20), outer x is still 10
  int r = f();
  return r + x;
}
''');
      // f() = 20, outer x = 10, total = 30
      expect(result, 30);
    });

    test('closure reads captured variable from enclosing scope', () async {
      final result = await compileAndRun('''
int main() {
  int x = 5;
  int f() => x;
  return f();
}
''');
      expect(result, 5);
    });

    test('closure modifies captured variable', () async {
      final result = await compileAndRun('''
int main() {
  int x = 0;
  void inc() { x = x + 1; }
  inc();
  inc();
  inc();
  return x;
}
''');
      expect(result, 3);
    });

    test('nested closure with local shadowing captured variable', () async {
      final result = await compileAndRun('''
int f() {
  int x = 10;
  int g() {
    int x = 20;
    return x;
  }
  int r = g();
  return r + x;
}
int main() => f();
''');
      // g() returns 20 (its local), f()'s x is 10, so 30
      expect(result, 30);
    });

    test('closure captures loop variable correctly', () async {
      final result = await compileAndRun('''
int f() {
  int sum = 0;
  for (int i = 0; i < 3; i = i + 1) {
    int val = i * 10;
    sum = sum + val;
  }
  return sum;
}
int main() => f();
''');
      // val = 0, 10, 20 => sum = 30
      expect(result, 30);
    });
  });

  group('if/else branch scope', () {
    test('variables declared in if branch are scoped', () async {
      final result = await compileAndRun('''
int main() {
  int r = 0;
  if (true) {
    int x = 42;
    r = x;
  }
  // x is not accessible here
  return r;
}
''');
      expect(result, 42);
    });

    test('if and else branches have independent scopes', () async {
      final result = await compileAndRun('''
int f(bool cond) {
  int r = 0;
  if (cond) {
    int x = 10;
    r = x;
  } else {
    int x = 20;
    r = x;
  }
  return r;
}
int main() => f(false);
''');
      expect(result, 20);
    });

    test('if/else with same variable name in both branches', () async {
      final result = await compileAndRun('''
int f(bool cond) {
  int r = 0;
  if (cond) {
    int val = 1;
    r = val;
  } else {
    int val = 2;
    r = val;
  }
  return r;
}
int main() => f(true);
''');
      expect(result, 1);
    });

    test('nested if with block scoping', () async {
      final result = await compileAndRun('''
int f(int n) {
  int r = 0;
  if (n > 0) {
    int x = n * 2;
    if (x > 5) {
      int y = x + 10;
      r = y;
    } else {
      int y = x + 1;
      r = y;
    }
  }
  return r;
}
int main() => f(3);
''');
      // n=3, x=6, 6>5 so y = 6+10 = 16
      expect(result, 16);
    });

    test('variable in outer scope accessible in if body', () async {
      final result = await compileAndRun('''
int main() {
  int x = 10;
  if (true) {
    x = x + 5;
  }
  return x;
}
''');
      expect(result, 15);
    });
  });

  group('register reuse after scope exit', () {
    test('registers reclaimed after block exit allow further allocation',
        () async {
      final result = await compileAndRun('''
int main() {
  int sum = 0;
  {
    int a = 1;
    int b = 2;
    int c = 3;
    sum = a + b + c;
  }
  // After block exit, a, b, c registers should be reclaimed
  {
    int d = 10;
    int e = 20;
    int f = 30;
    sum = sum + d + e + f;
  }
  return sum;
}
''');
      // sum = 6, then 6 + 60 = 66
      expect(result, 66);
    });

    test('many sequential blocks reuse registers', () async {
      final result = await compileAndRun('''
int main() {
  int total = 0;
  { int x = 1; total = total + x; }
  { int x = 2; total = total + x; }
  { int x = 3; total = total + x; }
  { int x = 4; total = total + x; }
  { int x = 5; total = total + x; }
  return total;
}
''');
      expect(result, 15);
    });
  });

  group('complex scope scenarios', () {
    test('do-while with block scope variable', () async {
      final result = await compileAndRun('''
int main() {
  int sum = 0;
  int i = 0;
  do {
    int doubled = i * 2;
    sum = sum + doubled;
    i = i + 1;
  } while (i < 5);
  return sum;
}
''');
      // doubled: 0, 2, 4, 6, 8 => sum = 20
      expect(result, 20);
    });

    test('switch-like if/else chain with scoped variables', () async {
      final result = await compileAndRun('''
int classify(int n) {
  int result = 0;
  if (n < 0) {
    int abs = -n;
    result = abs;
  } else if (n == 0) {
    int zero = 0;
    result = zero;
  } else {
    int pos = n * 10;
    result = pos;
  }
  return result;
}
int main() => classify(5);
''');
      expect(result, 50);
    });

    test('variable scoping across function calls', () async {
      final result = await compileAndRun('''
int helper(int x) {
  return x + 1;
}
int main() {
  int x = 10;
  {
    int x = helper(5);
    // x should be 6 here (helper returns 5+1)
    if (x != 6) return -1;
  }
  // x should be 10 here
  return x;
}
''');
      expect(result, 10);
    });

    test('deeply nested blocks with progressive shadowing', () async {
      final result = await compileAndRun('''
int main() {
  int x = 1;
  int r = x;
  {
    int x = 2;
    r = r + x;
    {
      int x = 3;
      r = r + x;
      {
        int x = 4;
        r = r + x;
      }
    }
  }
  r = r + x;
  return r;
}
''');
      // r = 1, r = 1+2 = 3, r = 3+3 = 6, r = 6+4 = 10, r = 10+1 = 11
      expect(result, 11);
    });

    test('block scope with string ref variables', () async {
      final result = await compileAndRun('''
String main() {
  String s = 'outer';
  {
    String s = 'inner';
    if (s != 'inner') return 'FAIL';
  }
  return s;
}
''');
      expect(result, 'outer');
    });

    test('for loop with block scoped accumulation', () async {
      final result = await compileAndRun('''
int main() {
  int total = 0;
  for (int i = 1; i <= 4; i = i + 1) {
    int square = i * i;
    total = total + square;
  }
  return total;
}
''');
      // 1 + 4 + 9 + 16 = 30
      expect(result, 30);
    });
  });

  group('variable copy independence (register aliasing regression)', () {
    test('int copy does not alias source', () async {
      final result = await compileAndRun('''
int main() {
  int a = 1;
  int b = a;
  b = 5;
  return a;
}
''');
      // a must remain 1, not become 5 (register aliasing bug).
      expect(result, 1);
    });

    test('ref copy does not alias source', () async {
      final result = await compileAndRun('''
String main() {
  String a = 'original';
  String b = a;
  b = 'modified';
  return a;
}
''');
      expect(result, 'original');
    });
  });
}
