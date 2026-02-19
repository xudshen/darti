import 'package:test/test.dart';

import '../helpers/compile_helper.dart';

void main() {
  group('multi-file: library with part files', () {
    test('part file function called from main library', () async {
      final result = await compileAndRunMultiFile(
        {
          'main.dart': '''
import 'lib.dart';

int main() => mainFunc();
''',
          'lib.dart': '''
library my_lib;
part 'part_a.dart';

int mainFunc() => partFunc() + 10;
''',
          'part_a.dart': '''
part of 'lib.dart';

int partFunc() => 42;
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 52);
    });

    test('part file with class declaration', () async {
      final result = await compileAndRunMultiFile(
        {
          'main.dart': '''
import 'lib.dart';

int main() {
  var c = Counter(10);
  c.increment();
  c.increment();
  return c.increment();
}
''',
          'lib.dart': '''
library my_lib;
part 'models.dart';
''',
          'models.dart': '''
part of 'lib.dart';

class Counter {
  int value;
  Counter(this.value);
  int increment() {
    value = value + 1;
    return value;
  }
}
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 13);
    });
  });

  group('multi-file: multiple libraries with cross-references', () {
    test('two independent libraries imported by main', () async {
      final result = await compileAndRunMultiFile(
        {
          'main.dart': '''
import 'math_lib.dart';

int main() => square(5);
''',
          'math_lib.dart': '''
int square(int x) => x * x;
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 25);
    });

    test('two libraries both imported by main', () async {
      final result = await compileAndRunMultiFile(
        {
          'main.dart': '''
import 'math_lib.dart';
import 'util_lib.dart';

int main() => square(3) + double2(4);
''',
          'math_lib.dart': '''
int square(int x) => x * x;
''',
          'util_lib.dart': '''
int double2(int x) => x * 2;
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 17); // 9 + 8
    });
  });

  group('multi-file: library with multiple part files', () {
    test('one library split across two parts', () async {
      final result = await compileAndRunMultiFile(
        {
          'main.dart': '''
import 'lib.dart';

int main() => getSum();
''',
          'lib.dart': '''
library multi_part;
part 'part1.dart';
part 'part2.dart';
''',
          'part1.dart': '''
part of 'lib.dart';

int getA() => 100;
''',
          'part2.dart': '''
part of 'lib.dart';

int getB() => 200;
int getSum() => getA() + getB();
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 300);
    });
  });

  group('multi-file: part file accessing main library declarations', () {
    test('part file calls function from main library', () async {
      final result = await compileAndRunMultiFile(
        {
          'main.dart': '''
import 'lib.dart';

int main() => computed();
''',
          'lib.dart': '''
library my_lib;
part 'helper.dart';

int baseValue() => 10;
''',
          'helper.dart': '''
part of 'lib.dart';

int computed() => baseValue() * 3;
''',
        },
        mainFile: 'main.dart',
      );
      expect(result, 30);
    });
  });
}
