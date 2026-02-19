import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('relative import paths', () {
    test('simple relative import with parent directory', () async {
      final result = await compileAndRunMultiFile(
        {
          'lib/helper.dart': '''
int add(int a, int b) => a + b;
''',
          'test/main.dart': '''
import '../lib/helper.dart';

int main() => add(3, 4);
''',
        },
        mainFile: 'test/main.dart',
      );
      expect(result, 7);
    });

    test('nested relative import (A -> B -> C)', () async {
      final result = await compileAndRunMultiFile(
        {
          'utils/math.dart': '''
int square(int x) => x * x;
''',
          'utils/helpers.dart': '''
import 'math.dart';

int squarePlus(int x, int y) => square(x) + y;
''',
          'main.dart': '''
import 'utils/helpers.dart';

int main() => squarePlus(5, 3);
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 28); // 5*5 + 3
    });

    test('import with class from subdirectory', () async {
      final result = await compileAndRunMultiFile(
        {
          'models/point.dart': '''
class Point {
  int x;
  int y;
  Point(this.x, this.y);
  int sum() => x + y;
}
''',
          'main.dart': '''
import 'models/point.dart';

int main() {
  final p = Point(10, 20);
  return p.sum();
}
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 30);
    });

    test('cross-library function calls from two files', () async {
      final result = await compileAndRunMultiFile(
        {
          'lib_a.dart': '''
int doubleVal(int x) => x * 2;
''',
          'lib_b.dart': '''
int tripleVal(int x) => x * 3;
''',
          'main.dart': '''
import 'lib_a.dart';
import 'lib_b.dart';

int main() => doubleVal(3) + tripleVal(3);
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 15); // 6 + 9
    });
  });
}
