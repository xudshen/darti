import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end tests for first-class function values: Dart source -> CFE ->
/// DarticCompiler -> DarticInterpreter.
///
/// Covers: FunctionDeclaration (local named), FunctionExpression (lambda),
/// function as argument, function as return value, StaticTearOff, and
/// higher-order function composition.
void main() {
  group('FunctionDeclaration (local named function)', () {
    test('local function called and returns value', () async {
      final result = await compileAndRun('''
int f() {
  int g(int x) => x * 2;
  return g(5);
}
int main() => f();
''');
      expect(result, 10);
    });
  });

  group('FunctionExpression (anonymous function / lambda)', () {
    test('lambda assigned to variable and called', () async {
      final result = await compileAndRun('''
int f() {
  var g = (int x) => x + 1;
  return g(3);
}
int main() => f();
''');
      expect(result, 4);
    });
  });

  group('function as argument', () {
    test('pass lambda to higher-order function', () async {
      final result = await compileAndRun('''
int apply(int Function(int) fn, int x) => fn(x);
int f() => apply((x) => x * 3, 7);
int main() => f();
''');
      expect(result, 21);
    });
  });

  group('function as return value', () {
    test('function returns a closure that is then called', () async {
      final result = await compileAndRun('''
int Function(int) maker() {
  return (int x) => x + 10;
}
int main() {
  var g = maker();
  return g(5);
}
''');
      expect(result, 15);
    });
  });

  group('StaticTearOff', () {
    test('top-level function assigned to variable and called', () async {
      final result = await compileAndRun('''
int add(int a, int b) => a + b;
int main() {
  var f = add;
  return f(1, 2);
}
''');
      expect(result, 3);
    });
  });

  group('higher-order function composition', () {
    test('compose two functions via closures', () async {
      final result = await compileAndRun('''
int Function(int) compose(int Function(int) f, int Function(int) g) {
  return (int x) => f(g(x));
}
int double_(int x) => x * 2;
int addThree(int x) => x + 3;
int main() {
  var h = compose(double_, addThree);
  return h(4);
}
''');
      // h(4) = double_(addThree(4)) = double_(7) = 14
      expect(result, 14);
    });
  });
}
