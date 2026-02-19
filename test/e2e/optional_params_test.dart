import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end tests for optional positional and named parameters.
///
/// Full pipeline: Dart source -> CFE (.dill) -> DarticCompiler -> DarticInterpreter.
void main() {
  group('optional positional parameters', () {
    test('one optional param omitted uses default', () async {
      final result = await compileAndRun('''
int f(int a, [int b = 0]) => a + b;
int main() => f(5);
''');
      expect(result, 5);
    });

    test('one optional param provided', () async {
      final result = await compileAndRun('''
int f(int a, [int b = 0]) => a + b;
int main() => f(5, 3);
''');
      expect(result, 8);
    });

    test('multiple optional params all omitted', () async {
      final result = await compileAndRun('''
int g(int a, [int b = 10, int c = 20]) => a + b + c;
int main() => g(1);
''');
      expect(result, 31);
    });

    test('multiple optional params one provided', () async {
      final result = await compileAndRun('''
int g(int a, [int b = 10, int c = 20]) => a + b + c;
int main() => g(1, 2);
''');
      expect(result, 23);
    });

    test('multiple optional params all provided', () async {
      final result = await compileAndRun('''
int g(int a, [int b = 10, int c = 20]) => a + b + c;
int main() => g(1, 2, 3);
''');
      expect(result, 6);
    });

    test('no required params only optional', () async {
      final result = await compileAndRun('''
int f([int x = 7, int y = 3]) => x + y;
int main() => f();
''');
      expect(result, 10);
    });
  });

  group('named parameters', () {
    test('one named param omitted uses default', () async {
      final result = await compileAndRun('''
int h(int a, {int b = 0}) => a + b;
int main() => h(5);
''');
      expect(result, 5);
    });

    test('one named param provided', () async {
      final result = await compileAndRun('''
int h(int a, {int b = 0}) => a + b;
int main() => h(5, b: 3);
''');
      expect(result, 8);
    });

    test('multiple named params only some provided', () async {
      final result = await compileAndRun('''
int k({int a = 1, int b = 2, int c = 3}) => a + b + c;
int main() => k(b: 10);
''');
      expect(result, 14);
    });

    test('multiple named params all provided', () async {
      final result = await compileAndRun('''
int k({int a = 1, int b = 2, int c = 3}) => a + b + c;
int main() => k(a: 10, b: 20, c: 30);
''');
      expect(result, 60);
    });

    test('required named param', () async {
      final result = await compileAndRun('''
int r({required int a}) => a * 2;
int main() => r(a: 7);
''');
      expect(result, 14);
    });

    test('named params provided in different order', () async {
      final result = await compileAndRun('''
int f({int a = 0, int b = 0, int c = 0}) => a * 100 + b * 10 + c;
int main() => f(c: 3, a: 1, b: 2);
''');
      expect(result, 123);
    });
  });

  group('mixed positional and named', () {
    test('required positional + named param', () async {
      final result = await compileAndRun('''
int f(int x, {int y = 0}) => x + y;
int main() => f(10, y: 5);
''');
      expect(result, 15);
    });

    test('required positional + named param omitted', () async {
      final result = await compileAndRun('''
int f(int x, {int y = 100}) => x + y;
int main() => f(10);
''');
      expect(result, 110);
    });
  });
}
