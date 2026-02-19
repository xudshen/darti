import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

/// End-to-end tests for default parameter values.
///
/// Full pipeline: Dart source -> CFE (.dill) -> DarticCompiler -> DarticInterpreter.
void main() {
  group('default value for optional positional', () {
    test('int default value', () async {
      final result = await compileAndRun('''
int f([int x = 42]) => x;
int main() => f();
''');
      expect(result, 42);
    });

    test('bool default value true', () async {
      // true = 1, false = 0 in value stack
      final result = await compileAndRun('''
int f([bool x = true]) => x ? 1 : 0;
int main() => f();
''');
      expect(result, 1);
    });

    test('bool default value false', () async {
      final result = await compileAndRun('''
int f([bool x = false]) => x ? 1 : 0;
int main() => f();
''');
      expect(result, 0);
    });

    test('multiple params with different int defaults', () async {
      final result = await compileAndRun('''
int f([int a = 1, int b = 2, int c = 3]) => a * 100 + b * 10 + c;
int main() => f();
''');
      expect(result, 123);
    });

    test('partially provided overrides defaults', () async {
      final result = await compileAndRun('''
int f([int a = 1, int b = 2, int c = 3]) => a * 100 + b * 10 + c;
int main() => f(9);
''');
      expect(result, 923);
    });
  });

  group('default value for named params', () {
    test('int default value', () async {
      final result = await compileAndRun('''
int f({int x = 42}) => x;
int main() => f();
''');
      expect(result, 42);
    });

    test('multiple named params with defaults', () async {
      final result = await compileAndRun('''
int f({int a = 5, int b = 10}) => a + b;
int main() => f();
''');
      expect(result, 15);
    });

    test('override one default keep another', () async {
      final result = await compileAndRun('''
int f({int a = 5, int b = 10}) => a + b;
int main() => f(a: 100);
''');
      expect(result, 110);
    });

    test('negative int default', () async {
      final result = await compileAndRun('''
int f({int x = -1}) => x;
int main() => f();
''');
      expect(result, -1);
    });

    test('zero default', () async {
      final result = await compileAndRun('''
int f({int x = 0}) => x;
int main() => f();
''');
      expect(result, 0);
    });
  });
}
