import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end tests for the factory/callback pattern used in co19 tests:
/// Dart source -> CFE -> DarticCompiler -> DarticInterpreter.
///
/// Covers: functions passed as parameters, lambdas as arguments, factory
/// functions creating objects, callback-based test patterns, multiple
/// callbacks, and factory patterns combined with Expect assertions.
void main() {
  group('function passed as parameter', () {
    test('named function passed to higher-order function', () async {
      final result = await compileAndRun('''
int applyFn(int Function(int) fn, int x) => fn(x);
int doubleIt(int x) => x * 2;
int main() => applyFn(doubleIt, 5);
''');
      expect(result, 10);
    });
  });

  group('lambda/closure as parameter', () {
    test('lambda passed to higher-order function', () async {
      final result = await compileAndRun('''
int applyFn(int Function(int) fn, int x) => fn(x);
int main() => applyFn((x) => x * 3, 7);
''');
      expect(result, 21);
    });
  });

  group('factory function creating objects', () {
    test('factory function passed as parameter creates instance', () async {
      final result = await compileAndRun('''
class Box {
  int value;
  Box(this.value);
  int get() => value;
}

Box createBox(int v) => Box(v);

int test(Box Function(int) factory) {
  var b = factory(42);
  return b.get();
}

int main() => test(createBox);
''');
      expect(result, 42);
    });
  });

  group('callback-based test pattern', () {
    test('co19-style test(Factory create) pattern', () async {
      final result = await compileAndRun('''
class Pair {
  int x;
  int y;
  Pair(this.x, this.y);
  int sum() => x + y;
}

void check(Pair Function(int, int) create) {
  var p = create(3, 4);
  if (p.sum() != 7) {
    throw "Expected 7";
  }
}

int main() {
  check((a, b) => Pair(a, b));
  return 0;
}
''');
      expect(result, 0);
    });
  });

  group('multiple callbacks combined', () {
    test('two function parameters composed', () async {
      final result = await compileAndRun('''
int compute(int Function(int) f, int Function(int) g, int x) => f(g(x));
int main() => compute((x) => x + 1, (x) => x * 2, 5);
''');
      // (5*2)+1 = 11
      expect(result, 11);
    });
  });

  group('factory with Expect-style assertions', () {
    test('factory pattern combined with Expect class', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'expect.dart';

class Box {
  int value;
  Box(this.value);
}

void test(Box Function(int) create) {
  var b = create(42);
  Expect.equals(42, b.value);
}

int main() {
  test((v) => Box(v));
  return 0;
}
''',
        'expect.dart': '''
void _fail(String message) {
  throw ExpectException(message);
}

class Expect {
  static void equals(Object? expected, Object? actual) {
    if (expected != actual) {
      _fail('Expect.equals fails');
    }
  }
}

class ExpectException {
  String? message;
  ExpectException(this.message);
  String toString() => message ?? '';
}
''',
      });
      expect(result, 0);
    });
  });
}
