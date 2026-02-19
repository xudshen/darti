import 'package:dartic/src/runtime/object.dart';
import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('multi-library import/export', () {
    test('multi-file function call', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'helper.dart';

int main() => add(3, 4);
''',
        'helper.dart': '''
int add(int a, int b) => a + b;
''',
      });
      expect(result, 7);
    });

    test('cross-library class usage', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'lib_a.dart';

Object main() => Point(10, 20);
''',
        'lib_a.dart': '''
class Point {
  int x;
  int y;
  Point(this.x, this.y);
}
''',
      });
      final obj = result as DarticObject;
      expect(obj.valueFields[0], 10);
      expect(obj.valueFields[1], 20);
    });

    test('private visibility across libraries', () async {
      // _privateFn is defined in helper.dart but main.dart calls publicFn
      // which internally uses _privateFn. This verifies cross-library
      // private members work correctly (CFE resolves visibility).
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'helper.dart';

int main() => publicFn(5);
''',
        'helper.dart': '''
int _privateFn(int x) => x * 2;
int publicFn(int x) => _privateFn(x) + 1;
''',
      });
      expect(result, 11); // 5 * 2 + 1
    });

    test('multiple imports', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'lib_a.dart';
import 'lib_b.dart';

int main() => addA(2, 3) + mulB(4, 5);
''',
        'lib_a.dart': '''
int addA(int a, int b) => a + b;
''',
        'lib_b.dart': '''
int mulB(int a, int b) => a * b;
''',
      });
      expect(result, 25); // (2+3) + (4*5) = 5 + 20
    });

    test('same-name top-level in different libraries', () async {
      // Both libraries define a top-level `value`, but they should not
      // conflict since they are in separate library scopes.
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'lib_a.dart' as a;
import 'lib_b.dart' as b;

int main() => a.value + b.value;
''',
        'lib_a.dart': '''
int value = 10;
''',
        'lib_b.dart': '''
int value = 32;
''',
      });
      expect(result, 42); // 10 + 32
    });

    test('cross-library method calls', () async {
      final result = await compileAndRunMultiFile({
        'main.dart': '''
import 'lib_a.dart';

int main() {
  final c = Counter(5);
  c.increment();
  c.increment();
  c.increment();
  return c.getValue();
}
''',
        'lib_a.dart': '''
class Counter {
  int _count;
  Counter(this._count);
  void increment() { _count = _count + 1; }
  int getValue() => _count;
}
''',
      });
      expect(result, 8); // 5 + 3
    });
  });
}
